#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 复刻新架构验证：
///  1. WKUserScript(forMainFrameOnly:NO) 把探针实现 + bootstrap 下发到每个框架
///  2. 原生侧在主框架广播 enable，并用 postMessage 转发给子框架（含跨源）
///  3. 验证跨源 iframe 内 hover 能把消息送回原生

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, strong) NSDictionary *last;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    printf("  [native msg] frame.isMain=%d type=%s\n",
           m.frameInfo.isMainFrame, [b[@"type"] UTF8String]);
    if ([b[@"type"] isEqualToString:@"hover"]) { self.count++; self.last = b[@"payload"]; }
}
@end

static void pump(double s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSString *impl = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js" encoding:NSUTF8StringEncoding error:NULL];
    NSString *bootstrap =
        @"(function(){if(window.__meoDomInspectorBooted)return;"
         "window.__meoDomInspectorBooted=true;"
         "window.__meoDomInspectorApply=function(on){try{"
         "if(on){if(window.__meoDomInspectorStart&&!window.__meoDomInspectorStop){window.__meoDomInspectorStart();}}"
         "else{if(window.__meoDomInspectorStop){window.__meoDomInspectorStop();}}}catch(e){}};"
         "window.addEventListener('message',function(e){"
         "var d=e&&e.data;if(!d)return;"
         "if(d.__meo==='dom-inspector-payload'){"
         "try{window.webkit.messageHandlers.meoDomInspector.postMessage(d.payload);}catch(x){}return;}"
         "if(d.__meo!=='dom-inspector')return;"
         "window.__meoDomInspectorApply(!!d.on);"
         "try{var fs=document.querySelectorAll('iframe,frame');"
         "for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':!!d.on},'*');}catch(x){}}}catch(x){}"
         "},false);"
         // 回报本框架探针状态，便于验证跨源框架是否拿到了实现
         "window.addEventListener('message',function(e){"
         "var d=e&&e.data;if(!d||d.__meo!=='probe-state')return;"
         "try{window.parent.postMessage({__meo:'probe-reply',"
         " impl:!!window.__meoDomInspectorImpl,"
         " booted:!!window.__meoDomInspectorBooted,"
         " start:typeof window.__meoDomInspectorStart,"
         " stop:typeof window.__meoDomInspectorStop},'*');}catch(x){}"
         "},false);})();";

    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:bootstrap
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:impl
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1000,700) configuration:cfg];

    // 父页面来自真实 HTTP 服务，其内嵌 iframe 指向另一个端口 → 真跨源
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8898/"]];
    [web loadRequest:req];
    pump(2.5);
    // 子框架用真实跨域 HTTP 源（与父页面 host 不同）
    pump(1.5);

    // 确认子框架真的加载了
    __block NSString *href = nil;
    [web evaluateJavaScript:
        @"(function(){try{return document.getElementById('f').contentWindow.location.href;}"
         "catch(e){return 'X:'+e.name;}})()"
                completionHandler:^(id r, NSError *e) { href = [r description]; }];
    pump(0.4);
    printf("child href: %s\n", href ? href.UTF8String : "(nil)");

    // 主框架监听子框架的状态回报
    [web evaluateJavaScript:
        @"(function(){window.__replies=[];"
         "window.addEventListener('message',function(e){"
         "var d=e&&e.data;if(!d)return;"
         "if(d.__meo==='probe-top-ok'){window.__replies.push(d);return;}"
         "if(d.__meo!=='probe-reply')return;"
         "window.__replies.push(d);},false);return 'ok';})();"
                completionHandler:nil];
    pump(0.2);

    // 子框架内部状态无法从父页面读取（跨源），改为把状态 postMessage 出来。
    __block NSString *fi = nil;
    [web evaluateJavaScript:
        @"(function(){try{var cw=document.getElementById('f').contentWindow;"
         "cw.postMessage({__meo:'probe-state'},'*');return 'sent';}catch(e){return 'X';}})()"
                completionHandler:nil];
    pump(0.5);
    __block NSString *rep = nil;
    [web evaluateJavaScript:@"JSON.stringify(window.__replies||[])"
            completionHandler:^(id r, NSError *e) { rep = [r description]; }];
    pump(0.3);
    printf("child probe: %s replies=%s\n", fi ? fi.UTF8String : "(nil)",
           rep ? rep.UTF8String : "(nil)");

    // 原生侧广播 enable + postMessage 转发
    for (int round = 0; round < 4; round++) {
        [web evaluateJavaScript:
            @"(function(){"
             "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) { window.__meoDomInspectorStart(); } } catch (e) {}"
             "  var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}"
             "  for (var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}"
             "})();" completionHandler:nil];
        pump(0.5);
    }

    __block NSString *st = nil;
    [web evaluateJavaScript:
        @"(function(){try{var cw=document.getElementById('f').contentWindow;"
         "return JSON.stringify({stop:typeof cw.__meoDomInspectorStop, href:cw.location.href});}catch(e){return 'X:'+e.name;}})()"
                completionHandler:^(id r, NSError *e) { st = [r description]; }];
    pump(0.3);
    printf("child after enable: %s\n", st ? st.UTF8String : "(nil)");

    // 让跨源 iframe 内部自己派发 hover
    __block NSString *hv = nil;
    [web evaluateJavaScript:
        @"(function(){var cw=document.getElementById('f').contentWindow;"
         "cw.postMessage({__meo:'probe-hover'},'*');return 'sent';})()"
                completionHandler:^(id r, NSError *e) { hv = [r description]; }];
    pump(0.9);
    printf("hover request: %s  messages=%ld\n", hv ? hv.UTF8String : "(nil)", (long)h.count);
    if (h.last) {
        printf("  tag=%s selector=%s\n", [h.last[@"tagName"] UTF8String],
               [h.last[@"selector"] UTF8String]);
    }
    return h.count > 0 ? 0 : 2;
} }