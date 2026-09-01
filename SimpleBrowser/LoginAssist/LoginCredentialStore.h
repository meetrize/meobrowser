#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const LoginCredentialStoreErrorDomain;
/// 历史兼容：文件存储下几乎不会出现；调用方可按原逻辑忽略或重试。
FOUNDATION_EXPORT const NSInteger LoginCredentialStoreErrorBusy;

@interface LoginCredentials : NSObject
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *phone;
@end

@interface LoginCredentialStore : NSObject

+ (instancetype)sharedStore;

- (BOOL)saveCredentials:(LoginCredentials *)credentials
            forRecipeID:(NSString *)recipeID
                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)saveUsername:(NSString *)username
            password:(NSString *)password
         forRecipeID:(NSString *)recipeID
               error:(NSError * _Nullable * _Nullable)error;

/// 同步读取（Application Support 本地文件；不访问钥匙串）。
- (nullable LoginCredentials *)loadCredentialsForRecipeID:(NSString *)recipeID
                                                    error:(NSError * _Nullable * _Nullable)error;

/// 异步读取，完成后在主队列回调。执行登录应用此 API。
- (void)loadCredentialsForRecipeID:(NSString *)recipeID
                        completion:(void (^)(LoginCredentials * _Nullable credentials, NSError * _Nullable error))completion;

- (BOOL)loadUsername:(NSString * _Nullable * _Nullable)username
            password:(NSString * _Nullable * _Nullable)password
         forRecipeID:(NSString *)recipeID
               error:(NSError * _Nullable * _Nullable)error;

- (BOOL)deleteCredentialsForRecipeID:(NSString *)recipeID
                               error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
