#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// WKWebView 子类：拦截系统右键菜单中无效的「Search with…」与「Download Image」等项。
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

@end

NS_ASSUME_NONNULL_END
