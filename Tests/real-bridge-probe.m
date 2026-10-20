#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorScript.h"
#import "BrowserDOMInspectorBridge.h"

/// 直接用真实的 BrowserDOMInspectorScript 源码做端到端验证：
/// WKUserScript(forMainFrameOnly:NO) 注入 → 广播 enable → 跨源 iframe 回报 → hover 回传原生。

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger hoverCount;
@property (nonatomic, strong) NSDictionary *last;
@property (nonatomic, strong) NSMutableArray *diags;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    NSString *type = b[@"type"] ?: @"";
    if ([type isEqualToString:@"hover"]) { self.hoverCount++; self.last = b[@"payload"]; }
    if ([type isEqualToString:@"dom-inspector-diag"]) { [self.diags addObject:b]; }
}
@end

static void pump(double s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    printf("bootstrap len = %lu\n",
           (unsigned long)[BrowserDOMInspectorScript bootstrapScript].length);
    printf("startScript len = %lu\n",
           (unsigned long)[BrowserDOMInspectorScript startScript].length);

    H *h = [[H alloc] init];
    h.diags = [NSMutableArray array];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    // 诊断：给 bootstrap 加个标记，看它到底跑没跑
    NSString *bootDbg = [[BrowserDOMInspectorScript bootstrapScript]
        stringByReplacingOccurrencesOfString:@"(function() {"
                                    withString:@"(function() { window.__bootRan = true;"];
    printf("bootDbg len=%lu\n", (unsigned long)bootDbg.length);
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:[BrowserDOMInspectorScript startScript]
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:bootDbg
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,900,600) configuration:cfg];

    NSString *html = @"<html><body style='margin:20px'>"
        "<div id='t' style='width:300px;height:50px;background:#cde'>TARGET</div>"
        "</body></html>";
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://x.test/"]];
    pump(1.5);

    printf("diags after load: %lu\n", (unsigned long)h.diags.count);
    for (NSDictionary *d in h.diags) {
        printf("  diag tag=%s impl=%d booted=%d hasStart=%d active=%d isTop=%d\n",
               [d[@"tag"] UTF8String], [d[@"impl"] boolValue], [d[@"booted"] boolValue],
               [d[@"hasStart"] boolValue], [d[@"active"] boolValue], [d[@"isTop"] boolValue]);
    }

    // 加入一个 srcdoc iframe（跨源），验证 iframe 内探针
    [web evaluateJavaScript:
        @"(function(){var f=document.createElement('iframe');"
         "f.id='fr';f.style.width='500px';f.style.height='200px';"
         "f.srcdoc='<html><body><div id=\"inner\" style=\"width:200px;height:40px\">INNER</div></body></html>';"
         "document.body.appendChild(f);return 'added';})();" completionHandler:nil];
    pump(1.5);

    NSInteger diagsBefore = h.diags.count;
    // 广播 enable（模拟原生侧 broadcastEnable）
    for (int i = 0; i < 3; i++) {
        [web evaluateJavaScript:
            @"(function(){"
             "try{if(window.__meoDomInspectorStart&&!window.__meoDomInspectorStop){"
             "window.__meoDomInspectorStart();}}catch(e){}"
             "var fs=[];try{fs=document.querySelectorAll('iframe,frame');}catch(e){return;}"
             "for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1},'*');}catch(x){}}"
             "})();" completionHandler:nil];
        pump(0.5);
    }
    printf("diags after enable: %lu (new %ld)\n", (unsigned long)h.diags.count,
           (long)(h.diags.count - diagsBefore));
    for (NSUInteger i = diagsBefore; i < h.diags.count; i++) {
        NSDictionary *d = h.diags[i];
        printf("  diag tag=%s impl=%d booted=%d hasStart=%d active=%d isTop=%d href=%s\n",
               [d[@"tag"] UTF8String], [d[@"impl"] boolValue], [d[@"booted"] boolValue],
               [d[@"hasStart"] boolValue], [d[@"active"] boolValue], [d[@"isTop"] boolValue],
               [d[@"href"] UTF8String]);
    }

    // 在 iframe 内触发 hover
    NSInteger before2 = h.hoverCount;
    [web evaluateJavaScript:
        @"(function(){var f=document.getElementById('fr');"
         "try{var cw=f.contentWindow;var t=cw.document.getElementById('inner');"
         "t.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));"
         "t.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,clientX:10,clientY:10}));"
         "return 'sent-in-frame';}catch(e){return 'X:'+e.name;}})()"
                completionHandler:^(id r, NSError *e) {
        printf("iframe hover dispatch -> %s\n", [r description]);
    }];
    pump(1.0);
    printf("iframe hover delta = %ld\n", (long)(h.hoverCount - before2));
    if (h.hoverCount > before2) {
        printf("  tag=%s selector=%s\n", [h.last[@"tagName"] UTF8String],
               [h.last[@"selector"] UTF8String]);
    }

    // 直接查 iframe 内探针状态
    __block NSString *ifState = nil;
    [web evaluateJavaScript:
        @"(function(){try{var cw=document.getElementById('fr').contentWindow;"
         "return JSON.stringify({impl:!!cw.__meoDomInspectorImpl,"
         " bootRan:!!cw.__bootRan,"
         " booted:!!cw.__meoDomInspectorBooted,"
         " start:typeof cw.__meoDomInspectorStart,"
         " stop:typeof cw.__meoDomInspectorStop,"
         " hasTarget:!!cw.document.getElementById('inner'),"
         " href:String(cw.location.href).slice(0,60)});}catch(e){return 'X:'+e.name;}})()"
                completionHandler:^(id r, NSError *e) { ifState = [r description]; }];
    pump(0.4);
    printf("iframe state: %s\n", ifState ? ifState.UTF8String : "(nil)");

    // 在 iframe 内手动 eval bootstrap，看真实错误
    NSData *bd = [NSJSONSerialization dataWithJSONObject:@[[BrowserDOMInspectorScript bootstrapScript]]
                                                 options:0 error:NULL];
    NSString *ba = [[NSString alloc] initWithData:bd encoding:NSUTF8StringEncoding];
    NSString *besc = [ba substringWithRange:NSMakeRange(1, ba.length-2)];
    __block NSString *manR = nil;
    [web evaluateJavaScript:
        [NSString stringWithFormat:
         @"(function(){try{var cw=document.getElementById('fr').contentWindow;"
         "(0,eval)(%@);return 'ok booted='+!!cw.__meoDomInspectorBooted;}"
         "catch(e){return 'ERR:'+e.name+':'+e.message;}})()", besc]
                completionHandler:^(id r, NSError *e) { manR = [r description]; }];
    pump(0.5);
    printf("manual eval bootstrap in iframe: %s\n", manR ? manR.UTF8String : "(nil)");

    // 主框架内触发 hover
    [web evaluateJavaScript:
        @"(function(){var t=document.getElementById('t');"
         "t.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));"
         "t.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,"
         "clientX:30,clientY:40}));return 'sent';})();" completionHandler:nil];
    pump(0.9);

    printf("hover messages = %ld\n", (long)h.hoverCount);
    if (h.last) {
        printf("  tag=%s selector=%s\n", [h.last[@"tagName"] UTF8String],
               [h.last[@"selector"] UTF8String]);
    }
    return h.hoverCount > 0 ? 0 : 2;
} }