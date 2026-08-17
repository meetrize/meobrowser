#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ServerSyncKeychain : NSObject

+ (BOOL)setToken:(nullable NSString *)token error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)token;
+ (BOOL)clearToken:(NSError * _Nullable * _Nullable)error;
/// 启动时后台预热内存 token，避免主线程首次读钥匙串。
+ (void)warmMemoryCacheInBackground;

@end

NS_ASSUME_NONNULL_END
