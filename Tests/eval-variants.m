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

    NSString *tests[][2] = {
      // [label, js]
      {@"A: no-cmt", @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__m:'d','o':1},'*');}catch(x){}}})();"},
      {@"B: ascii-cmt", @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// comment\nvar fs=[];})();"},
      {@"C: cjk-cmt", @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 注释中文\nvar fs=[];})();"},
      {@"D: cn-comment-with-cjk", @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 广播给所有子框架\nvar fs=[];})();"},
      {@"E: multi-cjk", @"(function(){try{if(window.__x&&!window.__s){window.__x();}}catch(e){}// 中文字符\n// 第二行\nvar fs=[];})();"},
    };
    int n = 5;
    for (int i = 0; i < n; i++) {
        NSString *label = tests[i][0];
        NSString *js = tests[i][1];
        __block NSString *res;
        [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
            if (e) res = [NSString stringWithFormat:@"ERR: %@", e];
            else res = @"ok";
        }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        printf("[%s] %s\n", label.UTF8String, (res ?: @"?").UTF8String);
    }
    return 0;
}}