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

    // 测试相邻字面量生成的字符串（无 LF）
    evalIt(wv, @"adj-1line", @"(function(){try{if(window.__x){window.__x();}}catch(e){}var fs=[];})();");
    evalIt(wv, @"adj-spaced", @"(function(){try { if (window.__x) { window.__x(); } } catch (e) {} var fs = [];})();");
    evalIt(wv, @"adj-cmt", @"(function(){try { if (window.__x) { window.__x(); } } catch (e) {} // hello\nvar fs = [];})();");
    evalIt(wv, @"adj-cmt-2", @"(function(){try { if (window.__x) { window.__x(); } } catch (e) {} // hello var fs = [];})();");

    // 关键：用 ObjC adjacent literal，**字符串里没转义**
    NSString *jsA = @"(function(){"
                     "  try { if (window.__x) {"
                     "    window.__x(); } } catch (e) {}"
                     "  // hello"
                     "  var fs = [];"
                     "})();";
    evalIt(wv, @"objc-adj-noLF", jsA);
    NSLog(@"%@", jsA);

    NSString *jsB = @"(function(){\n"
                     "  try { if (window.__x) {\n"
                     "    window.__x(); } } catch (e) {}\n"
                     "  // hello\n"
                     "  var fs = [];\n"
                     "})();";
    evalIt(wv, @"objc-adj-LF", jsB);
    NSLog(@"%@", jsB);
    return 0;
}}