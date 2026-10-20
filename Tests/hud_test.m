#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"

/// 验证 HUD 是否被正确触发。
@interface H : NSObject
@property NSInteger hoverTotal;
@property NSInteger pinnedTotal;
@end
@implementation H @end
static H *gH;

@interface Hub <WKScriptMessageHandler>
@end
@implementation Hub
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *body = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    NSString *type = body[@"type"] ?: @"?";
    if ([type isEqualToString:@"hover"]) gH.hoverTotal++;
    if ([type isEqualToString:@"pinned"]) gH.pinnedTotal++;
    printf("  [msg] type=%s tag=%s geo=%s\n",
           type.UTF8String,
           [body[@"payload"][@"tagName"] ?: @"-" UTF8String],
           [[[NSString stringWithFormat:@"%@", body[@"payload"][@"geometry"] ?: @{}] substringToIndex:MIN(60, [[NSString stringWithFormat:@"%@", body[@"payload"][@"geometry"] ?: @{}] length])] UTF8String]);
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    H *h = [H new];
    gH = h;

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        if ([type isEqualToString:@"hover"]) h.hoverTotal++;
        if ([type isEqualToString:@"pinned"]) h.pinnedTotal++;
        printf("  [bridge cb] type=%s tag=%s\n", type.UTF8String,
               [payload[@"tagName"] ?: @"-" UTF8String]);

        // 模拟 HUD 的几何计算
        NSDictionary *geo = payload[@"geometry"];
        if (geo) {
            CGFloat x = [geo[@"x"] doubleValue];
            CGFloat y = [geo[@"y"] doubleValue];
            CGFloat w = [geo[@"width"] doubleValue];
            CGFloat h2 = [geo[@"height"] doubleValue];
            printf("  [HUD geo] x=%.0f y=%.0f w=%.0f h=%.0f\n", x, y, w, h2);
        }

        // 模拟 HUD showSnapshot 调用
        // HUD 需要：geometryInContent（window.contentView 坐标）+ webViewInContent
        // 我们的测试 WebView 就在 contentView 左下角，frame = (0,0,800,600)
        // geometryInContent = NSMakeRect(x, contentH - y - h, w, h)
        // 这里 contentH 未知，我们用屏幕坐标系模拟
        printf("  [HUD simulate] geometryInContent = (x=%.0f, y=inverted, w=%.0f, h=%.0f)\n",
               [geo[@"x"] doubleValue], [geo[@"width"] doubleValue], [geo[@"height"] doubleValue]);
    };

    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];

    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif'>"
        @"<h1 id='title'>HUD Test</h1>"
        @"<p id='para1'>Hello world this is a paragraph</p>"
        @"<div id='box' style='width:200px;height:100px;background:#f00'>Red Box</div>"
        @"</body></html>";
    [wv loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!wv.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Start probe ==\n");
    [bridge startInWebView:wv];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Hover h1 ==\n");
    [wv evaluateJavaScript:
        @"var el=document.getElementById('title');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Hover p ==\n");
    [wv evaluateJavaScript:
        @"var el=document.getElementById('para1');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Hover div#box ==\n");
    [wv evaluateJavaScript:
        @"var el=document.getElementById('box');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Pin div#box ==\n");
    [wv evaluateJavaScript:
        @"var el=document.getElementById('box');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("RESULT: hover=%ld pinned=%ld\n", (long)h.hoverTotal, (long)h.pinnedTotal);
    [bridge stop];
    return (h.hoverTotal >= 3 && h.pinnedTotal >= 1) ? 0 : 1;
} }
