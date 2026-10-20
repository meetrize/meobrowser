#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 最小案例：WKUserScript 在 WKWebView 中到底会不会执行？
/// 分别测试 loadHTMLString 与 loadRequest 两种加载方式。

static void check(NSString *label, void (^setup)(WKWebViewConfiguration *cfg), NSString *url) {
    @autoreleasepool {
        WKUserContentController *ucc = [[WKUserContentController alloc] init];
        WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
        cfg.userContentController = ucc;
        setup(cfg);
        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,600,400) configuration:cfg];
        if (url) {
            [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
        } else {
            [web loadHTMLString:@"<html><body>hello</body></html>"
                        baseURL:[NSURL URLWithString:@"https://x.test/"]];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
        __block NSString *res = nil;
        [web evaluateJavaScript:@"JSON.stringify({ran:!!window.__usRan, ready:document.readyState})"
                completionHandler:^(id r, NSError *e) { res = [r description]; }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
        printf("%-40s %s\n", label.UTF8String, res.UTF8String);
    }
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];

    check(@"loadHTMLString + documentStart", ^(WKWebViewConfiguration *cfg) {
        [cfg.userContentController addUserScript:
            [[WKUserScript alloc] initWithSource:@"window.__usRan = true;"
                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                              forMainFrameOnly:NO]];
    }, nil);

    check(@"loadHTMLString + documentEnd", ^(WKWebViewConfiguration *cfg) {
        [cfg.userContentController addUserScript:
            [[WKUserScript alloc] initWithSource:@"window.__usRan = true;"
                                 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                              forMainFrameOnly:NO]];
    }, nil);

    check(@"loadHTMLString + mainFrameOnly YES", ^(WKWebViewConfiguration *cfg) {
        [cfg.userContentController addUserScript:
            [[WKUserScript alloc] initWithSource:@"window.__usRan = true;"
                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                              forMainFrameOnly:YES]];
    }, nil);

    return 0;
} }