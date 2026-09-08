#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

/// 标签页出声检测与页级静音（公开 API 轮询 + 可选 WebKit SPI）。
@interface BrowserTabAudioController : NSObject

/// 任一标签 isAudible / isPageMutedByUser 变化时回调（主线程；调用方应节流刷条）。
@property (nonatomic, copy, nullable) void (^audibleStateDidChangeHandler)(void);

/// 提供当前窗口标签列表；timer 每轮拉取。
- (void)startMonitoringWithTabProvider:(NSArray<BrowserTab *> * (^)(void))tabProvider;
- (void)stopMonitoring;

/// 切换用户静音并立即应用到 WebView。
- (void)toggleMuteForTab:(BrowserTab *)tab;

/// 按 tab.isPageMutedByUser 重新应用到 WebView（唤醒休眠后调用）。
- (void)applyMuteStateForTab:(BrowserTab *)tab;

/// 主文档新导航：清除用户 mute 并解除页静音。
- (void)clearUserMuteForTabAfterNavigation:(BrowserTab *)tab;

@end

NS_ASSUME_NONNULL_END
