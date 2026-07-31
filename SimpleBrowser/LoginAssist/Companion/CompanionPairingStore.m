#import "CompanionPairingStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString * const kCompanionKeychainService = @"MeoBrowser.LoginAssist.Companion";
static NSString * const kCompanionKeychainAccount = @"paired-devices";
static NSString * const kPendingCodeKey = @"CompanionPendingPairingCode";
static NSString * const kPendingExpiresKey = @"CompanionPendingPairingExpiresAt";
static NSString * const kAuthModeKey = @"CompanionAuthMode";
static NSString * const kSecurityCodeKey = @"CompanionSecurityCode";
static NSString * const kStickyPortKey = @"CompanionStickyListeningPort";
/// 启动态文案用；避免为「已配对 N 台」在冷启动就读钥匙串。
static NSString * const kPairedDeviceCountKey = @"CompanionPairedDeviceCount";
/// 非机密 deviceId 列表；启动邀请发现用，避免为白名单读钥匙串。
static NSString * const kPairedDeviceIdsKey = @"CompanionPairedDeviceIds";
/// deviceId → SHA256(token) 指纹；hello 校验用，冷启动不读钥匙串。
static NSString * const kPairedDeviceTokenFingerprintsKey = @"CompanionPairedDeviceTokenFingerprints";
/// 旧版钥匙串是否已尝试迁移（成功或确认无数据后置位，避免反复弹窗）。
static NSString * const kCompanionKeychainMigratedKey = @"CompanionPairedDevicesKeychainMigrated";

static NSString *CompanionTokenFingerprint(NSString *token) {
    if (token.length == 0) {
        return @"";
    }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static dispatch_queue_t CompanionKeychainMigrateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("meobrowser.companion.keychain-migrate", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@implementation CompanionPairedDevice
@end

@interface CompanionPairingStore ()
@property (nonatomic, copy, readwrite, nullable) NSString *pendingPairingCode;
@property (nonatomic, assign, readwrite) NSTimeInterval pendingPairingExpiresAt;
@property (nonatomic, copy, readwrite, nullable) NSString *securityCode;
@property (nonatomic, copy) NSArray<CompanionPairedDevice *> *pairedDevicesStorage;
@property (nonatomic, assign) BOOL devicesLoaded;
@property (nonatomic, assign) BOOL keychainMigrationInFlight;
@end

@implementation CompanionPairingStore

+ (instancetype)sharedStore {
    static CompanionPairingStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (NSString *)pairedDevicesFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"LoginAssist"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"companion-paired-devices.json"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 冷启动只读本地文件 / UserDefaults；旧钥匙串迁移放到后台，避免卡住主线程。
        _pairedDevicesStorage = @[];
        _devicesLoaded = NO;
        _keychainMigrationInFlight = NO;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _pendingPairingCode = [defaults stringForKey:kPendingCodeKey];
        _pendingPairingExpiresAt = [defaults doubleForKey:kPendingExpiresKey];
        _securityCode = [defaults stringForKey:kSecurityCodeKey];
        _authMode = (CompanionAuthMode)[defaults integerForKey:kAuthModeKey];
        if (_authMode != CompanionAuthModeSecurityCode) {
            _authMode = CompanionAuthModePairingCode;
        }
        _stickyListeningPort = [defaults integerForKey:kStickyPortKey];
        [self ensureDevicesLoaded];
    }
    return self;
}

- (NSUInteger)pairedDeviceCountHint {
    if (self.devicesLoaded) {
        return self.pairedDevicesStorage.count;
    }
    NSInteger stored = [NSUserDefaults.standardUserDefaults integerForKey:kPairedDeviceCountKey];
    return stored > 0 ? (NSUInteger)stored : 0;
}

- (void)syncPairedDeviceCountHint {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:(NSInteger)self.pairedDevicesStorage.count forKey:kPairedDeviceCountKey];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *fingerprints = [NSMutableDictionary dictionary];
    for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
        if (device.deviceId.length > 0) {
            [ids addObject:device.deviceId];
            if (device.deviceToken.length > 0) {
                fingerprints[device.deviceId] = CompanionTokenFingerprint(device.deviceToken);
            }
        }
    }
    [defaults setObject:ids forKey:kPairedDeviceIdsKey];
    [defaults setObject:fingerprints forKey:kPairedDeviceTokenFingerprintsKey];
}

