#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 页内 Leaflet 瓦片代理：用原生 NSURLSession 拉取（走系统代理），回传 data URL，绕过 Earth CSP。
@interface MeoMapAlignTileBridge : NSObject <WKScriptMessageHandler>

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
