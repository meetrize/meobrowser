#import "CompanionPairingStore.h"
#import <Security/Security.h>

static NSString * const kCompanionKeychainService = @"MeoBrowser.LoginAssist.Companion";
static NSString * const kCompanionKeychainAccount = @"paired-devices";
static NSString * const kPendingCodeKey = @"CompanionPendingPairingCode";
static NSString * const kPendingExpiresKey = @"CompanionPendingPairingExpiresAt";
static NSString * const kAuthModeKey = @"CompanionAuthMode";
static NSString * const kSecurityCodeKey = @"CompanionSecurityCode";
static NSString * const kStickyPortKey = @"CompanionStickyListeningPort";

@implementation CompanionPairedDevice
@end

@interface CompanionPairingStore ()
@property (nonatomic, copy, readwrite, nullable) NSString *pendingPairingCode;
@property (nonatomic, assign, readwrite) NSTimeInterval pendingPairingExpiresAt;
@property (nonatomic, copy, readwrite, nullable) NSString *securityCode;
@property (nonatomic, copy, readwrite) NSArray<CompanionPairedDevice *> *pairedDevices;
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

- (instancetype)init {
    self = [super init];
    if (self) {
        _pairedDevices = @[];
        [self reloadFromKeychain];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _pendingPairingCode = [defaults stringForKey:kPendingCodeKey];
        _pendingPairingExpiresAt = [defaults doubleForKey:kPendingExpiresKey];
        _securityCode = [defaults stringForKey:kSecurityCodeKey];
        _authMode = (CompanionAuthMode)[defaults integerForKey:kAuthModeKey];
        if (_authMode != CompanionAuthModeSecurityCode) {
            _authMode = CompanionAuthModePairingCode;
        }
        _stickyListeningPort = [defaults integerForKey:kStickyPortKey];
    }
    return self;
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

- (void)reloadFromKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCompanionKeychainService,
        (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) {
        self.pairedDevices = @[];
        return;
    }
    NSData *data = CFBridgingRelease(result);
    NSArray *list = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![list isKindOfClass:[NSArray class]]) {
        self.pairedDevices = @[];
        return;
    }
    NSMutableArray<CompanionPairedDevice *> *devices = [NSMutableArray array];
    for (id item in list) {
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
    self.pairedDevices = devices;
}

- (BOOL)persistDevices:(NSError **)error {
    NSMutableArray *list = [NSMutableArray array];
    for (CompanionPairedDevice *device in self.pairedDevices) {
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
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:0 error:error];
    if (!data) {
        return NO;
    }
    NSDictionary *del = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCompanionKeychainService,
        (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
    };
    SecItemDelete((__bridge CFDictionaryRef)del);
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCompanionKeychainService,
        (__bridge id)kSecAttrAccount: kCompanionKeychainAccount,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法保存配对信息"}];
        }
        return NO;
    }
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
    NSMutableArray<CompanionPairedDevice *> *devices = [self.pairedDevices mutableCopy] ?: [NSMutableArray array];
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
    self.pairedDevices = devices;
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
    for (CompanionPairedDevice *device in self.pairedDevices) {
        if (![device.deviceToken isEqualToString:deviceToken]) {
            continue;
        }
        if (deviceId.length > 0 && ![device.deviceId isEqualToString:deviceId]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

- (void)revokeAllDevices {
    self.pairedDevices = @[];
    [self persistDevices:nil];
}

- (void)revokeDeviceToken:(NSString *)deviceToken {
    if (deviceToken.length == 0) {
        return;
    }
    NSMutableArray *devices = [NSMutableArray array];
    for (CompanionPairedDevice *device in self.pairedDevices) {
        if (![device.deviceToken isEqualToString:deviceToken]) {
            [devices addObject:device];
        }
    }
    self.pairedDevices = devices;
    [self persistDevices:nil];
}

@end
