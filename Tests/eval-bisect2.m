#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

void evalIt(WKWebView *wv, NSString *label, NSString *js) {
    __block NSString *res;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        if (e) res = [@"ERR: " stringByAppendingString:e.localizedDescription];
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

    evalIt(wv, @"base",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}})();");
    evalIt(wv, @"base-then-comment",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}})();// hello");
    evalIt(wv, @"base-then-cjk-comment",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}})();// 你好");
    evalIt(wv, @"inside-comment",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 你好\n})();");
    evalIt(wv, @"inside-comment-ascii",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// hello\n})();");
    evalIt(wv, @"inside-comment-empty-cmt",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// \n})();");
    evalIt(wv, @"inside-comment-only-spaces",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}//   \n})();");
    evalIt(wv, @"no-comma",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 你好 我在 这 里\n})();");
    evalIt(wv, @"multi-line-cmt",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// line1\n// line2\n})();");
    return 0;
}}