#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 网页 → macOS 系统通知桥：`meoPageNotify` + `window.MeoBrowser.notify`。
@interface BrowserPageNotificationBridge : NSObject

+ (instancetype)sharedBridge;

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
