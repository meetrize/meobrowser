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

    // 单字符串（不带捕获）
    evalIt(wv, @"plain", @"(function(){try{if(window.__x){window.__x();}}catch(e){}var fs=[];})();");

    // 带 if 嵌套
    evalIt(wv, @"if-nested",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}var fs=[];})();");

    // 多行（分号后换行 + 注释）
    evalIt(wv, @"multi-line-1",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}\ncatch(e){}\n// hello\nvar fs=[];})();");

    // 多行（try 块直接多行）
    evalIt(wv, @"multi-line-2",
        @"(function(){\ntry{if(window.__x&&!window.__s){window.__x();}}\ncatch(e){}\nvar fs=[];})();");

    // 关键：分号后立刻 `}` `}` catch
    evalIt(wv, @"brace-close",
        @"(function(){try{if(window.__x){window.__x();}}catch(e){}})();");
    evalIt(wv, @"brace-close-spc",
        @"(function(){try { if (window.__x) { window.__x(); } } catch (e) {}})();");
    // 加注释
    evalIt(wv, @"brace-close-cmt",
        @"(function(){try{if(window.__x){window.__x();}}catch(e){}// hello\nvar fs=[];})();");
    evalIt(wv, @"brace-close-cmt-spc",
        @"(function(){try { if (window.__x) { window.__x(); } } catch (e) {} // hello\nvar fs = [];})();");
    return 0;
}}