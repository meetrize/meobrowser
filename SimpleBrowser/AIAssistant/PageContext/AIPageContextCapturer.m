#import "AIPageContextCapturer.h"
#import "AIPageContextBundle.h"
#import "AIPageContextResource.h"
#import "AIPageContextStore.h"

@implementation AIPageContextCapturer

+ (AIPageContextCapturer *)sharedCapturer {
    static AIPageContextCapturer *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[AIPageContextCapturer alloc] init];
    });
    return c;
}

- (nullable NSString *)loadCaptureScript {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *path = [bundle pathForResource:@"meo-page-context" ofType:@"js" inDirectory:@"AIAssistant"];
    if (!path.length) {
        path = [bundle pathForResource:@"meo-page-context" ofType:@"js"];
    }
    if (!path.length) return nil;
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

- (void)captureFromWebView:(WKWebView *)webView
                     tabID:(NSUUID *)tabID
          maxArticleChars:(NSUInteger)maxArticleChars
                completion:(AIPageContextCaptureCompletion)completion {
    if (!completion) return;
    if (!webView) {
        completion(nil, @"没有可采集的网页");
        return;
    }

    NSString *script = [self loadCaptureScript];
    if (script.length == 0) {
        completion(nil, @"缺少页面采集脚本");
        return;
    }

    NSUInteger maxChars = maxArticleChars > 0 ? maxArticleChars : 24000;
    NSUInteger maxHtml = 100000;
    NSString *runner = [NSString stringWithFormat:
                        @"%@\n"
                        @"(function(){try{"
                        @"return window.__MeoPageContext.capture({"
                        @"maxArticleChars:%lu,"
                        @"maxHtmlChars:%lu,"
                        @"includeResources:true,"
                        @"layers:['meta','article','outline','html','markdown']"
                        @"});"
                        @"}catch(e){return {ok:false,error:String(e&&e.message||e)};}})()",
                        script, (unsigned long)maxChars, (unsigned long)maxHtml];

    [webView evaluateJavaScript:runner completionHandler:^(id result, NSError *error) {
        if (error) {
            completion(nil, error.localizedDescription ?: @"采集失败");
            return;
        }
        if (![result isKindOfClass:[NSDictionary class]]) {
            completion(nil, @"采集结果无效");
            return;
        }
        NSDictionary *dict = (NSDictionary *)result;
        id okVal = dict[@"ok"];
        if ([okVal respondsToSelector:@selector(boolValue)] && ![okVal boolValue]) {
            NSString *err = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : @"采集失败";
            completion(nil, err);
            return;
        }
        AIPageContextBundle *bundle = [AIPageContextBundle bundleFromCaptureDictionary:dict tabID:tabID];
        if (!bundle) {
            completion(nil, @"无法解析页面上下文");
            return;
        }
        if (!bundle.urlString.length) {
            bundle.urlString = webView.URL.absoluteString;
        }
        if (!bundle.title.length) {
            bundle.title = webView.title;
        }
        if (tabID) {
            [[AIPageContextStore sharedStore] setBundle:bundle forTabID:tabID];
        }
        completion(bundle, nil);
    }];
}

- (void)loadTextForResource:(AIPageContextResource *)resource
                  inWebView:(WKWebView *)webView
                   maxChars:(NSUInteger)maxChars
                 completion:(AIPageContextResourceLoadCompletion)completion {
    if (!completion) return;
    if (!resource || !webView) {
        completion(NO, nil, @"无效资源");
        return;
    }
    if (resource.hasTextBody) {
        completion(YES, resource.text, nil);
        return;
    }
    if (resource.urlString.length == 0) {
        completion(NO, nil, @"无 URL");
        return;
    }

    NSString *script = [self loadCaptureScript];
    if (script.length == 0) {
        completion(NO, nil, @"缺少页面采集脚本");
        return;
    }

    NSUInteger limit = maxChars > 0 ? maxChars : 65536;
    NSString *urlJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:resource.urlString options:0 error:nil]
                                              encoding:NSUTF8StringEncoding];
    if (!urlJSON.length) urlJSON = @"\"\"";
    NSString *runner = [NSString stringWithFormat:
                        @"%@\n"
                        @"(function(){try{"
                        @"return window.__MeoPageContext.fetchResourceText(%@, %lu);"
                        @"}catch(e){return Promise.resolve({ok:false,error:String(e&&e.message||e)});}})()",
                        script, urlJSON, (unsigned long)limit];

    resource.loading = YES;
    [webView evaluateJavaScript:runner completionHandler:^(id result, NSError *error) {
        resource.loading = NO;
        if (error) {
            completion(NO, nil, error.localizedDescription ?: @"加载失败");
            return;
        }
        // Promise 可能仍未解包（旧 WebKit）；若是 thenable 再取一次少见，此处期望已是 dict
        NSDictionary *dict = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        if (!dict) {
            completion(NO, nil, @"加载结果无效");
            return;
        }
        id okVal = dict[@"ok"];
        if (![okVal respondsToSelector:@selector(boolValue)] || ![okVal boolValue]) {
            NSString *err = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : @"加载失败";
            completion(NO, nil, err);
            return;
        }
        NSString *text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : @"";
        resource.text = text;
        resource.reportedSize = text.length;
        completion(YES, text, nil);
    }];
}

@end
