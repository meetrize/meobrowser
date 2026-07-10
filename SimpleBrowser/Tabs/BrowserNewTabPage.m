#import "BrowserNewTabPage.h"
#import <WebKit/WebKit.h>

@implementation BrowserNewTabPage

+ (NSString *)html {
    return @"<!DOCTYPE html>"
           @"<html lang=\"zh-CN\"><head><meta charset=\"utf-8\">"
           @"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
           @"<title>新标签页</title>"
           @"<style>"
           @"body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;"
           @"font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f5f7;color:#1d1d1f;}"
           @".card{text-align:center;padding:48px 32px;}"
           @"h1{font-size:28px;font-weight:600;margin:0 0 12px;}"
           @"p{font-size:15px;color:#6e6e73;margin:0;line-height:1.6;}"
           @"</style></head><body><div class=\"card\">"
           @"<h1>新标签页</h1>"
           @"<p>在地址栏输入网址后按回车开始浏览</p>"
           @"</div></body></html>";
}

+ (void)loadInWebView:(WKWebView *)webView {
    [webView loadHTMLString:[self html] baseURL:nil];
}

@end
