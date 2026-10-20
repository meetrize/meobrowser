#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 决定性验证：WKUserScript(forMainFrameOnly:NO) 是否会注入到跨源子框架？
/// 做法：给 ucc 加一个只写 window.__userScriptRan = true 的用户脚本，
/// 跨源子框架无法被父页面读取，因此让子框架自己把标志 postMessage 出来。

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) NSMutableArray *msgs;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    printf("  [native] isMainFrame=%d body=%s\n", m.frameInfo.isMainFrame,
           [[b description] UTF8String]);
    [self.msgs addObject:b];
}
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"probe"];
    // 标记脚本
    [ucc addUserScript:[[WKUserScript alloc]
        initWithSource:@"(function(){window.__userScriptRan = true;})();"
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1000,700) configuration:cfg];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8898/"]];
    [web loadRequest:req];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3.0]];

    // 主框架里检查自己有没有被注入
    __block NSString *mainFlag = nil;
    [web evaluateJavaScript:@"JSON.stringify({ran:!!window.__userScriptRan, title:document.title, ready:document.readyState})"
            completionHandler:^(id r, NSError *e) { mainFlag = [r description]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    printf("main frame userScriptRan = %s\n", mainFlag.UTF8String);

    // 让子框架回报
    [web evaluateJavaScript:
        @"(function(){var f=document.getElementById('f');"
         "try{ f.contentWindow.postMessage({__meo:'ask'},'*'); }catch(e){}"
         "return 'sent';})();" completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    printf("native received %lu message(s)\n", (unsigned long)h.msgs.count);
    return 0;
} }