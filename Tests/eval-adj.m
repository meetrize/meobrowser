#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

void evalIt(WKWebView *wv, NSString *label, NSString *js) {
    __block NSString *res;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        if (e) res = [NSString stringWithFormat:@"ERR(%ld)", (long)e.code];
        else res = @"ok";
    }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("[%s] %s\n", label.UTF8String, (res ?: @"?").UTF8String);
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    [wv loadHTMLString:@"<html><body>hi</body></html>" baseURL:nil];
    for (int i = 0; i < 50; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!wv.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // 模拟相邻字面量拼接（用 \n 转义形式）
    NSString *js1 = @"(function(){\n"
                     "  try { if (window.__x) {\n"
                     "    window.__x(); } } catch (e) {}\n"
                     "  // hello\n"
                     "  var fs = [];\n"
                     "})();";
    evalIt(wv, @"adj-concat", js1);

    // 真实相邻字面量（无 \n）
    NSString *js2 = @"(function(){"
                     "  try { if (window.__x) {"
                     "    window.__x(); } } catch (e) {}"
                     "  // hello"
                     "  var fs = [];"
                     "})();";
    evalIt(wv, @"adj-concat-real", js2);

    return 0;
}}