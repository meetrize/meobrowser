#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// 摸鱼模式：鼠标移出窗 frame 时仅将窗口 alpha 置 0；移入还原。不改 ignoresMouseEvents。
@interface BrowserAfkModeController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign, readonly, getter=isConcealed) BOOL concealed;

/// 关闭摸鱼并确保窗口可见（全屏进入等强制路径）。
- (void)forceDisableAndReveal;

@end

NS_ASSUME_NONNULL_END
