#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const LoginCredentialStoreErrorDomain;
/// 主线程同步读取超时（系统可能正在弹出钥匙串解锁对话框）；后台仍会完成并写入内存缓存。
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

/// 同步读取。主线程有短超时；超时返回 nil 且 error 为 `LoginCredentialStoreErrorBusy`（勿对用户弹「繁忙」警告，应改用异步 API）。
- (nullable LoginCredentials *)loadCredentialsForRecipeID:(NSString *)recipeID
                                                    error:(NSError * _Nullable * _Nullable)error;

/// 后台完整等待钥匙串（含用户解锁对话框），完成后在主队列回调。执行登录应用此 API。
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
