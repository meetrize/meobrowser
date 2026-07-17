#import "BrowserFeedURLSchemeHandler.h"
#import "BrowserFeedReader.h"

@implementation BrowserFeedURLSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    (void)webView;
    NSURL *requestURL = urlSchemeTask.request.URL;
    NSURL *feedURL = [BrowserFeedReader feedURLFromReaderURL:requestURL];
    if (!feedURL) {
        NSError *error = [NSError errorWithDomain:@"BrowserFeedURLSchemeHandler"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的 Feed 阅读地址"}];
        [urlSchemeTask didFailWithError:error];
        return;
    }

    __weak id<WKURLSchemeTask> weakTask = urlSchemeTask;
    [BrowserFeedReader loadReadableHTMLForFeedURL:feedURL
                                completionHandler:^(NSString *html, NSError *error) {
        id<WKURLSchemeTask> strongTask = weakTask;
        if (!strongTask) {
            return;
        }

        if (error || html.length == 0) {
            NSString *message = error.localizedDescription ?: @"无法加载 Feed";
            html = [NSString stringWithFormat:
                    @"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Feed</title></head>"
                    @"<body style=\"font:15px/1.5 -apple-system;padding:24px;background:#f7f5f0;color:#1c1917;\">"
                    @"<h1>无法显示 Feed</h1><p>%@</p>"
                    @"<p><a href=\"%@\">%@</a></p></body></html>",
                    message, feedURL.absoluteString, feedURL.absoluteString];
        }

        NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSURLResponse *response =
            [[NSURLResponse alloc] initWithURL:requestURL
                                      MIMEType:@"text/html"
                         expectedContentLength:(NSInteger)data.length
                              textEncodingName:@"utf-8"];
        @try {
            [strongTask didReceiveResponse:response];
            [strongTask didReceiveData:data];
            [strongTask didFinish];
        } @catch (__unused NSException *exception) {
            // Task 可能已被 stopURLSchemeTask 取消。
        }
    }];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    (void)webView;
    (void)urlSchemeTask;
}

@end
