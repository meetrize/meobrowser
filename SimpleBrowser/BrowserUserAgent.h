#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 进程内缓存的 Safari 对齐 User-Agent（完整 `customUserAgent` 字符串）。
@interface BrowserUserAgent : NSObject

+ (NSString *)safariAlignedUserAgent;

@end

NS_ASSUME_NONNULL_END
