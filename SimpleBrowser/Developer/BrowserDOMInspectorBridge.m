#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorScript.h"
#import "LoginAssistScriptMessageProxy.h"
#import "BrowserWebViewPickCoordinator.h"

static NSString * const kDOMInspectorHandlerName = @"meoDomInspector";

@interface BrowserDOMInspectorMessageHub : NSObject <WKScriptMessageHandler>
+ (instancetype)sharedHub;
@property (nonatomic, weak, nullable) BrowserDOMInspectorBridge *activeBridge;
@end

@interface BrowserDOMInspectorBridge ()
@property (nonatomic, weak, nullable) WKWebView *webView;
@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, strong, nullable) NSTimer *broadcastTimer;
@end

/// document-start 引导脚本，下发到每个框架（含跨源 iframe）。
///
/// 关键约束：跨源 iframe 既无法被父页面 eval，也无法被原生侧直接赋值源码
/// （跨源窗口属性赋值会抛 SecurityError）。因此脚本必须由每个框架自己执行。
/// 做法是把完整探针源码作为 WKUserScript 下发，再用开关标志控制启停。
/// 本引导脚本负责在「探针已开启」状态下自动启动本框架的探针，
/// 这样后加载的 iframe 无需等待原生侧广播也能工作。


@implementation BrowserDOMInspectorMessageHub

+ (instancetype)sharedHub {
    static BrowserDOMInspectorMessageHub *hub;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ hub = [[BrowserDOMInspectorMessageHub alloc] init]; });
    return hub;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:kDOMInspectorHandlerName]) return;
    [self.activeBridge handleScriptMessageBody:message.body];
}

@end

@implementation BrowserDOMInspectorBridge

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) return;
    NSLog(@"[DOMInspector] installOnConfiguration: called, bootstrapLen=%lu",
          (unsigned long)[BrowserDOMInspectorScript bootstrapScript].length);
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    [ucc removeScriptMessageHandlerForName:kDOMInspectorHandlerName];
    [ucc addScriptMessageHandler:[BrowserDOMInspectorMessageHub sharedHub]
                           name:kDOMInspectorHandlerName];
    WKUserScript *bootstrap =
        [[WKUserScript alloc] initWithSource:[BrowserDOMInspectorScript bootstrapScript]
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            // 必须覆盖所有框架：业务表格常在 iframe 内，
                            // 若仅注入主框架，iframe 中的元素完全探测不到。
                            forMainFrameOnly:NO];
    [ucc addUserScript:bootstrap];

    // 完整探针实现同样下发到每个框架。
    // 跨源 iframe 既无法被父页面 eval，也无法被原生侧直接赋值源码
    // （跨源窗口属性赋值抛 SecurityError），只有 WKUserScript 这条路能到达它。
    WKUserScript *impl =
        [[WKUserScript alloc] initWithSource:[BrowserDOMInspectorScript startScript]
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [ucc addUserScript:impl];
}

#pragma mark - Lifecycle

- (BOOL)startInWebView:(WKWebView *)webView {
    if (!webView) return NO;
    [self stop];
    if (![[BrowserWebViewPickCoordinator shared] beginPickInWebView:webView owner:self]) {
        return NO;
    }
    self.webView = webView;
    self.active = YES;
    [BrowserDOMInspectorMessageHub sharedHub].activeBridge = self;
    NSLog(@"[DOMInspector] startInWebView: %@", webView);
    [self injectIntoWebView:webView];
    [self startBroadcastTimer];
    return YES;
}

/// 广播启停到主框架及其所有已加载的子框架。
/// 探针实现已由 WKUserScript 下发到每个框架，这里只需触发开关。
/// 跨源 iframe 触达不到，因此改用 window.postMessage 广播：
/// postMessage 不受同源策略限制，任意框架都能收到。
- (void)injectIntoWebView:(WKWebView *)webView {
    if (!webView) return;
    [self broadcastEnable];
}

- (void)broadcastEnable {
    WKWebView *webView = self.webView;
    if (!webView) return;
    // 字符串拼成单行 JS：所有换行都用 `\n` 转义，否则 Objective-C 的相邻字符串字面量
    // 在拼接时不会自动插入换行，`//` 注释会延到下一行字面量，覆盖后面的 `})();` 导致语法错。
    NSString *js =
        @"(function(){\n"
         "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) {\n"
         "    window.__meoDomInspectorStart(); } } catch (e) {}\n"
         "  // 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。\n"
         "  var fs = [];\n"
         "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }\n"
         "  for (var i = 0; i < fs.length; i++) {\n"
         "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1}, '*'); } catch (x) {}\n"
         "  }\n"
         "})();";
    [webView evaluateJavaScript:js
                completionHandler:^(id result, NSError *error) {
        __unused id r = result;
        if (error) {
            NSLog(@"[DOMInspector] broadcastEnable evaluate error: %@", error);
        }
    }];
}

