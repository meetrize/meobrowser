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

    // 与 eval-bisect 相同字面
    evalIt(wv, @"V1-spaces-around",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// hello\n})();");
    // 与 eval-progressive 相同字面
    evalIt(wv, @"V2-spaces-and-newline",
        @"(function(){"
        "  try { if (window.__x && !window.__s) {"
        "    window.__x(); } } catch (e) {}"
        "  // hello"
        "  var fs = [];"
        "})();");
    // 第一个测试 A 没注释，OK
    // B 有注释，ERR
    // 差异：B 在 catch 后面有 `} ` 然后换行 `// hello` 然后再换行 `var fs = []`
    // eval-bisect 区别：先 `try{if(...){...}}catch(e){}` 单行
    // 让我精确对比
    evalIt(wv, @"V3-multi-line-try",
        @"(function(){"
        "  try { if (window.__x) {"
        "    window.__x(); } } catch (e) {}"
        "  // hello"
        "  var fs = [];"
        "})();");
    evalIt(wv, @"V4-no-try-comment",
        @"(function(){"
        "  if (window.__x) { window.__x(); }"
        "  // hello"
        "  var fs = [];"
        "})();");
    evalIt(wv, @"V5-try-oneliner-comment",
        @"(function(){"
        "  try { window.__x(); } catch (e) {}"
        "  // hello"
        "  var fs = [];"
        "})();");
    return 0;
}}