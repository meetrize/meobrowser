#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// WKWebView 子类：拦截系统「Search with…」右键项，改在应用内用默认搜索引擎打开。
@interface BrowserWebView : WKWebView

/// 在应用内打开 URL（通常为新标签）。未设置时回退为当前 WebView 加载。
@property (nonatomic, copy, nullable) void (^openURLHandler)(NSURL *url);

@end

NS_ASSUME_NONNULL_END
