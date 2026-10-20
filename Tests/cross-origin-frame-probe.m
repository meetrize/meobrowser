#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 验证跨源 iframe：WKUserScript(forMainFrameOnly:NO) 是否让子框架拿到
/// messageHandlers，并在其中加载探针后把 hover 消息送回原生。
/// 这里用 WKWebView 直接加载一个跨源子框架（不同 host），并预先注入 bootstrap。

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, strong) NSDictionary *last;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    if ([b[@"type"] isEqualToString:@"hover"]) { self.count++; self.last = b[@"payload"]; }
}
@end

static void pump(double s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSString *jsPath = @"SimpleBrowser/Developer/.dom-inspector-script.js";
    NSString *script = [NSString stringWithContentsOfFile:jsPath encoding:NSUTF8StringEncoding error:NULL];
    printf("script bytes: %lu\n", (unsigned long)script.length);

    // 复刻 Bridge：document-start bootstrap 下发到所有框架
    NSString *bootstrap =
        @"(function(){if(window.__meoDomInspectorBooted)return;"
         "window.__meoDomInspectorBooted=true;"
         "window.__meoDomInspectorListen=function(){"
         "if(window.__meoDomInspectorReady)return;"
         "if(!window.__meoDomInspectorSource)return;"
         "window.__meoDomInspectorReady=true;"
         "try{(0,eval)(window.__meoDomInspectorSource);}catch(e){}};})();";

    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:bootstrap
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1000,700) configuration:cfg];

    // 主页面 + 一个 data: 子框架（与主页面不同源）
    NSString *outer = @"<html><body><h1>main</h1>"
        "<iframe id='f' style='width:800px;height:400px'></iframe></body></html>";
    [web loadHTMLString:outer baseURL:[NSURL URLWithString:@"https://parent.example/"]];
    pump(1.0);

    // 检查主框架 bootstrap 是否就绪
    __block NSString *b1 = nil;
    [web evaluateJavaScript:@"JSON.stringify({booted:!!window.__meoDomInspectorBooted,"
                            "listen:typeof window.__meoDomInspectorListen,"
                            "mh:!!(window.webkit&&window.webkit.messageHandlers)})"
            completionHandler:^(id r, NSError *e) { b1 = [r description]; }];
    pump(0.3);
    printf("main frame: %s\n", b1 ? b1.UTF8String : "(nil)");

    // data: iframe 内容
    NSString *inner = @"<html><body style='margin:30px'><div id='target' "
        "style='width:300px;height:60px;background:#ccc'>IN-CROSS-ORIGIN</div></body></html>";
    __block NSString *setR = nil;
    [web evaluateJavaScript:
        @"(function(){var d=document.createElement('div');d.id='t';"
         "document.body.appendChild(d);"
         "document.getElementById('f').src='data:text/html;charset=utf-8,'+"
         "encodeURIComponent(arguments[0]);return 'set';})()"
                completionHandler:^(id r, NSError *e) { setR = [r description]; }];
    (void)inner; (void)setR;
    pump(1.2);

    // 用 evaluateJavaScript 把源码下发到主框架，主框架再尝试同源下发（data: 视为不透明源）
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[script] options:0 error:NULL];
    NSString *arr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    NSString *escaped = [arr substringWithRange:NSMakeRange(1, arr.length-2)];
    NSString *driver = [NSString stringWithFormat:
        @"(function(){var S=%@;var seen=0;"
         "function inj(w){try{w.__meoDomInspectorSource=S;"
         "if(typeof w.__meoDomInspectorListen==='function'){w.__meoDomInspectorListen();}else{(0,eval)(S);}"
         "seen++;return true;}catch(e){return false;}}"
         "function walk(w,d){if(d>6)return;if(!inj(w))return;return seen;}"
         "var n=walk(window,0);return JSON.stringify({injected:n, ready:!!window.__meoDomInspectorStop});})()",
        escaped];
    __block NSString *inj = nil;
    [web evaluateJavaScript:driver completionHandler:^(id r, NSError *e) { inj = [r description]; }];
    pump(0.5);
    printf("inject main: %s\n", inj ? inj.UTF8String : "(nil)");

    // 主框架内触发 hover
    __block NSString *hv = nil;
    [web evaluateJavaScript:
        @"(function(){var t=document.getElementById('t');var r=t.getBoundingClientRect();"
         "var k='clientX';"
         "window.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,"
         "clientX:r.left+50,clientY:r.top+20}));"
         "t.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));"
         "return JSON.stringify({hasStop:typeof window.__meoDomInspectorStop});})()"
                completionHandler:^(id r, NSError *e) { hv = [r description]; }];
    pump(0.9);
    printf("hover main: %s  messages=%ld\n", hv ? hv.UTF8String : "(nil)", (long)h.count);
    if (h.last) {
        printf("  tag=%s selector=%s\n", [h.last[@"tagName"] UTF8String],
               [h.last[@"selector"] UTF8String]);
    }
    return 0;
} }