- (NSDictionary<NSString *, NSString *> *)storedTokenFingerprints {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPairedDeviceTokenFingerprintsKey];
    if (![stored isKindOfClass:[NSDictionary class]] || stored.count == 0) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    [stored enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]] &&
            [(NSString *)key length] > 0 && [(NSString *)obj length] > 0) {
            out[key] = obj;
        }
    }];
    return out;
}

- (BOOL)validateDeviceTokenAgainstFingerprints:(NSString *)deviceToken deviceId:(NSString *)deviceId {
    NSString *fp = CompanionTokenFingerprint(deviceToken);
    if (fp.length == 0) {
        return NO;
    }
    NSDictionary<NSString *, NSString *> *fingerprints = [self storedTokenFingerprints];
    if (fingerprints.count == 0) {
        return NO;
    }
    if (deviceId.length > 0) {
        return [fingerprints[deviceId] isEqualToString:fp];
    }
    for (NSString *stored in fingerprints.allValues) {
        if ([stored isEqualToString:fp]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSString *> *)pairedDeviceIdHints {
    if (self.devicesLoaded) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
            if (device.deviceId.length > 0) {
                [ids addObject:device.deviceId];
            }
        }
        return ids;
    }
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kPairedDeviceIdsKey];
    if (![stored isKindOfClass:[NSArray class]] || stored.count == 0) {
        return @[];
    }
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) {
            [ids addObject:item];
        }
    }
    return ids;
}

- (NSArray<CompanionPairedDevice *> *)devicesFromJSONData:(NSData *)data {
    if (data.length == 0) {
        return @[];
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<CompanionPairedDevice *> *devices = [NSMutableArray array];
    for (id item in (NSArray *)json) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = item;
        NSString *deviceId = dict[@"deviceId"];
        NSString *token = dict[@"deviceToken"];
        if (![deviceId isKindOfClass:[NSString class]] || ![token isKindOfClass:[NSString class]]) {
            continue;
        }
        CompanionPairedDevice *device = [[CompanionPairedDevice alloc] init];
        device.deviceId = deviceId;
        device.deviceToken = token;
        device.displayName = [dict[@"displayName"] isKindOfClass:[NSString class]] ? dict[@"displayName"] : nil;
        device.pairedAt = [dict[@"pairedAt"] doubleValue];
        [devices addObject:device];
    }
    return devices;
}

- (void)ensureDevicesLoaded {
    if (self.devicesLoaded) {
        return;
    }
    self.devicesLoaded = YES;
    NSString *path = [[self class] pairedDevicesFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length > 0) {
        self.pairedDevicesStorage = [self devicesFromJSONData:data];
        [self syncPairedDeviceCountHint];
        // 文件已是权威来源：标记迁移完成，并在后台静默删除旧钥匙串项。
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kCompanionKeychainMigratedKey];
        dispatch_async(CompanionKeychainMigrateQueue(), ^{
            NSDictionary *del = @{
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService: kCompanionKeychainService,
                (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
            };
            SecItemDelete((__bridge CFDictionaryRef)del);
        });
        return;
    }
    self.pairedDevicesStorage = @[];
}

- (NSArray<CompanionPairedDevice *> *)pairedDevices {
    [self ensureDevicesLoaded];
    return self.pairedDevicesStorage ?: @[];
}

- (void)setAuthMode:(CompanionAuthMode)authMode {
    if (_authMode == authMode) {
        return;
    }
    _authMode = authMode;
    [NSUserDefaults.standardUserDefaults setInteger:authMode forKey:kAuthModeKey];
}

- (void)setStickyListeningPort:(NSInteger)stickyListeningPort {
    if (_stickyListeningPort == stickyListeningPort) {
        return;
    }
    _stickyListeningPort = stickyListeningPort;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (stickyListeningPort > 0) {
        [defaults setInteger:stickyListeningPort forKey:kStickyPortKey];
    } else {
        [defaults removeObjectForKey:kStickyPortKey];
    }
}

