#import "LoginCredentialStore.h"
#import <Security/Security.h>

static NSString * const kLoginAssistKeychainService = @"MeoBrowser.LoginAssist";

/// 钥匙串 I/O 放串行后台队列；主线程仅有限预算等待，避免无限泵 runloop。
static dispatch_queue_t LoginCredentialKeychainQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("meobrowser.login-credential.keychain", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const NSTimeInterval kLoginCredentialMainThreadBudget = 0.25;

static BOOL LoginCredentialPerformKeychain(void (^block)(void)) {
    if (!block) {
        return YES;
    }
    if (![NSThread isMainThread]) {
        dispatch_sync(LoginCredentialKeychainQueue(), block);
        return YES;
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL finished = NO;
    dispatch_async(LoginCredentialKeychainQueue(), ^{
        block();
        finished = YES;
        dispatch_semaphore_signal(sem);
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kLoginCredentialMainThreadBudget];
    while (!finished && dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        if ([deadline timeIntervalSinceNow] < 0) {
            return NO;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return finished;
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, LoginCredentials *> *memoryCache;
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

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoryCache = [NSMutableDictionary dictionary];
    }
    return self;
}

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
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return NO;
    }

    NSDictionary *payload = @{
        @"username": credentials.username ?: @"",
        @"password": credentials.password ?: @"",
        @"phone": credentials.phone ?: @"",
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError ?: [NSError errorWithDomain:@"LoginCredentialStore"
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无法编码凭证"}];
        }
        return NO;
    }

    [self deleteCredentialsForRecipeID:recipeID error:nil];

    __block OSStatus status = errSecSuccess;
    BOOL completed = LoginCredentialPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kLoginAssistKeychainService,
            (__bridge id)kSecAttrAccount: recipeID,
            (__bridge id)kSecValueData: data,
            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        };
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    });
    // 主线程超时：仍写入内存缓存；后台 SecItemAdd 会继续。
    self.memoryCache[recipeID] = [credentials copy];
    if (!completed) {
        return YES;
    }
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写入钥匙串"}];
        }
        return NO;
    }
    return YES;
}

- (LoginCredentials *)loadCredentialsForRecipeID:(NSString *)recipeID error:(NSError **)error {
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return nil;
    }

    LoginCredentials *cached = self.memoryCache[recipeID];
    if (cached) {
        return [cached copy];
    }

    __block CFTypeRef result = NULL;
    __block OSStatus status = errSecSuccess;
    BOOL completed = LoginCredentialPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kLoginAssistKeychainService,
            (__bridge id)kSecAttrAccount: recipeID,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        };
        status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    });
    if (!completed) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"钥匙串繁忙，请稍后重试"}];
        }
        return nil;
    }
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    if (status == errSecItemNotFound) {
        self.memoryCache[recipeID] = [credentials copy];
        return credentials;
    }
    if (status != errSecSuccess || !result) {
        if (result) {
            CFRelease(result);
        }
        if (error) {
            NSString *message = [NSString stringWithFormat:@"无法读取钥匙串（代码 %d）", (int)status];
            if (status == errSecInteractionNotAllowed) {
                message = @"无法读取钥匙串（当前不可访问，请解锁 Mac 后重试）";
            }
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSData *data = CFBridgingRelease(result);
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"凭证数据损坏"}];
        }
        return nil;
    }
    id username = payload[@"username"];
    id password = payload[@"password"];
    id phone = payload[@"phone"];
    credentials.username = [username isKindOfClass:[NSString class]] ? username : @"";
    credentials.password = [password isKindOfClass:[NSString class]] ? password : @"";
    credentials.phone = [phone isKindOfClass:[NSString class]] ? phone : @"";
    self.memoryCache[recipeID] = [credentials copy];
    return credentials;
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
    [self.memoryCache removeObjectForKey:recipeID];
    __block OSStatus status = errSecSuccess;
    BOOL completed = LoginCredentialPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kLoginAssistKeychainService,
            (__bridge id)kSecAttrAccount: recipeID,
        };
        status = SecItemDelete((__bridge CFDictionaryRef)query);
    });
    if (!completed) {
        return YES;
    }
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法删除钥匙串项"}];
        }
        return NO;
    }
    return YES;
}

@end
