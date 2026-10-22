#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 标准 Web Notification API 桥：`Notification.requestPermission` / `new Notification(...)`
/// → 站点权限对话框 → macOS 通知中心。
@interface BrowserWebNotificationBridge : NSObject

+ (instancetype)sharedBridge;

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
