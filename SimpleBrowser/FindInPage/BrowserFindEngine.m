#import "BrowserFindEngine.h"

@implementation BrowserFindResult
@end

@implementation BrowserFindEngine

+ (NSString *)userScriptSource {
    static NSString *source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"find-in-page" ofType:@"js"];
        if (path.length > 0) {
            NSError *error = nil;
            NSString *fileSource = [NSString stringWithContentsOfFile:path
                                                             encoding:NSUTF8StringEncoding
                                                                error:&error];
            if (fileSource.length > 0 && error == nil) {
                source = fileSource;
                return;
            }
        }
        source = @"(function(){window.__MeoFind=window.__MeoFind||{search:function(){return{matchCount:0,currentIndex:0}},next:function(){return{matchCount:0,currentIndex:0}},prev:function(){return{matchCount:0,currentIndex:0}},clear:function(){return{matchCount:0,currentIndex:0}},selectionText:function(){return'';}};})();";
    });
    return source;
}

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) {
        return;
    }
    WKUserContentController *ucc = configuration.userContentController;
    NSString *source = [self userScriptSource];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)jsonEscape:(NSString *)string {
    if (!string) {
        return @"\"\"";
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string] options:0 error:&error];
    if (!data || error) {
        return @"\"\"";
    }
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // ["..."] → "..."
    if (arrayJSON.length < 2) {
        return @"\"\"";
    }
    return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
}

+ (BrowserFindResult *)resultFromObject:(id)object {
    BrowserFindResult *result = [[BrowserFindResult alloc] init];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return result;
    }
    NSDictionary *dict = (NSDictionary *)object;
    result.matchCount = [dict[@"matchCount"] integerValue];
    result.currentIndex = [dict[@"currentIndex"] integerValue];
    result.wrapped = [dict[@"wrapped"] boolValue];
    result.truncated = [dict[@"truncated"] boolValue];
    result.invalidQuery = [dict[@"invalidQuery"] boolValue];
    return result;
}

+ (void)evaluateJavaScript:(NSString *)js
                 inWebView:(WKWebView *)webView
                completion:(void (^)(id _Nullable value))completion {
    if (!webView || js.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    [webView evaluateJavaScript:js completionHandler:^(id value, NSError *error) {
        (void)error;
        if (completion) {
            completion(value);
        }
    }];
}

+ (void)ensureBridgeInWebView:(WKWebView *)webView completion:(void (^)(BOOL ready))completion {
    NSString *check = @"(function(){return !!(window.__MeoFind && window.__MeoFind.search);})()";
    [self evaluateJavaScript:check inWebView:webView completion:^(id value) {
        if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) {
            if (completion) {
                completion(YES);
            }
            return;
        }
        NSString *inject = [self userScriptSource];
        [self evaluateJavaScript:inject inWebView:webView completion:^(id ignored) {
            (void)ignored;
            if (completion) {
                completion(YES);
            }
        }];
    }];
}

+ (void)searchInWebView:(WKWebView *)webView
                  query:(NSString *)query
                   mode:(BrowserFindMode)mode
          caseSensitive:(BOOL)caseSensitive
             completion:(void (^)(BrowserFindResult *result))completion {
    NSString *modeString = (mode == BrowserFindModeWildcard) ? @"wildcard" : @"literal";
    NSString *escaped = [self jsonEscape:query ?: @""];
    NSString *js = [NSString stringWithFormat:
                    @"(function(){if(!window.__MeoFind){return {matchCount:0,currentIndex:0};}"
                    "return window.__MeoFind.search({query:%@,mode:\"%@\",caseSensitive:%@});})()",
                    escaped,
                    modeString,
                    caseSensitive ? @"true" : @"false"];
    [self ensureBridgeInWebView:webView completion:^(BOOL ready) {
        (void)ready;
        [self evaluateJavaScript:js inWebView:webView completion:^(id value) {
            if (completion) {
                completion([self resultFromObject:value]);
            }
        }];
    }];
}

+ (void)nextInWebView:(WKWebView *)webView
           completion:(void (^)(BrowserFindResult *result))completion {
    [self evaluateJavaScript:@"window.__MeoFind&&window.__MeoFind.next()"
                   inWebView:webView
                  completion:^(id value) {
        if (completion) {
            completion([self resultFromObject:value]);
        }
    }];
}

+ (void)previousInWebView:(WKWebView *)webView
               completion:(void (^)(BrowserFindResult *result))completion {
    [self evaluateJavaScript:@"window.__MeoFind&&window.__MeoFind.prev()"
                   inWebView:webView
                  completion:^(id value) {
        if (completion) {
            completion([self resultFromObject:value]);
        }
    }];
}

+ (void)clearInWebView:(WKWebView *)webView
            completion:(void (^)(void))completion {
    if (!webView) {
        if (completion) {
            completion();
        }
        return;
    }
    [self evaluateJavaScript:@"window.__MeoFind&&window.__MeoFind.clear()"
                   inWebView:webView
                  completion:^(id value) {
        (void)value;
        if (completion) {
            completion();
        }
    }];
}

+ (void)selectionTextInWebView:(WKWebView *)webView
                    completion:(void (^)(NSString *text))completion {
    [self ensureBridgeInWebView:webView completion:^(BOOL ready) {
        (void)ready;
        [self evaluateJavaScript:@"(window.__MeoFind&&window.__MeoFind.selectionText)?window.__MeoFind.selectionText():(window.getSelection?window.getSelection().toString():'')"
                       inWebView:webView
                      completion:^(id value) {
            NSString *text = [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
            if (completion) {
                completion(text);
            }
        }];
    }];
}

@end