- (BOOL)persistDevices:(NSError **)error {
    [self ensureDevicesLoaded];
    NSMutableArray *list = [NSMutableArray array];
    for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
        NSMutableDictionary *dict = [@{
            @"deviceId": device.deviceId ?: @"",
            @"deviceToken": device.deviceToken ?: @"",
            @"pairedAt": @(device.pairedAt),
        } mutableCopy];
        if (device.displayName.length > 0) {
            dict[@"displayName"] = device.displayName;
        }
        [list addObject:dict];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:NSJSONWritingPrettyPrinted error:error];
    if (!data) {
        return NO;
    }
    NSString *path = [[self class] pairedDevicesFilePath];
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    // 限制为本用户可读，降低明文 token 落盘风险。
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path
                                            error:nil];
    [self syncPairedDeviceCountHint];
    return YES;
}

#pragma mark - Legacy Keychain migration (background only)

- (void)scheduleKeychainMigrationIfNeeded {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kCompanionKeychainMigratedKey]) {
        return;
    }
    if (self.keychainMigrationInFlight) {
        return;
    }
    self.keychainMigrationInFlight = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(CompanionKeychainMigrateQueue(), ^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kCompanionKeychainService,
            (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        };
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        NSData *data = nil;
        if (status == errSecSuccess && result) {
            data = CFBridgingRelease(result);
        } else if (result) {
            CFRelease(result);
        }

        // 删除旧项：成功读到、或不存在、或用户拒绝后也不再反复弹。
        NSDictionary *del = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kCompanionKeychainService,
            (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
        };
        if (status == errSecSuccess || status == errSecItemNotFound) {
            SecItemDelete((__bridge CFDictionaryRef)del);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            self.keychainMigrationInFlight = NO;
            if (data.length > 0) {
                NSArray<CompanionPairedDevice *> *migrated = [self devicesFromJSONData:data];
                [self mergeMigratedDevices:migrated];
            }
            // 用户取消（interaction not allowed / auth failed）时不置位，下次还可再试；
            // 无数据或已成功则置位，避免连接路径再碰钥匙串。
            if (status == errSecSuccess || status == errSecItemNotFound) {
                [NSUserDefaults.standardUserDefaults setBool:YES forKey:kCompanionKeychainMigratedKey];
                // 已有文件权威数据时，再删一次钥匙串（后台）。
                dispatch_async(CompanionKeychainMigrateQueue(), ^{
                    SecItemDelete((__bridge CFDictionaryRef)del);
                });
            }
        });
    });
}

- (void)mergeMigratedDevices:(NSArray<CompanionPairedDevice *> *)migrated {
    if (migrated.count == 0) {
        return;
    }
    [self ensureDevicesLoaded];
    NSMutableDictionary<NSString *, CompanionPairedDevice *> *byId = [NSMutableDictionary dictionary];
    for (CompanionPairedDevice *device in migrated) {
        if (device.deviceId.length > 0) {
            byId[device.deviceId] = device;
        }
    }
    // 内存/文件里已有的（例如迁移期间新配对）优先。
    for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
        if (device.deviceId.length > 0) {
            byId[device.deviceId] = device;
        }
    }
    self.pairedDevicesStorage = byId.allValues ?: @[];
    [self persistDevices:nil];
}

- (NSString *)refreshPendingPairingCode {
    uint32_t value = 0;
    int result = SecRandomCopyBytes(kSecRandomDefault, sizeof(value), (uint8_t *)&value);
    if (result != errSecSuccess) {
        value = (uint32_t)arc4random_uniform(1000000);
    }
    NSString *code = [NSString stringWithFormat:@"%06u", value % 1000000u];
    self.pendingPairingCode = code;
    self.pendingPairingExpiresAt = [NSDate date].timeIntervalSince1970 + 5 * 60;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:code forKey:kPendingCodeKey];
    [defaults setDouble:self.pendingPairingExpiresAt forKey:kPendingExpiresKey];
    return code;
}

- (BOOL)isPendingPairingCodeValid:(NSString *)code {
    if (code.length == 0 || self.pendingPairingCode.length == 0) {
        return NO;
    }
    if ([NSDate date].timeIntervalSince1970 > self.pendingPairingExpiresAt) {
        return NO;
    }
    return [code isEqualToString:self.pendingPairingCode];
}

- (BOOL)setSecurityCode:(NSString *)code error:(NSError **)error {
    NSString *trimmed = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.securityCode = nil;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kSecurityCodeKey];
        return YES;
    }
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSCharacterSet *inverted = [allowed invertedSet];
    if (trimmed.length < 4 || trimmed.length > 12 || [trimmed rangeOfCharacterFromSet:inverted].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"CompanionPairingStore"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"安全码需为 4～12 位字母或数字"}];
        }
        return NO;
    }
    self.securityCode = trimmed;
    [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:kSecurityCodeKey];
    return YES;
}

