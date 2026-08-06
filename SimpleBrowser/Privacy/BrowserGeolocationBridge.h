#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// macOS WKWebView 上原生 geolocation 不可靠；在 document-start 桥接 navigator.geolocation 与 Permissions API。
@interface BrowserGeolocationBridge : NSObject

+ (instancetype)sharedBridge;

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

/// WebKit UIDelegate 回调入口（origin / frame 两种 SPI 共用）。
+ (void)handleWebKitPermissionRequestForHost:(NSString *)host
                                  hostWindow:(nullable NSWindow *)hostWindow
                             decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler;

@end

NS_ASSUME_NONNULL_END
