#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 验证：同一 WKUserContentController 上注册两个 WKUserScript(forMainFrameOnly:NO)，
/// 它们是否都会进入子框架？逐一加标记。

static void check(NSString *label, NSArray<NSString *> *sources) {
    @autoreleasepool {
        WKUserContentController *ucc = [[WKUserContentController alloc] init];
        for (NSString *src in sources) {
            [ucc addUserScript:[[WKUserScript alloc] initWithSource:src
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:NO]];
        }
        WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
        cfg.userContentController = ucc;
        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,600,400) configuration:cfg];

        NSString *html = @"<html><body><div id='t'>X</div>"
            @"<iframe id='f' style='width:400px;height:150px' srcdoc='<html><body><div id=\"i\">I</div></body></html>'></iframe>"
            @"</body></html>";
        [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://x.test/"]];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];

        __block NSString *main1 = nil, *main2 = nil, *f1 = nil, *f2 = nil;
        [web evaluateJavaScript:@"JSON.stringify({a:!!window.__a,b:!!window.__b})"
                completionHandler:^(id r, NSError *e) { main1 = [r description]; }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        [web evaluateJavaScript:
            @"(function(){try{var cw=document.getElementById('f').contentWindow;"
             "return JSON.stringify({a:!!cw.__a,b:!!cw.__b});}catch(e){return 'X';}})()"
                completionHandler:^(id r, NSError *e) { f1 = [r description]; }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        printf("%-34s main=%-26s frame=%s\n", label.UTF8String,
               main1.UTF8String, f1.UTF8String);
    }
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *a = @"window.__a = true;";
    NSString *b = @"window.__b = true;";
    check(@"single A", @[a]);
    check(@"single B", @[b]);
    check(@"A then B", @[a, b]);
    check(@"B then A", @[b, a]);
    return 0;
} }