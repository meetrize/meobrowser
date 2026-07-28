#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ServerSyncKeychain : NSObject

+ (BOOL)setToken:(nullable NSString *)token error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)token;
+ (BOOL)clearToken:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
