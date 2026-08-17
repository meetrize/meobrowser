#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

/// 标签级硬隔离：销毁僵死 WKWebView（≈杀掉该标签 WebContent），保留 restorableURL。
@interface BrowserTabLoadIsolator : NSObject

/// 强制丢弃 WebView。返回被丢弃的实例（可能为 nil）。不受 resistsHibernation 限制。
+ (nullable WKWebView *)forceAbandonWebViewInTab:(BrowserTab *)tab
                                     failingURL:(nullable NSURL *)failingURL;

@end

NS_ASSUME_NONNULL_END
