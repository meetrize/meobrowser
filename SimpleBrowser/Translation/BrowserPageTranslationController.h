#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserTab;

/// 地址栏网页翻译：菜单对齐 Safari（翻译成中文 / 首选语言 / 显示原始网页）。
/// 优先软链 SafariSharedUI；不可用时在原页面就地替换文本（不经过翻译代理域名）。
@interface BrowserPageTranslationController : NSObject

@property (nonatomic, weak, nullable) NSWindow *hostWindow;

- (BOOL)isAvailable;

/// 弹出翻译菜单（锚定在按钮下）。
- (void)showMenuFromButton:(NSButton *)button
                 forWebView:(nullable WKWebView *)webView
                        tab:(nullable BrowserTab *)tab;

/// 主文档 commit 后通知，便于 Safari 引擎做语言检测。
- (void)webViewDidCommitNavigation:(WKWebView *)webView URL:(nullable NSURL *)url;

/// 标签关闭或 WebView 销毁时清理上下文。
- (void)invalidateForWebView:(WKWebView *)webView;

/// 当前页是否处于「已翻译」态（用于菜单启用「显示原始网页」）。
- (BOOL)isShowingTranslationForWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
