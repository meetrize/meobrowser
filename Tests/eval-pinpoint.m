#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

void evalIt(WKWebView *wv, NSString *label, NSString *js) {
    __block NSString *res;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        if (e) res = [NSString stringWithFormat:@"ERR(%ld): %@", (long)e.code, e.localizedDescription];
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

    // catch 后面有无空格差异？
    evalIt(wv, @"a-no-space",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}\n  // hello\n})();");
    evalIt(wv, @"b-with-space-after-try",
        @"(function(){\n  try { if (window.__x && !window.__s) { window.__x(); } } catch (e) {}\n  // hello\n})();");
    evalIt(wv, @"c-after-try-no-cmt",
        @"(function(){\n  try { if (window.__x && !window.__s) { window.__x(); } } catch (e) {}\n  var fs = [];\n})();");
    evalIt(wv, @"d-cmt-then-var",
        @"(function(){\n  try { if (window.__x && !window.__s) { window.__x(); } } catch (e) {}\n  // hello\n})();");
    // 再回到 V2
    evalIt(wv, @"e-original-bug",
        @"(function(){"
        "  try { if (window.__x && !window.__s) {"
        "    window.__x(); } } catch (e) {}"
        "  // hello"
        "  var fs = [];"
        "})();");
    return 0;
}}