- (BOOL)isSecurityCodeValid:(NSString *)code {
    if (code.length == 0 || self.securityCode.length == 0) {
        return NO;
    }
    return [code isEqualToString:self.securityCode];
}

- (NSString *)issueDeviceTokenForDeviceId:(NSString *)deviceId
                              pairingCode:(NSString *)pairingCode
                                    error:(NSError **)error {
    if (deviceId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CompanionPairingStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 deviceId"}];
        }
        return nil;
    }

    BOOL securityMode = (self.authMode == CompanionAuthModeSecurityCode);
    if (securityMode) {
        if (![self isSecurityCodeValid:pairingCode]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CompanionPairingStore"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"安全码不正确"}];
            }
            return nil;
        }
    } else {
        if (![self isPendingPairingCodeValid:pairingCode]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CompanionPairingStore"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"配对码无效或已过期"}];
            }
            return nil;
        }
    }

    NSString *token = [[NSUUID UUID] UUIDString];
    [self ensureDevicesLoaded];
    NSMutableArray<CompanionPairedDevice *> *devices = [self.pairedDevicesStorage mutableCopy] ?: [NSMutableArray array];
    CompanionPairedDevice *existing = nil;
    for (CompanionPairedDevice *device in devices) {
        if ([device.deviceId isEqualToString:deviceId]) {
            existing = device;
            break;
        }
    }
    if (!existing) {
        existing = [[CompanionPairedDevice alloc] init];
        existing.deviceId = deviceId;
        [devices addObject:existing];
    }
    existing.deviceToken = token;
    existing.pairedAt = [NSDate date].timeIntervalSince1970;
    self.pairedDevicesStorage = devices;
    if (![self persistDevices:error]) {
        return nil;
    }

    // 临时配对码一次性；固定安全码保持不变，便于手机下次自动连接。
    if (!securityMode) {
        self.pendingPairingCode = nil;
        self.pendingPairingExpiresAt = 0;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kPendingCodeKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kPendingExpiresKey];
    }
    return token;
}

- (BOOL)validateDeviceToken:(NSString *)deviceToken deviceId:(NSString *)deviceId {
    if (deviceToken.length == 0) {
        return NO;
    }
    // 指纹优先：不读文件/钥匙串也能放行已配对手机。
    if ([self validateDeviceTokenAgainstFingerprints:deviceToken deviceId:deviceId]) {
        return YES;
    }
    [self ensureDevicesLoaded];
    for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
        if (![device.deviceToken isEqualToString:deviceToken]) {
            continue;
        }
        if (deviceId.length > 0 && ![device.deviceId isEqualToString:deviceId]) {
            return NO;
        }
        [self syncPairedDeviceCountHint];
        return YES;
    }
    // 文件尚空且可能仍在后台迁移：触发迁移，本次先拒绝（手机可重试 hello）。
    if (self.pairedDevicesStorage.count == 0 &&
        ![NSUserDefaults.standardUserDefaults boolForKey:kCompanionKeychainMigratedKey]) {
        [self scheduleKeychainMigrationIfNeeded];
    }
    return NO;
}

- (void)revokeAllDevices {
    [self ensureDevicesLoaded];
    self.pairedDevicesStorage = @[];
    [self persistDevices:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPairedDeviceTokenFingerprintsKey];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kCompanionKeychainMigratedKey];
    dispatch_async(CompanionKeychainMigrateQueue(), ^{
        NSDictionary *del = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kCompanionKeychainService,
            (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
        };
        SecItemDelete((__bridge CFDictionaryRef)del);
    });
}

- (void)revokeDeviceToken:(NSString *)deviceToken {
    if (deviceToken.length == 0) {
        return;
    }
    [self ensureDevicesLoaded];
    NSMutableArray *devices = [NSMutableArray array];
    for (CompanionPairedDevice *device in self.pairedDevicesStorage) {
        if (![device.deviceToken isEqualToString:deviceToken]) {
            [devices addObject:device];
        }
    }
    self.pairedDevicesStorage = devices;
    [self persistDevices:nil];
}

@end
