#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 云同步 auth token：存 Application Support 文件（不访问钥匙串）。
@interface ServerSyncKeychain : NSObject

+ (BOOL)setToken:(nullable NSString *)token error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)token;
+ (BOOL)clearToken:(NSError * _Nullable * _Nullable)error;
/// 启动时后台预热内存 token。
+ (void)warmMemoryCacheInBackground;

@end

NS_ASSUME_NONNULL_END
