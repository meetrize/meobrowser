#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// macOS WKWebView 上原生 geolocation 不可靠；桥接 navigator.geolocation。
/// DocumentStart + 主框架；Cloudflare / 人机页整段静默。非风险域桥接 geolocation 与 permissions.query。
@interface BrowserGeolocationBridge : NSObject

+ (instancetype)sharedBridge;

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

/// WebKit UIDelegate 回调入口（origin / frame 两种 SPI 共用）。
+ (void)handleWebKitPermissionRequestForHost:(NSString *)host
                                  hostWindow:(nullable NSWindow *)hostWindow
                             decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler;

@end

NS_ASSUME_NONNULL_END
