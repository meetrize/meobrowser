#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    [wv loadHTMLString:@"<html><body>hi</body></html>" baseURL:nil];
    for (int i = 0; i < 50; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!wv.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    NSString *js = @"(function(){"
                    "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) {"
                    "    window.__meoDomInspectorStart(); } } catch (e) {}"
                    "  // 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。"
                    "  var fs = [];"
                    "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }"
                    "  for (var i = 0; i < fs.length; i++) {"
                    "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1}, '*'); } catch (x) {}"
                    "  }"
                    "})();";
    __block NSString *err;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) { err = [NSString stringWithFormat:@"%@", e]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("eval err: %s\n", err ? err.UTF8String : "(none)");

    // 再读 JS 长度
    printf("js.length=%lu\n", (unsigned long)js.length);
    return 0;
}}