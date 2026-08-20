#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

/// 透明模式：窗口/WebView 外观快照与应用（壳显隐由 WindowController 编排）。
@interface BrowserTransparentModeController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, readonly) BOOL hasSnapshot;

/// 在 WKWebViewConfiguration 上安装 document-start 脚本（Canvas 文字钩子尽早生效）。
+ (void)installPageStyleUserScriptOnConfiguration:(WKWebViewConfiguration *)configuration;

- (void)captureSnapshotFromWindow:(NSWindow *)window
                contentContainer:(NSView *)contentContainer;

- (void)applyWindowTransparency:(NSWindow *)window
              contentContainer:(NSView *)contentContainer
                      webViews:(NSArray<WKWebView *> *)webViews;

- (void)restoreWindowAppearance:(NSWindow *)window
              contentContainer:(NSView *)contentContainer
                      webViews:(NSArray<WKWebView *> *)webViews;

- (void)clearSnapshot;

/// 向页面注入透明模式样式（统一文字色；媒体保持可见）。
- (void)applyTransparentPageStyleToWebView:(nullable WKWebView *)webView;

/// 移除透明模式页面样式。
- (void)removeTransparentPageStyleFromWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
