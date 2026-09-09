#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 用户是否仍在操作本应用（键鼠/滚轮/触控板）。
/// 活跃期内不做预算休眠；空闲超过阈值后再回收后台 WebView。
@interface BrowserUserActivityMonitor : NSObject

+ (instancetype)sharedMonitor;

/// 记录一次用户输入（由 MeoApplication.sendEvent 调用）。
- (void)noteUserInput;

/// 距上次输入的秒数。
@property (nonatomic, readonly) NSTimeInterval secondsSinceLastInput;

/// 仍在「活跃期」：近期有输入，且应用处于 active（前台）。
@property (nonatomic, readonly, getter=isUserActivelyBrowsing) BOOL userActivelyBrowsing;

/// 已进入可回收空闲：超过阈值无输入，或应用退到后台超过较短阈值。
@property (nonatomic, readonly, getter=isIdleForReclaim) BOOL idleForReclaim;

/// 活跃期时长（默认 90s）。defaults：MeoBrowserUserActiveSeconds
@property (nonatomic, readonly) NSTimeInterval activeWindowSeconds;

/// 退到后台后多久视为可回收（默认 30s）。defaults：MeoBrowserBackgroundIdleSeconds
@property (nonatomic, readonly) NSTimeInterval backgroundIdleSeconds;

@end

NS_ASSUME_NONNULL_END
