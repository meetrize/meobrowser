#import "ServerSyncAuth.h"
#import "ServerSyncAPIClient.h"
#import "ServerSyncSettings.h"
#import "ServerSyncKeychain.h"

@implementation ServerSyncAuth

+ (instancetype)sharedAuth {
    static ServerSyncAuth *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (BOOL)isLoggedIn {
    // 无 userId 时不必碰钥匙串（避免冷启动仅为判登录就弹密码框）。
    if (ServerSyncSettings.sharedSettings.userId.length == 0) {
        return NO;
    }
    return [ServerSyncKeychain token].length > 0;
}

- (void)registerWithEmail:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(NSError *))completion {
    NSString *trimmedEmail = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *pass = password ?: @"";
    if (trimmedEmail.length == 0) {
        completion([NSError errorWithDomain:@"ServerSyncAuth"
                                       code:10
                                   userInfo:@{NSLocalizedDescriptionKey: @"请填写邮箱"}]);
        return;
    }
    if (pass.length < 8) {
        completion([NSError errorWithDomain:@"ServerSyncAuth"
                                       code:11
                                   userInfo:@{NSLocalizedDescriptionKey: @"密码至少 8 位（服务器要求）"}]);
        return;
    }
    NSDictionary *body = @{
        @"email": trimmedEmail,
        @"password": pass,
        @"passwordConfirm": pass,
    };
    [[ServerSyncAPIClient sharedClient] postJSON:@"/api/collections/users/records"
                                            body:body
                                           token:nil
                                      completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        (void)json;
        [self loginWithEmail:trimmedEmail password:pass completion:completion];
    }];
}

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^)(NSError *))completion {
    NSString *trimmedEmail = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSDictionary *body = @{
        @"identity": trimmedEmail,
        @"password": password ?: @"",
    };
    [[ServerSyncAPIClient sharedClient] postJSON:@"/api/collections/users/auth-with-password"
                                            body:body
                                           token:nil
                                      completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        NSString *token = json[@"token"];
        NSDictionary *record = json[@"record"];
        NSString *userId = [record isKindOfClass:[NSDictionary class]] ? record[@"id"] : nil;
        if (![token isKindOfClass:[NSString class]] || token.length == 0 ||
            ![userId isKindOfClass:[NSString class]] || userId.length == 0) {
            completion([NSError errorWithDomain:@"ServerSyncAuth"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey: @"登录响应无效"}]);
            return;
        }
        NSError *kcError = nil;
        if (![ServerSyncKeychain setToken:token error:&kcError]) {
            completion(kcError);
            return;
        }
        ServerSyncSettings.sharedSettings.email = email;
        ServerSyncSettings.sharedSettings.userId = userId;
        completion(nil);
    }];
}

- (void)logout {
    [ServerSyncKeychain clearToken:nil];
    ServerSyncSettings.sharedSettings.userId = nil;
}

@end
