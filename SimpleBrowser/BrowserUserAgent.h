#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 进程内缓存的 Safari 对齐 User-Agent（完整 `customUserAgent` 字符串）。
@interface BrowserUserAgent : NSObject

/// 后台仅写入静态 fallback；真正采样须在主线程（见 sampleOnMainQueueIfNeeded）。
+ (void)warmUpInBackground;

/// 已缓存则返回采样结果；否则立刻返回静态 fallback，并触发后台预热。
+ (NSString *)safariAlignedUserAgent;

/// 在主线程异步采样并升级缓存；applicationDidFinishLaunching 后调用。
+ (void)scheduleMainQueueSampleIfNeeded;

@end

NS_ASSUME_NONNULL_END
