#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// 透明模式下：网页区右键拖拽移窗；短按右键仍弹出上下文菜单。
@interface BrowserTransparentModeWindowDragMonitor : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;

/// 本次右键手势已进入拖拽，应抑制上下文菜单。
@property (nonatomic, assign, readonly) BOOL shouldSuppressContextMenu;

- (void)install;
- (void)uninstall;

@end

NS_ASSUME_NONNULL_END
