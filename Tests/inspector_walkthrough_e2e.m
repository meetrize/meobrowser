#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorController.h"
#import "BrowserDOMInspectorBridge.h"

/// 模拟用户点击 DOM 探针工具栏按钮 → 真实注入 + 悬停 + 钉住 + 截图，再切下一标签。
@interface H : NSObject
@property NSInteger hoverTotal;
@property NSInteger pinnedTotal;
@end
@implementation H
@end

static H *gH;
@interface Hub <WKScriptMessageHandler>
@end
@implementation Hub
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *body = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    NSString *type = body[@"type"] ?: @"?";
    if ([type isEqualToString:@"hover"]) {
        gH.hoverTotal++;
        printf("    [hover] tag=%s id=%s\n",
               [body[@"payload"][@"tagName"] ?: @"-" UTF8String],
               [body[@"payload"][@"id"] ?: @"-" UTF8String]);
    }
    if ([type isEqualToString:@"pinned"]) {
        gH.pinnedTotal++;
        printf("    [pinned] tag=%s id=%s sel=%s\n",
               [body[@"payload"][@"tagName"] ?: @"-" UTF8String],
               [body[@"payload"][@"id"] ?: @"-" UTF8String],
               [body[@"payload"][@"selector"] ?: @"-" UTF8String]);
    }
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    H *h = [H new];
    gH = h;

    // 1) 真实创建一个浏览器 webView
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    // 用 Bridge 的 installOnConfiguration 安装脚本通道
    [BrowserDOMInspectorBridge installOnConfiguration:config];
    printf("   registered bridge on config\n");

    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];

    NSString *html =
      @"<html><body style='margin:0;font:14px sans-serif'>"
      @"<h1 id='title'>E2E Walkthrough</h1>"
      @"<table border=1 cellpadding=6 width=600>"
      @"<tr><th colspan=2>任务表</th></tr>"
      @"<tr><td>报表A</td><td data-row='row[price]'>完成</td></tr>"
      @"<tr id='r2'><td>报表B</td><td>进行中</td></tr></table>"
      @"<iframe id='f1' srcdoc='<html><body><h2 id=inner>Same-Origin</h2></body></html>'"
      @" style='width:90%;height:80px;border:1px solid #888'></iframe>"
      @"</body></html>";
    [wv loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!wv.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // 2) 模拟用户点击工具栏探针按钮：直接调 Bridge API
    printf("== Step 1: 模拟点击工具栏探针按钮 ==\n");
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        printf("    [bridge cb] type=%s tag=%s\n",
               type.UTF8String, [payload[@"tagName"] ?: @"-" UTF8String]);
        if ([type isEqualToString:@"hover"]) {
            h.hoverTotal++;
            printf("    [hover] tag=%s id=%s selector=%s\n",
                   [payload[@"tagName"] ?: @"-" UTF8String],
                   [payload[@"id"] ?: @"-" UTF8String],
                   [payload[@"selector"] ?: @"-" UTF8String]);
        }
        if ([type isEqualToString:@"pinned"]) {
            h.pinnedTotal++;
            printf("    [pinned] tag=%s id=%s selector=%s\n",
                   [payload[@"tagName"] ?: @"-" UTF8String],
                   [payload[@"id"] ?: @"-" UTF8String],
                   [payload[@"selector"] ?: @"-" UTF8String]);
        }
    };
    BOOL started = [bridge startInWebView:wv];
    printf("   bridge.startInWebView: %d\n", started);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // 3) 模拟鼠标移动：分别在主页面 / 同源 iframe 上 hover
    printf("== Step 2: 鼠标悬停 r2 数据行 ==\n");
    [wv evaluateJavaScript:
        @"var el=document.querySelector('#r2 td:last-child');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Step 3: 鼠标悬停同源 iframe inner h2 ==\n");
    [wv evaluateJavaScript:
        @"var inner=document.getElementById('f1').contentDocument.querySelector('#inner');"
         "var r=inner.getBoundingClientRect();"
         "inner.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // 4) 模拟点击钉住
    printf("== Step 4: 点击钉住主页面 r1 ==\n");
    [wv evaluateJavaScript:
        @"var el=document.querySelector('table tr:nth-of-type(2) td:last-child');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Step 5: 点击钉住 iframe inner ==\n");
    [wv evaluateJavaScript:
        @"var inner=document.getElementById('f1').contentDocument.querySelector('#inner');"
         "var r=inner.getBoundingClientRect();"
         "inner.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // 5) 关闭探针
    printf("== Step 6: 关闭探针 ==\n");
    [bridge stop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    printf("\n=== RESULT ===\n");
    printf("hover=%ld (期望 ≥ 2)\n", (long)h.hoverTotal);
    printf("pinned=%ld (期望 ≥ 2)\n", (long)h.pinnedTotal);
    bool ok = (h.hoverTotal >= 2 && h.pinnedTotal >= 2);
    printf("STATUS: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
} }