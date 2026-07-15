#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 非模态轻提示，若干秒后自动淡出消失。
@interface BrowserTransientToast : NSObject

+ (void)showMessage:(NSString *)message
           inWindow:(NSWindow *)window
           duration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