/// 周期性广播。跨源 iframe 的 load 事件父页面收不到，
/// 只能靠反复广播覆盖到那些后加载的框架。
- (void)startBroadcastTimer {
    [self stopBroadcastTimer];
    __weak typeof(self) weakSelf = self;
    self.broadcastTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __unused NSTimer *t = timer;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.active) return;
        [strongSelf broadcastEnable];
    }];
}

- (void)stopBroadcastTimer {
    [self.broadcastTimer invalidate];
    self.broadcastTimer = nil;
}

- (NSString *)jsonEscape:(NSString *)text {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[text ?: @""]
                                                   options:0 error:NULL];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return array.length >= 2 ? [array substringWithRange:NSMakeRange(1, array.length - 2)] : @"\"\"";
}

- (void)reinjectIntoWebView:(WKWebView *)webView {
    [self injectIntoWebView:webView];
}

- (void)unpinBubble {
    WKWebView *webView = self.webView;
    if (!webView || !self.active) return;
    NSString *js =
        @"(function(){\n"
         "  try { if (window.__meoDomInspectorUnpin) { window.__meoDomInspectorUnpin(); } } catch (e) {}\n"
         "  var fs = [];\n"
         "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }\n"
         "  for (var i = 0; i < fs.length; i++) {\n"
         "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector',unpin:1}, '*'); } catch (x) {}\n"
         "  }\n"
         "})();";
    [webView evaluateJavaScript:js completionHandler:nil];
}

- (void)pinLastHovered {
    WKWebView *webView = self.webView;
    if (!webView || !self.active) return;
    NSString *js =
        @"(function(){\n"
         "  try { if (window.__meoDomInspectorPinLast) { window.__meoDomInspectorPinLast(); } } catch (e) {}\n"
         "  var fs = [];\n"
         "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }\n"
         "  for (var i = 0; i < fs.length; i++) {\n"
         "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector',pinLast:1}, '*'); } catch (x) {}\n"
         "  }\n"
         "})();";
    [webView evaluateJavaScript:js completionHandler:nil];
}

- (void)stop {
    if (!self.active) return;
    self.active = NO;
    [self stopBroadcastTimer];
    [BrowserDOMInspectorMessageHub sharedHub].activeBridge = nil;
    [[BrowserWebViewPickCoordinator shared] endPickForOwner:self];
    WKWebView *webView = self.webView;
    self.webView = nil;
    if (webView) {
        NSString *stopDriver =
            @"(function(){"
             "  function walk(w, d) {"
             "    if (d > 6) { return; }"
             "    try { if (window.__meoDomInspectorStop) { window.__meoDomInspectorStop(); } } catch (e) {}"
             "    var fs = [];"
             "    try { fs = w.document.querySelectorAll('iframe,frame'); } catch (e) { return; }"
             "    for (var i = 0; i < fs.length; i++) {"
             "      try { var cw = fs[i].contentWindow; if (cw) { cw.document; walk(cw, d + 1); } } catch (x) {}"
             "    }"
             "  }"
             "  walk(window, 0);"
             "})()";
        [webView evaluateJavaScript:stopDriver completionHandler:nil];
        // 跨源框架用 postMessage 关闭
        [webView evaluateJavaScript:
            @"(function(){"
             "  var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}"
             "  for(var i=0;i<fs.length;i++){"
             "    try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':0},'*');}catch(x){}"
             "  }"
             "})();" completionHandler:nil];
    }
}

#pragma mark - Script Message

- (void)handleScriptMessageBody:(id)body {
    if (!self.active) return;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *dict = (NSDictionary *)body;
    NSString *type = [dict[@"type"] isKindOfClass:[NSString class]] ? dict[@"type"] : @"";
    if ([type isEqualToString:@"cancelled"]) {
        if (self.onCancelled) self.onCancelled();
        return;
    }
    NSDictionary *payload = [dict[@"payload"] isKindOfClass:[NSDictionary class]] ? dict[@"payload"] : nil;
    if ([type isEqualToString:@"hover"] || [type isEqualToString:@"pinned"]) {
        if (!payload) {
            NSLog(@"[DOMInspector] %@ message missing payload", type);
            return;
        }
        if (self.onSnapshot) self.onSnapshot(type, payload);
        return;
    }
    if (payload && self.onSnapshot) self.onSnapshot(type, payload);
    if ([type isEqualToString:@"dom-inspector-diag"]) {
        NSLog(@"[DOMInspector][diag] %@", dict[@"tag"] ?: @"");
    }
}

@end
