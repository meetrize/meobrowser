#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 用自定义 scheme 模拟跨源：a.test 与 b.test 是不同 origin。
/// 通过 WKURLSchemeHandler 响应，避免依赖外部 HTTP 服务器。
/// 验证：WKUserScript(forMainFrameOnly:NO) 是否注入到跨源子框架。

@interface SchemeHandler : NSObject <WKURLSchemeHandler>
@property (nonatomic, copy) NSDictionary *pages;   // host -> html
@end

@implementation SchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *url = task.request.URL;
    NSString *html = self.pages[url.host ?: @""] ?: @"<html><body>404</body></html>";
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    [task didReceiveResponse:[[NSURLResponse alloc] initWithURL:url
                                                      MIMEType:@"text/html"
                                         expectedContentLength:data.length
                                              textEncodingName:@"utf-8"]];
    [task didReceiveData:data];
    [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {}
@end

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger hoverCount;
@property (nonatomic, strong) NSDictionary *last;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    printf("  [native] isMainFrame=%d type=%s\n", m.frameInfo.isMainFrame,
           [b[@"type"] UTF8String]);
    if ([b[@"type"] isEqualToString:@"hover"]) { self.hoverCount++; self.last = b[@"payload"]; }
}
@end

static void pump(double s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSString *childHTML =
        @"<html><body><div id='target' style='width:300px;height:60px;background:#ccc'>CHILD</div>"
        @"<script>"
        @"window.__report = function(tag){"
        @"  try{ window.parent.postMessage({__meo:'child-report', tag:tag,"
        @"    impl:!!window.__meoDomInspectorImpl,"
        @"    booted:!!window.__meoDomInspectorBooted,"
        @"    start:typeof window.__meoDomInspectorStart,"
        @"    stop:typeof window.__meoDomInspectorStop}, '*'); }catch(e){}"
        @"};"
        @"window.addEventListener('message', function(e){"
        @"  var d=e&&e.data; if(!d)return;"
        @"  window.__report('msg:'+JSON.stringify(d));"
        @"  if(d.__meo==='probe-hover'){"
        @"    var t=document.getElementById('target');"
        @"    t.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));"
        @"    t.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,"
        @"      clientX:t.getBoundingClientRect().left+50, clientY:t.getBoundingClientRect().top+20}));"
        @"  }"
        @"});"
        @"setTimeout(function(){window.__report('boot');}, 300);"
        @"</script></body></html>";

    NSString *parentHTML =
        @"<html><body><h1>PARENT</h1>"
        @"<iframe id='f' style='width:700px;height:300px' src='b.test/child'></iframe>"
        @"<script>"
        @"window.__reports = [];"
        @"window.addEventListener('message', function(e){"
        @"  var d=e&&e.data; if(!d)return;"
        @"  if(d.__meo==='child-report'){ window.__reports.push(d); }"
        @"}, false);"
        @"</script></body></html>";

    SchemeHandler *sh = [[SchemeHandler alloc] init];
    sh.pages = @{ @"a.test": parentHTML, @"b.test": childHTML };

    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];

    // 探针实现 + bootstrap（模拟真实应用的 WKUserScript 配置）
    NSString *impl = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js" encoding:NSUTF8StringEncoding error:NULL];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:impl
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];
    // 主框架负责把子框架的消息转发给原生（跨源 iframe 无法直连原生 handler）
    NSString *boot =
        @"(function(){window.addEventListener('message',function(e){"
         "var d=e&&e.data;if(!d)return;"
         "if(d.__meo==='dom-inspector-payload'){"
         "try{window.webkit.messageHandlers.meoDomInspector.postMessage(d.payload);}catch(x){}return;}"
         "},false);})();";
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:boot
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    [cfg setURLSchemeHandler:sh forURLScheme:@"a"];
    [cfg setURLSchemeHandler:sh forURLScheme:@"b"];
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,900,600) configuration:cfg];

    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"a.test/"]]];
    pump(2.0);

    // 子框架是否真的加载
    __block NSString *childInfo = nil;
    [web evaluateJavaScript:
        @"(function(){var f=document.getElementById('f');"
         "try{ var cw=f.contentWindow; return JSON.stringify({src:f.getAttribute('src'),"
         "  href:cw.location.href, hasTarget:!!cw.document.getElementById('target'),"
         "  impl:!!cw.__meoDomInspectorImpl, booted:!!cw.__meoDomInspectorBooted}); }"
         "catch(e){ return JSON.stringify({err:e.name}); }})()"
                completionHandler:^(id r, NSError *e) { childInfo = [r description]; }];
    pump(0.4);
    printf("child info: %s\n", childInfo ? childInfo.UTF8String : "(nil)");

    // 确认 postMessage 在自定义 scheme 下是否可用（主框架自测）
    __block NSString *pmTest = nil;
    [web evaluateJavaScript:
        @"(function(){window.__pm=[];"
         "window.addEventListener('message',function(e){window.__pm.push('got:'+JSON.stringify(e.data));},false);"
         "window.postMessage({t:1},'*');"
         "return 'posted';})();" completionHandler:nil];
    pump(0.5);
    [web evaluateJavaScript:@"JSON.stringify(window.__pm||[])"
            completionHandler:^(id r, NSError *e) { pmTest = [r description]; }];
    pump(0.3);
    printf("self postMessage: %s\n", pmTest ? pmTest.UTF8String : "(nil)");

    // 询问子框架状态
    [web evaluateJavaScript:
        @"(function(){var cw=document.getElementById('f').contentWindow;"
         "try{cw.postMessage({__meo:'probe-state'},'*');}catch(e){}"
         "return 'asked';})();" completionHandler:nil];
    pump(1.0);

    __block NSString *rep = nil;
    [web evaluateJavaScript:@"JSON.stringify(window.__reports||[])"
            completionHandler:^(id r, NSError *e) { rep = [r description]; }];
    pump(0.3);
    printf("child reports: %s\n", rep ? rep.UTF8String : "(nil)");

    // 广播 enable（含 postMessage 转发）
    for (int i = 0; i < 3; i++) {
        [web evaluateJavaScript:
            @"(function(){"
             "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) { window.__meoDomInspectorStart(); } } catch (e) {}"
             "  var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}"
             "  for (var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}"
             "})();" completionHandler:nil];
        pump(0.5);
    }

    __block NSString *rep2 = nil;
    [web evaluateJavaScript:@"JSON.stringify(window.__reports||[])"
            completionHandler:^(id r, NSError *e) { rep2 = [r description]; }];
    pump(0.3);
    printf("after enable: %s\n", rep2 ? rep2.UTF8String : "(nil)");

    // 请求子框架内 hover
    [web evaluateJavaScript:
        @"(function(){var cw=document.getElementById('f').contentWindow;"
         "try{cw.postMessage({__meo:'probe-hover'},'*');}catch(e){}"
         "return 'asked';})();" completionHandler:nil];
    pump(1.0);
    printf("hover messages = %ld\n", (long)h.hoverCount);
    if (h.last) {
        printf("  tag=%s selector=%s\n", [h.last[@"tagName"] UTF8String],
               [h.last[@"selector"] UTF8String]);
    }
    return 0;
} }