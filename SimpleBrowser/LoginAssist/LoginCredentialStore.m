#import "LoginCredentialStore.h"
#import <Security/Security.h>

NSErrorDomain const LoginCredentialStoreErrorDomain = @"LoginCredentialStore";
const NSInteger LoginCredentialStoreErrorBusy = 4;

static NSString * const kLegacyKeychainService = @"MeoBrowser.LoginAssist";
static NSString * const kKeychainMigratedKey = @"LoginAssistCredentialsKeychainMigrated";

static dispatch_queue_t LoginCredentialMigrateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("meobrowser.login-credential.migrate", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@implementation LoginCredentials
- (instancetype)init {
    self = [super init];
    if (self) {
        _username = @"";
        _password = @"";
        _phone = @"";
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone {
    (void)zone;
    LoginCredentials *copy = [[LoginCredentials alloc] init];
    copy.username = self.username;
    copy.password = self.password;
    copy.phone = self.phone;
    return copy;
}
@end

@interface LoginCredentialStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, LoginCredentials *> *credentialsByRecipeID;
@property (nonatomic, copy) NSString *storePath;
@property (nonatomic, assign) BOOL keychainMigrationInFlight;
@end

@implementation LoginCredentialStore

+ (instancetype)sharedStore {
    static LoginCredentialStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (NSString *)credentialsFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"LoginAssist"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"credentials.json"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _credentialsByRecipeID = [NSMutableDictionary dictionary];
        _storePath = [[self class] credentialsFilePath];
        [self loadFromDisk];
        // 热路径只走本地文件；旧钥匙串仅后台一次性迁移，避免登录页反复弹授权框。
        [self scheduleKeychainMigrationIfNeeded];
    }
    return self;
}

#pragma mark - Disk

- (void)loadFromDisk {
    [self.credentialsByRecipeID removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data.length) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id map = json[@"credentials"];
    if (![map isKindOfClass:[NSDictionary class]]) {
        return;
    }
    for (id key in map) {
        if (![key isKindOfClass:[NSString class]] || [(NSString *)key length] == 0) {
            continue;
        }
        id payload = map[key];
        if (![payload isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        LoginCredentials *credentials = [self credentialsFromPayload:payload];
        self.credentialsByRecipeID[key] = credentials;
    }
}

- (LoginCredentials *)credentialsFromPayload:(NSDictionary *)payload {
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    id username = payload[@"username"];
    id password = payload[@"password"];
    id phone = payload[@"phone"];
    credentials.username = [username isKindOfClass:[NSString class]] ? username : @"";
    credentials.password = [password isKindOfClass:[NSString class]] ? password : @"";
    credentials.phone = [phone isKindOfClass:[NSString class]] ? phone : @"";
    return credentials;
}

- (BOOL)persist:(NSError **)error {
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:self.credentialsByRecipeID.count];
    for (NSString *recipeID in self.credentialsByRecipeID) {
        LoginCredentials *credentials = self.credentialsByRecipeID[recipeID];
        map[recipeID] = @{
            @"username": credentials.username ?: @"",
            @"password": credentials.password ?: @"",
            @"phone": credentials.phone ?: @"",
        };
    }
    NSDictionary *root = @{
        @"version": @1,
        @"credentials": map,
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError ?: [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无法编码凭证"}];
        }
        return NO;
    }
    if (![data writeToFile:self.storePath options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:self.storePath
                                            error:nil];
    return YES;
}

#pragma mark - Public API

- (BOOL)saveUsername:(NSString *)username
            password:(NSString *)password
         forRecipeID:(NSString *)recipeID
               error:(NSError **)error {
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = username ?: @"";
    credentials.password = password ?: @"";
    LoginCredentials *existing = [self loadCredentialsForRecipeID:recipeID error:nil];
    if (existing) {
        credentials.phone = existing.phone ?: @"";
    }
    return [self saveCredentials:credentials forRecipeID:recipeID error:error];
}

- (BOOL)saveCredentials:(LoginCredentials *)credentials
            forRecipeID:(NSString *)recipeID
                  error:(NSError **)error {
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return NO;
    }
    if (!credentials) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少凭证"}];
        }
        return NO;
    }
    @synchronized (self) {
        self.credentialsByRecipeID[recipeID] = [credentials copy];
        return [self persist:error];
    }
}

- (LoginCredentials *)loadCredentialsForRecipeID:(NSString *)recipeID error:(NSError **)error {
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return nil;
    }
    @synchronized (self) {
        LoginCredentials *cached = self.credentialsByRecipeID[recipeID];
        if (cached) {
            return [cached copy];
        }
        // 无记录视为空凭证（与旧钥匙串「item not found」语义一致）。
        LoginCredentials *empty = [[LoginCredentials alloc] init];
        return empty;
    }
}

