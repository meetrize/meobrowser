#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// Chrome 式网页全屏（F11）：macOS 原生全屏 + 隐藏全部浏览器壳。
@interface BrowserPresentationFullscreenController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, getter=isActive, readonly) BOOL active;

- (BOOL)canEnter;
- (void)toggle;
- (void)enter;
- (void)exit;

/// `windowDidEnterFullScreen` / 动画结束后布局网页。
- (void)windowDidEnterNativeFullscreen;
/// `windowDidExitFullScreen`：系统手势或 ⌃⌘F 退出时清理。
- (void)windowDidExitNativeFullscreen;

@end

NS_ASSUME_NONNULL_END
