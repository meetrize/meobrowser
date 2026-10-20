#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

void evalIt(WKWebView *wv, NSString *label, NSString *js) {
    __block NSString *res;
    [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        if (e) res = [NSString stringWithFormat:@"ERR(%ld): %@",
                       (long)e.code, e.localizedDescription];
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

    NSString *full = @"(function(){"
                     "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) {"
                     "    window.__meoDomInspectorStart(); } } catch (e) {}"
                     "  // 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。"
                     "  var fs = [];"
                     "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }"
                     "  for (var i = 0; i < fs.length; i++) {"
                     "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1}, '*'); } catch (x) {}"
                     "  }"
                     "})();";
    evalIt(wv, @"full-original", full);
    evalIt(wv, @"full-no-cmt", @"(function(){try{if(window.__meoDomInspectorStart&&!window.__meoDomInspectorStop){window.__meoDomInspectorStart();}}catch(e){}var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}})();");
    return 0;
}}