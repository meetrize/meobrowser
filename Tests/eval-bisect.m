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

    // 简化
    evalIt(wv, @"just-try",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。})();");
    evalIt(wv, @"ascii-only",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// broadcast})();");
    evalIt(wv, @"cjk-broadcast",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 广播})();");
    evalIt(wv, @"cjk-广播给所有子框架",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 广播给所有子框架})();");
    evalIt(wv, @"full-cjk-text",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。})();");
    evalIt(wv, @"with-real-newline",
        @"(function(){\n"
         @"try{if(window.__x&&!window.__s){window.__x();}}catch(e){}\n"
         @"// 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。\n"
         @"})();");
    evalIt(wv, @"object-literal",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');})();");
    evalIt(wv, @"everything-but-comment",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}})();");
    evalIt(wv, @"every-then-cmt-last",
        @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}// 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。})();");
    return 0;
}}