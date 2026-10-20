#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorScript.h"

/// 端到端：通过 BrowserDOMInspectorBridge 真实 API 验证 hover / pin 回调。
@interface H : NSObject <WKScriptMessageHandler, NSApplicationDelegate>
@property NSInteger hoverCount, pinnedCount;
@property NSDictionary *lastPayload;
@property BOOL ranStop;
@property BOOL bridgeActive;
@end
@implementation H
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *body = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    NSString *type = body[@"type"] ?: @"?";
    if ([type isEqualToString:@"hover"]) { self.hoverCount++; self.lastPayload = body[@"payload"]; }
    if ([type isEqualToString:@"pinned"]) { self.pinnedCount++; self.lastPayload = body[@"payload"]; }
    printf("  [bridge msg] type=%s tag=%s\n", type.UTF8String,
           [body[@"payload"][@"tagName"] ?: @"-" UTF8String]);
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    H *h = [H new];

    // 我们直接调用 Bridge 的 installOnConfiguration + startInWebView 来模拟真实应用路径。
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    // Bridge 内部已注册 meoDomInspector handler，我们用自己的 bridge 实例接收回调。
    // 把 hub.activeBridge 链通：用我们的 bridge 实例。
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    __block H *weakH = h;
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        if ([type isEqualToString:@"hover"]) { weakH.hoverCount++; weakH.lastPayload = payload; }
        if ([type isEqualToString:@"pinned"]) { weakH.pinnedCount++; weakH.lastPayload = payload; }
        printf("  [bridge cb] type=%s tag=%s\n", type.UTF8String,
               [payload[@"tagName"] ?: @"-" UTF8String]);
    };

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];
    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif'>"
        @"<h1 id='title'>DOM Inspector E2E</h1>"
        @"<table border=1 cellpadding=6 width=600>"
        @"<tr><td>任务</td><td>状态</td></tr>"
        @"<tr id='r1'><td>报表A</td><td data-row='row[price]'>完成</td></tr>"
        @"<tr id='r2'><td>报表B</td><td>进行中</td></tr></table>"
        @"</body></html>";
    [webView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];

    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!webView.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];

    printf("1) bridge.startInWebView\n");
    BOOL ok = [bridge startInWebView:webView];
    printf("   started=%d active=%d\n", ok, bridge.active);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    // 由于 Bridge 内部会安装 BroadcastTimer, 它会每 1 秒调一次 __meoDomInspectorStart
    // 这是为什么前一次 stop:undefined 也是预期的。

    printf("2) verify state\n");
    __block NSString *state;
    [webView evaluateJavaScript:@"(function(){return JSON.stringify({impl:!!window.__meoDomInspectorImpl, stop:typeof window.__meoDomInspectorStop, start:typeof window.__meoDomInspectorStart, style:!!document.getElementById('__meo_dom_inspector_style')});})()"
          completionHandler:^(id r, NSError *e) { state = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("   %s\n", state ? state.UTF8String : "(nil)");

    // 手动启动一次，验证 start 函数本身可工作
    printf("2b) force start\n");
    __block NSString *fs;
    [webView evaluateJavaScript:@"(function(){try{window.__meoDomInspectorStart();return JSON.stringify({stop:typeof window.__meoDomInspectorStop,style:!!document.getElementById('__meo_dom_inspector_style')});}catch(e){return e.message;}})()"
          completionHandler:^(id r, NSError *e) { fs = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("   %s\n", fs ? fs.UTF8String : "(nil)");

    printf("3) mouseover r1\n");
    NSInteger b1 = h.hoverCount;
    [webView evaluateJavaScript:
        @"(function(){var el=document.querySelector('#r1 td:last-child');var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true,clientX:r.left+5,clientY:r.top+5}));})()"
          completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    printf("   hover delta = %ld\n", (long)(h.hoverCount - b1));

    printf("4) mousedown to pin\n");
    NSInteger bp = h.pinnedCount;
    [webView evaluateJavaScript:
        @"(function(){var el=document.querySelector('#r1 td:last-child');var r=el.getBoundingClientRect();"
         "var o={bubbles:true,composed:true,cancelable:true,button:0,clientX:r.left+5,clientY:r.top+5};"
         "el.dispatchEvent(new PointerEvent('pointerdown',o));"
         "el.dispatchEvent(new MouseEvent('mousedown',o));})()"
          completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    printf("   pinned delta = %ld\n", (long)(h.pinnedCount - bp));

    printf("5) bridge.stop\n");
    [bridge stop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("RESULT: hover=%ld pinned=%ld\n", (long)h.hoverCount, (long)h.pinnedCount);
    if (h.lastPayload) {
        printf("last tagName=%s id=%s\n",
               [h.lastPayload[@"tagName"] UTF8String], [h.lastPayload[@"id"] UTF8String]);
    }
    return (h.hoverCount > 0 && h.pinnedCount > 0) ? 0 : 1;
} }