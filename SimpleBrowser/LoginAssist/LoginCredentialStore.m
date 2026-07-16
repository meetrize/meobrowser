#import "LoginCredentialStore.h"
#import <Security/Security.h>

static NSString * const kLoginAssistKeychainService = @"MeoBrowser.LoginAssist";

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

    if (![NSThread isMainThread]) {
        __block BOOL ok = NO;
        __block NSError *localError = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            ok = [self saveCredentials:credentials forRecipeID:recipeID error:&localError];
        });
        if (error) {
            *error = localError;
        }
        return ok;
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

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLoginAssistKeychainService,
        (__bridge id)kSecAttrAccount: recipeID,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
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

    // 钥匙串访问必须在主线程，否则常见 errSecInteractionNotAllowed。
    if (![NSThread isMainThread]) {
        __block LoginCredentials *credentials = nil;
        __block NSError *localError = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            credentials = [self loadCredentialsForRecipeID:recipeID error:&localError];
        });
        if (error) {
            *error = localError;
        }
        return credentials;
    }

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLoginAssistKeychainService,
        (__bridge id)kSecAttrAccount: recipeID,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    if (status == errSecItemNotFound) {
        return credentials;
    }
    if (status != errSecSuccess || !result) {
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
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLoginAssistKeychainService,
        (__bridge id)kSecAttrAccount: recipeID,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
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
