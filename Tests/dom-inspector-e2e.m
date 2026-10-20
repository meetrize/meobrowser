#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 端到端验证 DOM 探针注入脚本：
/// 真实 WKWebView + 真实注入脚本 + 真实 postMessage 通道，检查 hover 是否回传快照。

@interface Harness : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger hoverCount;
@property (nonatomic, strong) NSDictionary *lastPayload;
@property (nonatomic, copy) void (^onMessage)(void);
@end

@implementation Harness
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : @{};
    NSString *type = body[@"type"] ?: @"?";
    if ([type isEqualToString:@"hover"]) {
        self.hoverCount++;
        self.lastPayload = body[@"payload"];
    }
    printf("  [msg] type=%s tag=%s\n", type.UTF8String,
           [body[@"payload"][@"tagName"] ?: @"-" UTF8String]);
    if (self.onMessage) self.onMessage();
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    Harness *harness = [[Harness alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:harness name:@"meoDomInspector"];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                          configuration:config];
    WKWebView *windowWeb = webView;

    // 模拟表格 + 表单控件
    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif'>"
        @"<table border=1 cellpadding=6 width=600>"
        @"<tr><td>任务</td><td>状态</td></tr>"
        @"<tr id='r1'><td>报表A</td><td data-row='row[price]'>完成</td></tr>"
        @"<tr id='r2'><td>报表B</td><td>进行中</td></tr></table>"
        @"<form><input type='text' name='kw' value='abc' style='margin-top:20px'></form>"
        @"</body></html>";
    [windowWeb loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];

    // 等页面加载完成
    __block BOOL loaded = NO;
    for (int i = 0; i < 100 && !loaded; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        loaded = ([windowWeb.title length] > 0 || windowWeb.isLoading == NO);
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    printf("1) inject inspector script ...\n");
    NSString *script = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js"
                                               encoding:NSUTF8StringEncoding error:NULL];
    if (!script) { printf("   cannot read script file\n"); return 1; }

    __block NSString *evalError = nil;
    [windowWeb evaluateJavaScript:script completionHandler:^(id r, NSError *e) {
        evalError = e.localizedDescription;
    }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("   eval error: %s\n", evalError ? evalError.UTF8String : "(none)");

    printf("2) verify hooks installed ...\n");
    __block NSString *probe = nil;
    [windowWeb evaluateJavaScript:
        @"JSON.stringify({stop: typeof window.__meoDomInspectorStop,"
         " styleInDoc: !!document.getElementById('__meo_dom_inspector_style')})"
                completionHandler:^(id r, NSError *e) { probe = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    printf("   %s\n", probe ? probe.UTF8String : "(nil)");

    printf("2b) explicit start (script auto-start needs manual call when injected ad hoc) ...\n");
    [windowWeb evaluateJavaScript:@"window.__meoDomInspectorStart && window.__meoDomInspectorStart();"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    __block NSString *probe2 = nil;
    [windowWeb evaluateJavaScript:
        @"JSON.stringify({stop: typeof window.__meoDomInspectorStop,"
         " styleInDoc: !!document.getElementById('__meo_dom_inspector_style')})"
                completionHandler:^(id r, NSError *e) { probe2 = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    printf("   %s\n", probe2 ? probe2.UTF8String : "(nil)");

    printf("3) dispatch mouseover on table cell ...\n");
    [windowWeb evaluateJavaScript:
        @"document.querySelector('#r1 td:last-child').dispatchEvent("
         "new MouseEvent('mouseover', {bubbles:true, composed:true}))"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];

    printf("4) dispatch mouseover on input ...\n");
    [windowWeb evaluateJavaScript:
        @"document.querySelector('input').dispatchEvent("
         "new MouseEvent('mouseover', {bubbles:true, composed:true}))"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];

    // bootstrap-table 表头特征：固定容器 + sticky thead + 内部 div/span 包裹文本
    printf("5) build bootstrap-table-like header, then hover it ...\n");
    NSString *buildHeaderJS =
        @"var t=document.querySelector('table');"
         "var wrap=document.createElement('div');"
         "wrap.className='fixed-table-container';"
         "t.parentNode.insertBefore(wrap,t); wrap.appendChild(t);"
         "var ths=document.querySelectorAll('tr:first-child td');"
         "for (var i=0;i<ths.length;i++){"
         "  var c=ths[i];"
         "  c.setAttribute('style','position:sticky;top:0;background:#fff');"
         "  var inner=document.createElement('div'); inner.className='th-inner';"
         "  var icon=document.createElement('span'); icon.className='sort-icon';"
         "  var txt=document.createElement('span'); txt.className='th-text';"
         "  txt.textContent=c.textContent;"
         "  inner.appendChild(icon); inner.appendChild(txt);"
         "  c.textContent=''; c.appendChild(inner);"
         "}";
    [windowWeb evaluateJavaScript:buildHeaderJS completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];

    __block NSString *hdrReport = nil;
    [windowWeb evaluateJavaScript:
        @"(function(){"
         " var th=document.querySelector('.th-inner');"
         " var r=th.getBoundingClientRect();"
         " var cs=getComputedStyle(th);"
         " var atPoint=document.elementFromPoint(r.left+r.width/2, r.top+r.height/2);"
         " return JSON.stringify({rect:[Math.round(r.left),Math.round(r.top),Math.round(r.width),Math.round(r.height)],"
         "   pointerEvents:cs.pointerEvents, display:cs.display, visibility:cs.visibility,"
         "   topEl: atPoint ? atPoint.tagName+'.'+atPoint.className : 'null'});"
         "})()"
                completionHandler:^(id r, NSError *e) { hdrReport = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    printf("   header report: %s\n", hdrReport ? hdrReport.UTF8String : "(nil)");

    NSInteger beforeHeader = harness.hoverCount;
    [windowWeb evaluateJavaScript:
        @"(function(){var t=document.querySelector('.th-inner');"
         " t.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));})()"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("   hover delta on header = %ld\n", (long)(harness.hoverCount - beforeHeader));

    // 真实站点常见：在 document 上用捕获监听器 + stopImmediatePropagation 抢占事件，
    // 会让后注册的捕获监听器（探针）完全收不到事件。
    printf("6) page installs blocking capture listener, then hover again ...\n");
    [windowWeb evaluateJavaScript:
        @"window.__blocker=function(e){ e.stopImmediatePropagation(); };"
         "document.addEventListener('mouseover', window.__blocker, true);"
         "document.addEventListener('mousedown', window.__blocker, true);"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    NSInteger beforeBlocked = harness.hoverCount;
    // 模拟真实鼠标：pointermove 通道靠坐标采样，不受拦截影响。
    // 必须换一个未悬停过的元素，否则会被 lastHovered 去重挡掉。
    __block NSString *ptrReport = nil;
    [windowWeb evaluateJavaScript:
        @"(function(){"
         " var cells=document.querySelectorAll('#r2 td');"
         " var t=cells[cells.length-1];"
         " var r=t.getBoundingClientRect();"
         " var x=r.left+r.width/2, y=r.top+r.height/2;"
         " var hit=document.elementFromPoint(x,y);"
         " var ev=new PointerEvent('pointermove',{bubbles:true,composed:true,clientX:x,clientY:y});"
         " window.dispatchEvent(ev);"
         " return JSON.stringify({x:Math.round(x),y:Math.round(y),"
         "   atPoint: hit?hit.tagName+'.'+hit.className:'null'});"
         "})()"
                completionHandler:^(id r, NSError *e) { ptrReport = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    printf("   pointer dispatch: %s\n", ptrReport ? ptrReport.UTF8String : "(nil)");
    printf("   hover delta while page blocks = %ld  %s\n",
           (long)(harness.hoverCount - beforeBlocked),
           (harness.hoverCount - beforeBlocked) > 0 ? "(RECEIVED via pointermove)" : "(BLOCKED by page)");

    // 移除拦截后，走常规 mouseover 路径也应恢复
    [windowWeb evaluateJavaScript:
        @"document.removeEventListener('mouseover', window.__blocker, true);"
                completionHandler:nil];
    NSInteger beforeUnblocked = harness.hoverCount;
    [windowWeb evaluateJavaScript:
        @"(function(){var c=document.querySelectorAll('#r1 td')[0];"
         " c.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,composed:true}));})()"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    printf("   hover delta after unblock   = %ld\n",
           (long)(harness.hoverCount - beforeUnblocked));

    printf("RESULT: hover messages = %ld\n", (long)harness.hoverCount);
    if (harness.hoverCount > 0) {
        NSLog(@"last payload: %@", harness.lastPayload);
    }
    return harness.hoverCount > 0 ? 0 : 2;
} }
