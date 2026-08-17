#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 非模态轻提示。默认若干秒后自动淡出；也支持常驻进度提示直至显式关闭。
@interface BrowserTransientToast : NSObject

+ (void)showMessage:(NSString *)message
           inWindow:(NSWindow *)window
           duration:(NSTimeInterval)duration;

/// 常驻提示（不自动消失）。同一窗口只保留一条。
+ (void)showPersistentMessage:(NSString *)message inWindow:(NSWindow *)window;

/// 关闭该窗口上的常驻提示。
+ (void)dismissPersistentMessageInWindow:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
