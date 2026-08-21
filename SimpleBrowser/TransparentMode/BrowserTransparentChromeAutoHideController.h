#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// 透明模式：鼠标移出窗 frame 后延迟通知「壳应收起」；移入立即通知「壳应展开」。
@interface BrowserTransparentChromeAutoHideController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
/// 考虑移出延迟后的结果：YES=应显示标签条（及非精简地址栏）。
@property (nonatomic, assign, readonly) BOOL chromeRevealed;
@property (nonatomic, assign) NSTimeInterval hideDelay;

/// 指针边沿或延迟结束后回调（主线程）。
@property (nonatomic, copy, nullable) void (^chromeRevealDidChangeHandler)(void);

- (void)reevaluatePointerNow;
- (void)forceDisableAndReveal;

@end

NS_ASSUME_NONNULL_END
