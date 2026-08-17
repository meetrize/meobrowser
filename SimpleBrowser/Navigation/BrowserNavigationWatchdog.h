#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserNavigationSession;

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserNavigationWatchdogHandler)(WKWebView *webView,
                                                 BrowserNavigationSession *session,
                                                 NSURL * _Nullable failingURL);

/// 统一调度 T0 总超时、T1 provisional、T2 commit 后文档宽限；回调前校验 generation。
@interface BrowserNavigationWatchdog : NSObject

- (void)startOverallTimeoutForWebView:(WKWebView *)webView
                              session:(BrowserNavigationSession *)session
                                  URL:(nullable NSURL *)url
                              handler:(BrowserNavigationWatchdogHandler)handler;

- (void)startProvisionalTimeoutForWebView:(WKWebView *)webView
                                  session:(BrowserNavigationSession *)session
                                      URL:(nullable NSURL *)url
                                  handler:(BrowserNavigationWatchdogHandler)handler;

/// commit 后若文档仍 isLoading，到期仅截断加载态（不换错误页）。
- (void)startDocumentLoadGraceForWebView:(WKWebView *)webView
                                 session:(BrowserNavigationSession *)session
                                     URL:(nullable NSURL *)url
                                interval:(NSTimeInterval)interval
                                 handler:(BrowserNavigationWatchdogHandler)handler;

- (void)cancelAllForWebView:(nullable WKWebView *)webView;
- (void)cancelOverallForWebView:(nullable WKWebView *)webView;
- (void)cancelProvisionalForWebView:(nullable WKWebView *)webView;
- (void)cancelDocumentLoadGraceForWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
