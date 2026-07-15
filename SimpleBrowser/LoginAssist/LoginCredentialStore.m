#import "LoginCredentialStore.h"
#import <Security/Security.h>

static NSString * const kLoginAssistKeychainService = @"MeoBrowser.LoginAssist";

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
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return NO;
    }

    NSDictionary *payload = @{
        @"username": username ?: @"",
        @"password": password ?: @"",
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

- (BOOL)loadUsername:(NSString **)username
            password:(NSString **)password
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

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLoginAssistKeychainService,
        (__bridge id)kSecAttrAccount: recipeID,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        if (username) {
            *username = @"";
        }
        if (password) {
            *password = @"";
        }
        return YES;
    }
    if (status != errSecSuccess || !result) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法读取钥匙串"}];
        }
        return NO;
    }

    NSData *data = CFBridgingRelease(result);
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginCredentialStore"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"凭证数据损坏"}];
        }
        return NO;
    }
    if (username) {
        id value = payload[@"username"];
        *username = [value isKindOfClass:[NSString class]] ? value : @"";
    }
    if (password) {
        id value = payload[@"password"];
        *password = [value isKindOfClass:[NSString class]] ? value : @"";
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
