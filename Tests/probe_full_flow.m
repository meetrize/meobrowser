#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Harness : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger hoverCount;
@property (nonatomic, assign) NSInteger pinnedCount;
@property (nonatomic, strong) NSDictionary *lastPayload;
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
    if ([type isEqualToString:@"pinned"]) {
        self.pinnedCount++;
        self.lastPayload = body[@"payload"];
    }
    if ([type isEqualToString:@"cancelled"]) {
        self.pinnedCount = -999;
    }
    printf("  [msg] type=%s tag=%s id=%s\n", type.UTF8String,
           [body[@"payload"][@"tagName"] ?: @"-" UTF8String],
           [body[@"payload"][@"id"] ?: @"-" UTF8String]);
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    Harness *harness = [[Harness alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:harness name:@"meoDomInspector"];

    // 注入主框架和子框架都使用 impl 的 WKUserScript
    NSString *script = [NSString stringWithContentsOfFile:
        @"/Volumes/SSD4T/pro/meobrowser/SimpleBrowser/Developer/.dom-inspector-script.js"
                                               encoding:NSUTF8StringEncoding error:NULL];
    if (!script) { printf("cannot read\n"); return 1; }
    NSLog(@"script length=%lu", (unsigned long)script.length);

    WKUserScript *us = [[WKUserScript alloc] initWithSource:script
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO];
    [ucc addUserScript:us];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;

    WKWebView *windowWeb = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                              configuration:config];

    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif'>"
        @"<table border=1 cellpadding=6 width=600>"
        @"<tr><td>任务</td><td>状态</td></tr>"
        @"<tr id='r1'><td>报表A</td><td data-row='row[price]'>完成</td></tr>"
        @"<tr id='r2'><td>报表B</td><td>进行中</td></tr></table>"
        @"</body></html>";
    [windowWeb loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];

    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!windowWeb.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("1) start inspector\n");
    __block NSString *r1;
    [windowWeb evaluateJavaScript:
        @"(function(){try {"
         " var s = window.__meoDomInspectorStart;"
         " var before = typeof window.__meoDomInspectorStop;"
         " if (typeof s === 'function') { s(); } else { return 'no start: ' + typeof s; }"
         " var after = typeof window.__meoDomInspectorStop;"
         " return JSON.stringify({before:before, after:after,"
         "   hasStart: typeof window.__meoDomInspectorStart,"
         "   hasImpl: !!window.__meoDomInspectorImpl,"
         "   styleInDoc: !!document.getElementById('__meo_dom_inspector_style')});"
         "} catch(e) { return 'ERR:' + e.message; }})()"
                completionHandler:^(id r, NSError *e) { r1 = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("   %s\n", r1 ? r1.UTF8String : "(nil)");

    printf("2) dispatch mouseover on table cell\n");
    NSInteger before1 = harness.hoverCount;
    [windowWeb evaluateJavaScript:
        @"document.querySelector('#r1 td:last-child').dispatchEvent("
         "new MouseEvent('mouseover', {bubbles:true, composed:true}))"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("   hover delta = %ld\n", (long)(harness.hoverCount - before1));

    printf("3) dispatch mouseover on input\n");
    NSInteger before2 = harness.hoverCount;
    [windowWeb evaluateJavaScript:
        @"document.querySelector('#r2 td:last-child').dispatchEvent("
         "new MouseEvent('mouseover', {bubbles:true, composed:true}))"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("   hover delta = %ld\n", (long)(harness.hoverCount - before2));

    printf("4) pointermove (window dispatch)\n");
    NSInteger before3 = harness.hoverCount;
    [windowWeb evaluateJavaScript:
        @"(function(){"
         " var c = document.querySelector('#r1 td:last-child');"
         " var r = c.getBoundingClientRect();"
         " var ev = new PointerEvent('pointermove', {bubbles:true, composed:true,"
         "  clientX: r.left + 10, clientY: r.top + 5});"
         " window.dispatchEvent(ev);"
         "})()"
    completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("   hover delta = %ld\n", (long)(harness.hoverCount - before3));

    printf("5) mousedown (pin)\n");
    NSInteger beforePin = harness.pinnedCount;
    [windowWeb evaluateJavaScript:
        @"document.querySelector('#r1 td:last-child').dispatchEvent("
         "new MouseEvent('mousedown', {bubbles:true, composed:true}))"
                completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("   pinned delta = %ld\n", (long)(harness.pinnedCount - beforePin));

    printf("RESULT: hover=%ld pinned=%ld\n", (long)harness.hoverCount, (long)harness.pinnedCount);
    if (harness.lastPayload) {
        NSLog(@"last payload: %@", harness.lastPayload);
    }
    return 0;
} }