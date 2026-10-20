#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 验证两个假设：
///  A) 探针注入后，页面再重新渲染 DOM（bootstrap-table 异步渲染 / 轮询刷新），
///     window 上的监听器是否仍然有效？
///  B) bootstrap-table 的 .fht-cell 固定表头覆盖层会不会挡住 hover？

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

static NSString *runJS(WKWebView *w, NSString *js) {
    __block NSString *out = nil;
    [w evaluateJavaScript:js completionHandler:^(id r, NSError *e) { out = [r description]; }];
    pump(0.25);
    return out;
}

/// 通过坐标派发 pointermove（模拟真实鼠标），返回命中的元素描述。
static NSString *hoverAt(WKWebView *w, NSString *selector) {
    NSString *js = [NSString stringWithFormat:
        @"(function(){var t=document.querySelector('%@');if(!t)return 'NO-EL';"
         "var r=t.getBoundingClientRect();var x=r.left+r.width/2,y=r.top+r.height/2;"
         "var hit=document.elementFromPoint(x,y);"
         "window.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,clientX:x,clientY:y}));"
         "return (hit?hit.tagName+'.'+hit.className:'null')+' @'+Math.round(x)+','+Math.round(y);})()",
        selector];
    return runJS(w, js);
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1200,800) configuration:cfg];

    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif'>"
        @"<table border=1 cellpadding=6 style='width:900px'>"
        @"<thead><tr>"
        @"<th style='text-align:center'><div class='th-inner '>任务名称(mtasksname)</div>"
        @"<div class='fht-cell' style='width:293px'></div></th>"
        @"<th style='text-align:center'><div class='th-inner'>状态</div>"
        @"<div class='fht-cell' style='width:120px'></div></th>"
        @"</tr></thead><tbody><tr><td>A</td><td>完成</td></tr></tbody></table>"
        @"</body></html>";
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    pump(1.0);

    NSString *script = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js" encoding:NSUTF8StringEncoding error:NULL];
    [web evaluateJavaScript:script completionHandler:nil];
    pump(0.4);

    printf("A) baseline hover on .th-inner ...\n");
    NSInteger c0 = h.count;
    printf("   hit=%s  delta=%ld\n", [hoverAt(web, @".th-inner") UTF8String],
           (long)(h.count - c0));

    printf("B) hover on .fht-cell (固定表头覆盖层) ...\n");
    NSInteger c1 = h.count;
    printf("   hit=%s  delta=%ld\n", [hoverAt(web, @".fht-cell") UTF8String],
           (long)(h.count - c1));

    printf("C) 页面重新渲染整个表格后（模拟 bootstrap-table 异步渲染/轮询）...\n");
    NSInteger c2 = h.count;
    [web evaluateJavaScript:
        @"document.querySelector('table').outerHTML ="
         "'<table border=1 cellpadding=6 style=\"width:900px\"><thead><tr>"
         "<th style=\"text-align:center\"><div class=\"th-inner new\">任务名称</div>"
         "<div class=\"fht-cell\" style=\"width:293px\"></div></th></tr></thead>"
         "<tbody><tr><td>X</td></tr></tbody></table>';" completionHandler:nil];
    pump(0.4);
    printf("   after re-render, hover .th-inner.new ...\n");
    printf("   hit=%s  delta=%ld  %s\n", [hoverAt(web, @".th-inner.new") UTF8String],
           (long)(h.count - c2), (h.count - c2) > 0 ? "(listener survived)" : "(LISTENER DEAD)");

    printf("D) body 是否被 consider() 跳过 ...\n");
    NSInteger c3 = h.count;
    printf("   hit=%s  delta=%ld\n", [hoverAt(web, @"body") UTF8String], (long)(h.count - c3));

    printf("E) 页面删掉探针注入的 <style> 后，自愈是否补回 ...\n");
    NSString *removed = runJS(web,
        @"(function(){var s=document.getElementById('__meo_dom_inspector_style');"
         "var had=!!s; if(s){s.remove();}"
         "return JSON.stringify({hadStyle:had});})()");
    printf("   %s\n", removed ? removed.UTF8String : "(nil)");
    pump(0.9);
    NSString *restored = runJS(web,
        @"(function(){return JSON.stringify({styleBack:!!document.getElementById('__meo_dom_inspector_style')});})()");
    printf("   after self-heal: %s\n", restored ? restored.UTF8String : "(nil)");

    printf("TOTAL hover messages = %ld\n", (long)h.count);
    return 0;
} }