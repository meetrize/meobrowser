#import <WebKit/WebKit.h>
#import "BrowserNavigationTimeouts.h"

NS_ASSUME_NONNULL_BEGIN

/// WKWebView 子类：拦截系统右键菜单中无效的「Search with…」与「Download Image」等项；
/// 选中文本含 http(s):// 时补充「在新标签中打开」。
@interface BrowserWebView : WKWebView

/// 在应用内打开 URL（通常为新标签）。未设置时回退为当前 WebView 加载。
@property (nonatomic, copy, nullable) void (^openURLHandler)(NSURL *url);

/// 在新浏览器窗口打开 URL。
@property (nonatomic, copy, nullable) void (^openURLInNewWindowHandler)(NSURL *url);

/// 下载 URL（写入 Downloads）。由窗口控制器接到 BrowserDownloadManager。
@property (nonatomic, copy, nullable) void (^downloadURLHandler)(NSURL *url);

/// 右键「下载图片/媒体」进行中：下一次 createWebView 应改为下载而非开标签。
@property (nonatomic, assign, readonly) BOOL pendingContextMenuDownload;

/// 右键「在新窗口打开链接」进行中：下一次 createWebView 应开新窗口。
@property (nonatomic, assign, readonly) BOOL pendingContextMenuOpenInNewWindow;

/// 若正在处理右键下载，取出 URL 并清除标记；否则返回 nil。
- (nullable NSURL *)consumePendingContextMenuDownloadURL:(NSURL *)candidateURL;

/// 若正在处理右键「新窗口打开」，取出 URL 并清除标记；否则返回 nil。
- (nullable NSURL *)consumePendingContextMenuOpenInNewWindowURL:(NSURL *)candidateURL;

/// 系统 HTTP 代理下，WKWebView 可能把 URL fragment 以 %23 打进请求路径导致 404。
/// 对 http: 主文档导航应剥离 fragment，经查询参数在 document-start 写回 hash。
+ (void)installFragmentRestoreScriptOnContentController:(WKUserContentController *)controller;
+ (void)cleanupHashRestoreQueryInWebView:(WKWebView *)webView;
+ (void)cleanupHashRestoreQueryInWebView:(WKWebView *)webView
                              completion:(void (^ _Nullable)(NSString * _Nullable href))completion;
/// 同文档改 hash：replaceState + hashchange + 滚到锚点，避免 http+# 经代理发网。
/// completion 返回页面最终 location.href（含 #），供地址栏同步；失败时传 nil。
+ (void)applySameDocumentFragment:(nullable NSString *)fragment
                        inWebView:(WKWebView *)webView
                       completion:(void (^ _Nullable)(NSString * _Nullable href))completion;
+ (void)applySameDocumentFragment:(nullable NSString *)fragment inWebView:(WKWebView *)webView;
+ (BOOL)shouldStripFragmentForNetworkLoadOfURL:(nullable NSURL *)url;
+ (BOOL)URL:(nullable NSURL *)url isSameDocumentAsURL:(nullable NSURL *)otherURL;
/// 将 path 内误编码的 %23 还原为 fragment；若无需处理则返回原 URL。
+ (NSURL *)URLByNormalizingEmbeddedFragment:(NSURL *)url;
/// 生成可供网络加载的 URL（去掉 fragment，必要时带上恢复用查询参数）。
+ (nullable NSURL *)networkLoadURLByStrippingFragment:(NSURL *)url;
/// 地址栏 / 会话用：去掉内部 `__meo_hf`，还原为用户可见的 #hash URL。
+ (nullable NSURL *)publicURLFromInternalURL:(nullable NSURL *)url;
/// 是否为带 `__meo_hf` 的 hash 恢复导航（T2 应用短宽限）。
+ (BOOL)URLContainsHashRestoreQuery:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