- (void)loadCredentialsForRecipeID:(NSString *)recipeID
                        completion:(void (^)(LoginCredentials * _Nullable, NSError * _Nullable))completion {
    if (!completion) {
        return;
    }
    NSError *localError = nil;
    LoginCredentials *credentials = [self loadCredentialsForRecipeID:recipeID error:&localError];
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(credentials, localError);
    });
}

- (BOOL)loadUsername:(NSString **)username
            password:(NSString **)password
         forRecipeID:(NSString *)recipeID
               error:(NSError **)error {
    LoginCredentials *credentials = [self loadCredentialsForRecipeID:recipeID error:error];
    if (!credentials) {
        return NO;
    }
    if (username) {
        *username = credentials.username ?: @"";
    }
    if (password) {
        *password = credentials.password ?: @"";
    }
    return YES;
}

- (BOOL)deleteCredentialsForRecipeID:(NSString *)recipeID error:(NSError **)error {
    if (recipeID.length == 0) {
        return YES;
    }
    @synchronized (self) {
        [self.credentialsByRecipeID removeObjectForKey:recipeID];
        return [self persist:error];
    }
}

#pragma mark - Legacy Keychain migration (background only)

- (void)scheduleKeychainMigrationIfNeeded {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kKeychainMigratedKey]) {
        return;
    }
    if (self.keychainMigrationInFlight) {
        return;
    }
    self.keychainMigrationInFlight = YES;

    // 本地文件已是权威来源：直接置位，不再碰钥匙串（删项也可能弹授权框）。
    BOOL hasFile = [[NSFileManager defaultManager] fileExistsAtPath:self.storePath];
    if (hasFile && self.credentialsByRecipeID.count > 0) {
        [defaults setBool:YES forKey:kKeychainMigratedKey];
        self.keychainMigrationInFlight = NO;
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(LoginCredentialMigrateQueue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kLegacyKeychainService,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        };
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

        NSMutableDictionary<NSString *, LoginCredentials *> *migrated = [NSMutableDictionary dictionary];
        if (status == errSecSuccess && result) {
            NSArray *items = CFBridgingRelease(result);
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in items) {
                    if (![item isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }
                    NSDictionary *dict = (NSDictionary *)item;
                    NSString *account = dict[(__bridge id)kSecAttrAccount];
                    NSData *data = dict[(__bridge id)kSecValueData];
                    if (![account isKindOfClass:[NSString class]] || account.length == 0 || ![data isKindOfClass:[NSData class]]) {
                        continue;
                    }
                    id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (![payload isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }
                    migrated[account] = [self credentialsFromPayload:payload];
                }
            }
        } else if (result) {
            CFRelease(result);
        }

        if (status == errSecSuccess || status == errSecItemNotFound) {
            [self deleteAllLegacyKeychainItems];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) store = weakSelf;
            if (!store) {
                return;
            }
            store.keychainMigrationInFlight = NO;
            if (migrated.count > 0) {
                @synchronized (store) {
                    for (NSString *recipeID in migrated) {
                        if (!store.credentialsByRecipeID[recipeID]) {
                            store.credentialsByRecipeID[recipeID] = migrated[recipeID];
                        }
                    }
                    [store persist:nil];
                }
            }
            // 成功、无数据、或用户取消：一律置位，热路径已不碰钥匙串，避免反复弹窗。
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:kKeychainMigratedKey];
        });
    });
}

- (void)deleteAllLegacyKeychainItems {
    NSDictionary *del = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLegacyKeychainService,
    };
    SecItemDelete((__bridge CFDictionaryRef)del);
}

@end
