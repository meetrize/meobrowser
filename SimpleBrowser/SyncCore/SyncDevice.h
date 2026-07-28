#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SyncDevice : NSObject

/// 稳定本机 id，形如 mac-<uuid>，缓存在 Application Support。
+ (NSString *)deviceId;

@end

NS_ASSUME_NONNULL_END
