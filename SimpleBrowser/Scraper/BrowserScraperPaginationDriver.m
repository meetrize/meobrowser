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

/// 用于判断滚动后是否加载了更多内容（新闻卡片多为 a/article，不能只数 tr/li）。
+ (NSString *)scrollMetricsJavaScript {
    return @
    "(function(){\n"
    "  function docH(){\n"
    "    return Math.max(\n"
    "      (document.body && document.body.scrollHeight) || 0,\n"
    "      (document.documentElement && document.documentElement.scrollHeight) || 0,\n"
    "      (document.scrollingElement && document.scrollingElement.scrollHeight) || 0\n"
    "    );\n"
    "  }\n"
    "  function countItems(){\n"
    "    return document.querySelectorAll(\n"
    "      'a[href*=\"/news/\"], a[href*=\"/article\"], a[href*=\"/post\"], article, li, tr, [data-row], [role=\"listitem\"], main a[href], .grid > a, [class*=\"list\"] > a'\n"
    "    ).length;\n"
    "  }\n"
    "  var se = document.scrollingElement || document.documentElement || document.body;\n"
    "  return {\n"
    "    height: docH(),\n"
    "    count: countItems(),\n"
    "    top: se ? (se.scrollTop || 0) : (window.pageYOffset || 0)\n"
    "  };\n"
    "})()";
}

+ (void)scrollInWebView:(WKWebView *)webView
                stepPx:(NSInteger)stepPx
             settleMs:(NSInteger)settleMs
           completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    NSInteger step = MAX(400, stepPx > 0 ? stepPx : 1000);
    // 窗口级无限滚动常见需要更长等待（网络请求 + React 渲染）
    NSInteger settle = MAX(1200, settleMs > 0 ? settleMs : 1600);
    NSString *scrollJS = [NSString stringWithFormat:
                          @"(function(){\n"
                           "  function docH(){\n"
                           "    return Math.max(\n"
                           "      (document.body && document.body.scrollHeight) || 0,\n"
                           "      (document.documentElement && document.documentElement.scrollHeight) || 0,\n"
                           "      (document.scrollingElement && document.scrollingElement.scrollHeight) || 0\n"
                           "    );\n"
                           "  }\n"
                           "  function countItems(){\n"
                           "    return document.querySelectorAll(\n"
                           "      'a[href*=\"/news/\"], a[href*=\"/article\"], a[href*=\"/post\"], article, li, tr, [data-row], [role=\"listitem\"], main a[href], .grid > a, [class*=\"list\"] > a'\n"
                           "    ).length;\n"
                           "  }\n"
                           "  var beforeH = docH();\n"
                           "  var beforeC = countItems();\n"
                           "  var se = document.scrollingElement || document.documentElement || document.body;\n"
                           "  window.scrollBy(0, %ld);\n"
                           "  var target = Math.max(docH(), (se && se.scrollHeight) || 0);\n"
                           "  window.scrollTo(0, Math.max(0, target));\n"
                           "  if(se){ try{ se.scrollTop = Math.max(0, se.scrollHeight); }catch(e){} }\n"
                           "  try{ window.dispatchEvent(new Event('scroll')); }catch(e){}\n"
                           "  return { before: beforeH, countBefore: beforeC };\n"
                           "})()", (long)step];

    [webView evaluateJavaScript:scrollJS completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }
        NSInteger before = [result isKindOfClass:[NSDictionary class]] ? [result[@"before"] integerValue] : 0;
        NSInteger countBefore = [result isKindOfClass:[NSDictionary class]] ? [result[@"countBefore"] integerValue] : 0;
        NSInteger attempts = MAX(3, (NSInteger)ceil(settle / 400.0));
        [self pollScrollGrowthInWebView:webView
                                 before:before
                            countBefore:countBefore
                          attemptsLeft:attempts
                            completion:completion];
    }];
}

+ (void)pollScrollGrowthInWebView:(WKWebView *)webView
                           before:(NSInteger)before
                      countBefore:(NSInteger)countBefore
                    attemptsLeft:(NSInteger)attemptsLeft
                      completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:[self scrollMetricsJavaScript] completionHandler:^(id after, NSError *err2) {
            (void)err2;
            NSInteger height = [after isKindOfClass:[NSDictionary class]] ? [after[@"height"] integerValue] : before;
            NSInteger count = [after isKindOfClass:[NSDictionary class]] ? [after[@"count"] integerValue] : countBefore;
            BOOL advanced = (height > before + 8) || (count > countBefore);
            if (advanced) {
                if (completion) completion(YES, nil);
                return;
            }
            if (attemptsLeft <= 1) {
                NSString *nudge =
                    @"(function(){ var se=document.scrollingElement||document.documentElement||document.body;\n"
                     "  var h=Math.max((document.body&&document.body.scrollHeight)||0,(document.documentElement&&document.documentElement.scrollHeight)||0);\n"
                     "  window.scrollTo(0,h); if(se) se.scrollTop=se.scrollHeight;\n"
                     "  try{ window.dispatchEvent(new Event('scroll')); }catch(e){}\n"
                     "  return true; })()";
                [webView evaluateJavaScript:nudge completionHandler:^(id r, NSError *e) {
                    (void)r; (void)e;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(700 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                        [webView evaluateJavaScript:[self scrollMetricsJavaScript] completionHandler:^(id after2, NSError *e2) {
                            (void)e2;
                            NSInteger h2 = [after2 isKindOfClass:[NSDictionary class]] ? [after2[@"height"] integerValue] : before;
                            NSInteger c2 = [after2 isKindOfClass:[NSDictionary class]] ? [after2[@"count"] integerValue] : countBefore;
                            BOOL ok = (h2 > before + 8) || (c2 > countBefore);
                            if (completion) completion(ok, nil);
                        }];
                    });
                }];
                return;
            }
            [self pollScrollGrowthInWebView:webView
                                     before:before
                                countBefore:countBefore
                              attemptsLeft:attemptsLeft - 1
                                completion:completion];
        }];
    });
}

@end
