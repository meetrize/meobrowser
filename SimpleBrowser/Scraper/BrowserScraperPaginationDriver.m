#import "BrowserScraperPaginationDriver.h"

@implementation BrowserScraperPaginationDriver

+ (NSString *)jsonStringLiteral:(NSString *)string {
    NSString *safe = [string isKindOfClass:[NSString class]] ? string : @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:nil];
    if (!data) return @"\"\"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"\"\"";
}

+ (void)advanceInWebView:(WKWebView *)webView
              pagination:(BrowserScraperPagination *)pagination
              completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    if (!webView || !pagination) {
        if (completion) completion(NO, nil);
        return;
    }
    switch (pagination.type) {
        case BrowserScraperPaginationTypeNextButton:
        case BrowserScraperPaginationTypeLoadMore:
            [self clickSelector:pagination.selector inWebView:webView completion:completion];
            break;
        case BrowserScraperPaginationTypePageNumbers:
            [self clickNextPageNumber:pagination.selector inWebView:webView completion:completion];
            break;
        case BrowserScraperPaginationTypeInfiniteScroll:
            [self scrollInWebView:webView
                          stepPx:pagination.scrollStepPx
                       settleMs:pagination.scrollSettleMs
                     completion:completion];
            break;
        default:
            if (completion) completion(NO, nil);
            break;
    }
}

+ (void)clickSelector:(NSString *)selector
            inWebView:(WKWebView *)webView
           completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    NSString *selJSON = [self jsonStringLiteral:selector];
    NSString *js = [NSString stringWithFormat:
                    @"(function(){ var sel=%@; var el=sel&&document.querySelector(sel);\n"
                     "  if(!el) return { ok:false, reason:'missing' };\n"
                     "  if(el.disabled || el.getAttribute('aria-disabled')==='true' || el.classList.contains('disabled')) return { ok:false, reason:'disabled' };\n"
                     "  el.click(); return { ok:true }; })()", selJSON];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }
        BOOL ok = [result isKindOfClass:[NSDictionary class]] && [result[@"ok"] boolValue];
        if (completion) completion(ok, nil);
    }];
}

+ (void)clickNextPageNumber:(NSString *)selector
                  inWebView:(WKWebView *)webView
                 completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    NSString *selJSON = [self jsonStringLiteral:selector];
    NSString *js = [NSString stringWithFormat:
                    @"(function(){\n"
                     "  var sel=%@;\n"
                     "  var nodes = sel ? Array.from(document.querySelectorAll(sel)) : [];\n"
                     "  if(!nodes.length) return { ok:false };\n"
                     "  var activeIdx = nodes.findIndex(function(n){ return n.classList.contains('active') || n.getAttribute('aria-current')==='page'; });\n"
                     "  var next = nodes[activeIdx+1] || null;\n"
                     "  if(!next){\n"
                     "    // fallback: click element whose text is current+1\n"
                     "    var cur = activeIdx>=0 ? parseInt((nodes[activeIdx].textContent||'').trim(),10) : NaN;\n"
                     "    if(!isNaN(cur)){\n"
                     "      next = nodes.find(function(n){ return parseInt((n.textContent||'').trim(),10)===cur+1; }) || null;\n"
                     "    }\n"
                     "  }\n"
                     "  if(!next) return { ok:false };\n"
                     "  next.click(); return { ok:true };\n"
                     "})()", selJSON];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }
        BOOL ok = [result isKindOfClass:[NSDictionary class]] && [result[@"ok"] boolValue];
        if (completion) completion(ok, nil);
    }];
}

+ (void)scrollInWebView:(WKWebView *)webView
                stepPx:(NSInteger)stepPx
             settleMs:(NSInteger)settleMs
           completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    NSString *js = [NSString stringWithFormat:
                    @"(function(){\n"
                     "  var before = document.body.scrollHeight;\n"
                     "  var countBefore = document.querySelectorAll('tr,li,[data-row]').length;\n"
                     "  window.scrollBy(0, %ld);\n"
                     "  return { before: before, countBefore: countBefore };\n"
                     "})()", (long)MAX(1, stepPx)];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        (void)error;
        NSInteger before = [result isKindOfClass:[NSDictionary class]] ? [result[@"before"] integerValue] : 0;
        NSInteger countBefore = [result isKindOfClass:[NSDictionary class]] ? [result[@"countBefore"] integerValue] : 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0, settleMs) * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            NSString *check =
                @"(function(){ return { height: document.body.scrollHeight, count: document.querySelectorAll('tr,li,[data-row]').length }; })()";
            [webView evaluateJavaScript:check completionHandler:^(id after, NSError *err2) {
                (void)err2;
                NSInteger height = [after isKindOfClass:[NSDictionary class]] ? [after[@"height"] integerValue] : before;
                NSInteger count = [after isKindOfClass:[NSDictionary class]] ? [after[@"count"] integerValue] : countBefore;
                BOOL advanced = (height > before) || (count > countBefore);
                if (completion) completion(advanced, nil);
            }];
        });
    }];
}

@end
