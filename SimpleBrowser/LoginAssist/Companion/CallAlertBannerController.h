#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const CallAlertDidUpdateNotification;

/// 跨窗口来电横幅控制器（单例状态，各窗口 contentContainer 顶部安装条）。
@interface CallAlertBannerController : NSObject

+ (instancetype)sharedController;

/// 在窗口内容区顶部安装横幅宿主（可重复调用，幂等）。
- (void)installInContentContainer:(NSView *)container forWindowController:(id)windowController;

- (void)updateFromPayload:(NSDictionary *)payload
              displayName:(nullable NSString *)displayName
                typeLabel:(nullable NSString *)typeLabel;

- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
