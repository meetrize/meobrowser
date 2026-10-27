#import "CompanionPairingStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString * const kPendingCodeKey = @"CompanionPendingPairingCode";
static NSString * const kPendingExpiresKey = @"CompanionPendingPairingExpiresAt";
static NSString * const kAuthModeKey = @"CompanionAuthMode";
static NSString * const kSecurityCodeKey = @"CompanionSecurityCode";
static NSString * const kStickyPortKey = @"CompanionStickyListeningPort";
/// 启动态文案用。
static NSString * const kPairedDeviceCountKey = @"CompanionPairedDeviceCount";
/// 非机密 deviceId 列表；启动邀请发现用。
static NSString * const kPairedDeviceIdsKey = @"CompanionPairedDeviceIds";
/// deviceId → SHA256(token) 指纹；hello 校验用。
static NSString * const kPairedDeviceTokenFingerprintsKey = @"CompanionPairedDeviceTokenFingerprints";

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

@implementation CompanionPairedDevice
@end

@interface CompanionPairingStore ()
@property (nonatomic, copy, readwrite, nullable) NSString *pendingPairingCode;
@property (nonatomic, assign, readwrite) NSTimeInterval pendingPairingExpiresAt;
@property (nonatomic, copy, readwrite, nullable) NSString *securityCode;
@property (nonatomic, copy) NSArray<CompanionPairedDevice *> *pairedDevicesStorage;
@property (nonatomic, assign) BOOL devicesLoaded;
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
        // 冷启动只读本地文件 / UserDefaults。
        _pairedDevicesStorage = @[];
        _devicesLoaded = NO;
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
    return NO;
}

- (void)revokeAllDevices {
    [self ensureDevicesLoaded];
    self.pairedDevicesStorage = @[];
    [self persistDevices:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPairedDeviceTokenFingerprintsKey];
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
