#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"
#import "BrowserWebViewPickCoordinator.h"

/// 验证：iframe（同源 + 跨源）里 hover 也能回传到原生 bridge。
@interface H : NSObject
@property NSInteger hoverTotal;
@property NSInteger pinnedTotal;
@property (nonatomic, copy) NSString *lastDiag;
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
    if ([type isEqualToString:@"hover"]) gH.hoverTotal++;
    if ([type isEqualToString:@"pinned"]) {
        gH.pinnedTotal++;
        printf("  ★★★ PINNED received: tag=%s\n", [body[@"payload"][@"tagName"] ?: @"-" UTF8String]);
    }
    if ([type isEqualToString:@"cancelled"]) printf("  ★★★ CANCELLED received\n");
    if ([type isEqualToString:@"dom-inspector-diag"]) {
        gH.lastDiag = [NSString stringWithFormat:@"%@", m.body];
        printf("  [diag] %s\n", gH.lastDiag.UTF8String ?: "");
    }
    NSString *tag = body[@"payload"][@"tagName"] ?: @"-";
    printf("  [msg] type=%s tag=%s src=%s\n", type.UTF8String, tag.UTF8String,
           m.webView.URL.absoluteString.UTF8String);
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    H *h = [H new];
    gH = h;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    __block H *weakH = h;
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        if ([type isEqualToString:@"hover"]) weakH.hoverTotal++;
        if ([type isEqualToString:@"pinned"]) weakH.pinnedTotal++;
        printf("  [cb]   type=%s tag=%s\n", type.UTF8String,
               [payload[@"tagName"] ?: @"-" UTF8String]);
    };

    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];

    // 主页面：iframe 同源 + 跨源
    NSString *html =
      @"<html><body style='margin:0;font:14px sans-serif'>"
      @"<h1>Main</h1>"
      @"<iframe id='sameorigin' srcdoc='<html><body><h2 id=inner>Same Origin Frame</h2></body></html>' "
      @"style='width:90%;height:120px;border:1px solid #333'></iframe>"
      @"<iframe id='crossorigin' src='https://example.com/' "
      @"style='width:90%;height:120px;border:1px solid #933'></iframe>"
      @"</body></html>";
    [wv loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];

    for (int i = 0; i < 200; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!wv.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    printf("1) bridge.startInWebView\n");
    BOOL ok = [bridge startInWebView:wv];
    printf("   started=%d\n", ok);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    printf("2) request diagnostics from all frames\n");
    [wv evaluateJavaScript:
        @"(function(){"
         " var ws=[window];"
         " try { for (var f=0; f<window.frames.length; f++) ws.push(window.frames[f]); } catch(e) {}"
         " for (var i=0; i<ws.length; i++) {"
         "   try { ws[i].__meoDomInspectorReport && ws[i].__meoDomInspectorReport('e2e'); } catch(e){}"
         " }"
         "})();"
       completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    // 主框架对 inner iframe 自身的 __meoDomInspectorStart
    [wv evaluateJavaScript:
        @"(function(){"
         " var fr=document.getElementById('sameorigin');"
         " var w=fr.contentWindow;"
         "  return JSON.stringify({stop:typeof w.__meoDomInspectorStop,"
         "    start:typeof w.__meoDomInspectorStart,"
         "    impl:!!w.__meoDomInspectorImpl});"
         "})();"
       completionHandler:^(id r, NSError *e) { printf("   iframe state: %s\n", [[r description] UTF8String]); }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    printf("3) hover main page <h1>\n");
    NSInteger b1 = h.hoverTotal;
    [wv evaluateJavaScript:@"document.querySelector('h1').dispatchEvent(new MouseEvent('mouseover', {bubbles:true, composed:true}))"
        completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("4) hover same-origin iframe #inner\n");
    NSInteger b2 = h.hoverTotal;
    NSString *hoverJS =
        @"var fr=document.getElementById('sameorigin');"
         "var inner=fr.contentDocument.querySelector('#inner');"
         "if(inner){var r=inner.getBoundingClientRect();"
         "  var ev=new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5});"
         "  inner.dispatchEvent(ev);}else{console.log('no inner');}";
    [wv evaluateJavaScript:hoverJS completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("5) pin same-origin iframe #inner (mousedown)\n");
    NSInteger bp = h.pinnedTotal;
    NSString *pinJS =
        @"(function(){"
         " var fr=document.getElementById('sameorigin');"
         " var inner=fr.contentDocument.querySelector('#inner');"
         " if(!inner){return 'no inner';}"
         " var r=inner.getBoundingClientRect();"
         " var ev=new MouseEvent('mousedown',{bubbles:true,clientX:r.left+5,clientY:r.top+5});"
         " var rs=inner.dispatchEvent(ev);"
         " return JSON.stringify({rs:rs, x:r.left, y:r.top, target:inner.tagName});"
         "})()";
    [wv evaluateJavaScript:pinJS completionHandler:^(id r, NSError *e) {
        printf("   pinJS: %s\n", [[r description] UTF8String]);
    }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("RESULT: hover=%ld pinned=%ld\n", (long)h.hoverTotal, (long)h.pinnedTotal);
    [bridge stop];
    return (h.hoverTotal >= 2 && h.pinnedTotal >= 1) ? 0 : 1;
} }