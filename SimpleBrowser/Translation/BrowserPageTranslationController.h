#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserTranslationPipeline.h"

NS_ASSUME_NONNULL_BEGIN

@class BrowserTab;

typedef NS_ENUM(NSInteger, BrowserPageTranslationUIState) {
    BrowserPageTranslationUIStateIdle = 0,
    BrowserPageTranslationUIStateTranslating,
    BrowserPageTranslationUIStateTranslated,
};

/// 地址栏网页翻译：替换 / 双语对照 / 即指即译；优先软链 Safari（仅替换）；否则页内管道。
@interface BrowserPageTranslationController : NSObject

@property (nonatomic, weak, nullable) NSWindow *hostWindow;
/// 状态变化时回调（主线程），用于刷新地址栏按钮外观。
@property (nonatomic, copy, nullable) void (^uiStateDidChangeHandler)(void);

- (BOOL)isAvailable;

/// 弹出翻译菜单（锚定在按钮下）。
- (void)showMenuFromButton:(NSButton *)button
                 forWebView:(nullable WKWebView *)webView
                        tab:(nullable BrowserTab *)tab;

/// 主文档 commit 后通知，便于 Safari 引擎做语言检测。
- (void)webViewDidCommitNavigation:(WKWebView *)webView URL:(nullable NSURL *)url;

/// 标签关闭或 WebView 销毁时清理上下文。
- (void)invalidateForWebView:(WKWebView *)webView;

/// 当前页是否处于「已翻译」态。
- (BOOL)isShowingTranslationForWebView:(nullable WKWebView *)webView;

/// 当前页是否正在翻译。
- (BOOL)isTranslatingWebView:(nullable WKWebView *)webView;

/// 综合 UI 状态（优先 translating）。
- (BrowserPageTranslationUIState)uiStateForWebView:(nullable WKWebView *)webView;

/// 当前页呈现模式（未翻译时返回 Replace）。
- (BrowserTranslationPresentationMode)presentationModeForWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
