#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// DOM 探针页面侧桥接：注入悬停/点击捕获脚本，回传元素快照。
/// 关闭时调用 `__meoDomInspectorStop()` 彻底移除监听、高亮与注入样式。
@interface BrowserDOMInspectorBridge : NSObject

/// 在配置阶段注册消息处理器与 document-start 引导脚本（每次新建 WebView 都需调用）。
+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

/// 开启探针。返回 NO 表示被其它拾取器占用或 WebView 不可用。
- (BOOL)startInWebView:(nullable WKWebView *)webView;
- (void)stop;

/// 快照回调。type 为 `hover` 或 `pinned`。
@property (nonatomic, copy, nullable) void (^onSnapshot)(NSString *type, NSDictionary *payload);
/// 探针在页面内被 Esc 取消。
@property (nonatomic, copy, nullable) void (^onCancelled)(void);

@property (nonatomic, readonly, getter=isActive) BOOL active;

/// 供消息中枢转发。
- (void)handleScriptMessageBody:(id)body;

/// 向 webView 及其所有子框架重新注入探针脚本（幂等）。
- (void)reinjectIntoWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
