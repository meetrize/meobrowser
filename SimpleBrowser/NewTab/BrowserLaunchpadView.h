#import <Cocoa/Cocoa.h>

@class BrowserLaunchpadView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserLaunchpadViewDelegate <NSObject>
- (void)launchpadView:(BrowserLaunchpadView *)view openURL:(NSURL *)url;
- (void)launchpadView:(BrowserLaunchpadView *)view openURLInNewTab:(NSURL *)url;

@optional
/// 用户按下快捷方式时提前预热 WebView，缩短 mouseUp→导航 的等待。
- (void)launchpadView:(BrowserLaunchpadView *)view prepareToOpenURL:(NSURL *)url;
@end

@interface BrowserLaunchpadView : NSView

@property (nonatomic, weak, nullable) id<BrowserLaunchpadViewDelegate> delegate;

- (void)reloadShortcuts;

/// 窗口创建后后台预建网格（hidden 时调用），避免首次打开新标签页才 reloadData。
- (void)preloadShortcutsIfNeeded;

/// 切到新标签页时轻量刷新：已预载则只补拉图标，不 reloadData。
- (void)refreshShortcutsWhenShown;

@end

NS_ASSUME_NONNULL_END
