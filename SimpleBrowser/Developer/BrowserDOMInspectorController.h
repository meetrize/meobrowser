#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserDOMInspectorStateDidChangeNotification;

/// DOM 探针的窗口级控制器：跟随当前标签的 WebView，负责开启/关闭与 HUD 呈现。
@interface BrowserDOMInspectorController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, readonly, getter=isActive) BOOL active;
/// 气泡是否已钉住（常显、不再跟随悬停）。
@property (nonatomic, readonly, getter=isBubblePinned) BOOL bubblePinned;
/// 兼容旧名：等同于 bubblePinned（已无右侧面板）。
@property (nonatomic, readonly, getter=isPanelVisible) BOOL panelVisible;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

/// 在 WebView 配置阶段注册脚本通道。
- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;

/// 切换开启/关闭。
- (IBAction)toggle:(nullable id)sender;
- (void)start;
- (void)stop;

/// 标签切换后调用；若处于开启态则迁移到新的 WebView。
- (void)attachToCurrentWebView:(nullable WKWebView *)webView;

/// 窗口侧在 tabControllerDidChange 时调用：选中标签变化则立刻隐藏气泡。
- (void)noteSelectedTabDidChange;

/// 页面导航完成后调用；处于开启态时重新注入脚本（新文档会清掉旧监听器）。
- (void)noteNavigationFinishedInWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
