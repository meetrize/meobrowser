#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"

/// 端到端：hover → click 钉住气泡 → 之后 hover 其它元素不再发 hover。
@interface Diag : NSObject
@property NSInteger hoverCount;
@property NSInteger pinnedCount;
@end
@implementation Diag
@end

static void pump(NSTimeInterval s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

static NSString *evalSync(WKWebView *wv, NSString *js) {
    __block NSString *out = nil;
    __block BOOL done = NO;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        if (e) out = [NSString stringWithFormat:@"ERR:%@", e.localizedDescription];
        else out = r ? [r description] : @"(null)";
        done = YES;
    }];
    for (int i = 0; i < 100 && !done; i++) pump(0.05);
    return out ?: @"(timeout)";
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    (void)argc; (void)argv;
    [NSApplication sharedApplication];
    Diag *d = [Diag new];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [BrowserDOMInspectorBridge installOnConfiguration:config];
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        (void)payload;
        printf("  [cb] %s\n", type.UTF8String);
        if ([type isEqualToString:@"hover"]) d.hoverCount++;
        if ([type isEqualToString:@"pinned"]) d.pinnedCount++;
    };

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 960, 720)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered defer:NO];
    [window makeKeyAndOrderFront:nil];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:window.contentView.bounds configuration:config];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [window.contentView addSubview:webView];

    NSString *html =
        @"<html><body style='margin:24px;font:16px sans-serif'>"
        @"<div id='box' data-id='sku-1' style='padding:48px;background:#cde'>BOX</div>"
        @"</body></html>";
    [webView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/pin-bubble"]];
    for (int i = 0; i < 80 && webView.isLoading; i++) pump(0.05);
    pump(0.4);

    printf("1) start\n");
    printf("   started=%d\n", [bridge startInWebView:webView]);
    pump(0.4);

    printf("2) hover\n");
    evalSync(webView,
        @"(function(){var el=document.getElementById('box');var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true,"
         "clientX:r.left+8,clientY:r.top+8}));return 'ok';})()");
    pump(0.7);
    printf("   hover=%ld\n", (long)d.hoverCount);

    printf("3) click pin bubble\n");
    evalSync(webView,
        @"(function(){var el=document.getElementById('box');var r=el.getBoundingClientRect();"
         "var o={bubbles:true,composed:true,cancelable:true,button:0,clientX:r.left+8,clientY:r.top+8};"
         "el.dispatchEvent(new PointerEvent('pointerdown',o));"
         "el.dispatchEvent(new MouseEvent('mousedown',o));"
         "return el.className;})()");
    pump(0.8);
    printf("   pinned=%ld class check via js next\n", (long)d.pinnedCount);
    printf("   class=%s\n", evalSync(webView, @"document.getElementById('box').className").UTF8String);

    printf("4) hover other must not emit\n");
    NSInteger h0 = d.hoverCount;
    evalSync(webView,
        @"(function(){var el=document.createElement('div');el.id='other';"
         "el.style.cssText='padding:40px;background:#fcc;margin-top:16px';el.textContent='OTHER';"
         "document.body.appendChild(el);var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true,"
         "clientX:r.left+5,clientY:r.top+5}));"
         "window.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));"
         "return 'ok';})()");
    pump(0.8);
    NSInteger hoverAfter = d.hoverCount - h0;
    printf("   hover delta=%ld (expect 0)\n", (long)hoverAfter);

    BOOL ok = (d.hoverCount > 0 && d.pinnedCount > 0 && hoverAfter == 0);
    printf("RESULT hover=%ld pinned=%ld hoverAfterPin=%ld => %s\n",
           (long)d.hoverCount, (long)d.pinnedCount, (long)hoverAfter, ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
} }
