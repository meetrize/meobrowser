#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// Presentation 全屏：顶边触发半透明「退出全屏」按钮；指针离开按钮后延迟隐藏。
@interface BrowserPresentationFullscreenExitOverlay : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, assign) NSTimeInterval hideDelay;

@end

NS_ASSUME_NONNULL_END
