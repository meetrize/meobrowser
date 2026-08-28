#import "PagePackInjector.h"
#import "PagePackModels.h"
#import "PagePackStore.h"
#import "PagePackSettings.h"
#import "PagePackMatcher.h"
#import "BrowserRiskHostPolicy.h"

@implementation PagePackInjector

+ (instancetype)sharedInjector {
    static PagePackInjector *injector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        injector = [[self alloc] init];
    });
    return injector;
}

+ (NSString *)jsonLiteralForString:(NSString *)string {
    NSString *safe = string ?: @"";
    // dataWithJSONObject: 默认不允许顶层 NSString，直接传入会抛异常导致 SIGABRT。
    // 一律包进数组再剥掉外层 []，避免依赖 FragmentsAllowed。
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[safe] options:0 error:&error];
    if (!data) {
        return @"\"\"";
    }
    NSString *arrayLit = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayLit.length < 2) {
        return @"\"\"";
    }
    return [arrayLit substringWithRange:NSMakeRange(1, arrayLit.length - 2)];
}

+ (NSString *)styleAttributeIDForPack:(NSString *)packID fileName:(NSString *)fileName {
    return [NSString stringWithFormat:@"%@:%@", packID ?: @"", fileName ?: @""];
}

- (void)evaluate:(NSString *)source inWebView:(WKWebView *)webView {
    if (source.length == 0 || !webView) {
        return;
    }
    [webView evaluateJavaScript:source completionHandler:nil];
}

- (NSString *)cssInjectionSourceForPackID:(NSString *)packID
                                 fileName:(NSString *)fileName
                                    css:(NSString *)css {
    NSString *attr = [[self class] styleAttributeIDForPack:packID fileName:fileName];
    NSString *attrLit = [[self class] jsonLiteralForString:attr];
    NSString *cssLit = [[self class] jsonLiteralForString:css ?: @""];
    NSString *suppressFn =
        [BrowserRiskHostPolicy javaScriptShouldSuppressPageAutomationFunctionNamed:@"meoShouldSkipPagePackCSS"];
    return [NSString stringWithFormat:
            @"(function(){%@ if(meoShouldSkipPagePackCSS())return; try{"
            @"var id=%@;var css=%@;"
            @"var el=document.querySelector('style[data-meo-pagepack=\"'+id+'\"]');"
            @"if(!el){el=document.createElement('style');el.setAttribute('data-meo-pagepack',id);"
            @"(document.documentElement||document).appendChild(el);}"
            @"el.textContent=css;"
            @"}catch(e){}})();",
            suppressFn, attrLit, cssLit];
}

- (NSString *)cssRemovalSourceForPackID:(NSString *)packID {
    NSString *prefixLit = [[self class] jsonLiteralForString:[NSString stringWithFormat:@"%@:", packID ?: @""]];
    return [NSString stringWithFormat:
            @"(function(){try{"
            @"var prefix=%@;"
            @"document.querySelectorAll('style[data-meo-pagepack]').forEach(function(el){"
            @"var v=el.getAttribute('data-meo-pagepack')||'';"
            @"if(v.indexOf(prefix)===0){el.remove();}"
            @"});"
            @"}catch(e){}})();",
            prefixLit];
}

- (NSString *)jsWrapperSource:(NSString *)source fileName:(NSString *)fileName packID:(NSString *)packID {
    NSString *body = source ?: @"";
    NSString *label = [NSString stringWithFormat:@"meo-pagepack %@/%@", packID ?: @"?", fileName ?: @"?"];
    NSString *labelLit = [[self class] jsonLiteralForString:label];
    NSString *suppressFn =
        [BrowserRiskHostPolicy javaScriptShouldSuppressPageAutomationFunctionNamed:@"meoShouldSkipPagePack"];
    return [NSString stringWithFormat:
            @"(function(){%@ if(meoShouldSkipPagePack())return; try{%@}catch(e){try{console.error(%@,e);}catch(_){}}})();",
            suppressFn, body, labelLit];
}

- (NSArray<PagePackFile *> *)sortedFiles:(NSArray<PagePackFile *> *)files kind:(PagePackFileKind)kind {
    NSMutableArray<PagePackFile *> *filtered = [NSMutableArray array];
    for (PagePackFile *file in files) {
        if (file.kind == kind) {
            [filtered addObject:file];
        }
    }
    [filtered sortUsingComparator:^NSComparisonResult(PagePackFile *a, PagePackFile *b) {
        return [a.name compare:b.name];
    }];
    return filtered;
}

- (void)injectCSSForPack:(PagePack *)pack webView:(WKWebView *)webView {
    PagePackStore *store = [PagePackStore sharedStore];
    for (PagePackFile *file in [self sortedFiles:pack.files kind:PagePackFileKindCSS]) {
        NSString *content = [store contentOfFile:file.name inPack:pack.packID error:nil] ?: @"";
        NSString *js = [self cssInjectionSourceForPackID:pack.packID fileName:file.name css:content];
        [self evaluate:js inWebView:webView];
    }
}

- (void)injectJSForPack:(PagePack *)pack
                webView:(WKWebView *)webView
                  phase:(PagePackInjectionPhase)phase
               includeAll:(BOOL)includeAll {
    PagePackStore *store = [PagePackStore sharedStore];
    NSArray<PagePackFile *> *jsFiles = [self sortedFiles:pack.files kind:PagePackFileKindJS];
    NSMutableArray<PagePackFile *> *toRun = [NSMutableArray array];
    for (PagePackFile *file in jsFiles) {
        if (includeAll) {
            [toRun addObject:file];
            continue;
        }
        if (phase == PagePackInjectionPhaseDocumentStart) {
            if (file.runAt == PagePackRunAtDocumentStart) {
                [toRun addObject:file];
            }
        } else {
            if (file.runAt == PagePackRunAtDocumentEnd || file.runAt == PagePackRunAtDocumentIdle) {
                [toRun addObject:file];
            }
        }
    }

    for (PagePackFile *file in toRun) {
        NSString *content = [store contentOfFile:file.name inPack:pack.packID error:nil] ?: @"";
        if (content.length == 0) {
            continue;
        }
        NSString *wrapped = [self jsWrapperSource:content fileName:file.name packID:pack.packID];
        if (!includeAll && phase == PagePackInjectionPhaseDocumentEnd && file.runAt == PagePackRunAtDocumentIdle) {
            __weak WKWebView *weakWebView = webView;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WKWebView *strong = weakWebView;
                if (strong) {
                    [self evaluate:wrapped inWebView:strong];
                }
            });
        } else {
            [self evaluate:wrapped inWebView:webView];
        }
    }
}

- (void)injectMatchingPacksIntoWebView:(WKWebView *)webView
                                   URL:(NSURL *)url
                                 phase:(PagePackInjectionPhase)phase {
    if (!webView || ![PagePackSettings sharedSettings].pagePackEnabled) {
        return;
    }
    if (!url || !([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) {
        return;
    }
    // 人机页 / 风险域不注入用户脚本，避免干扰 Cloudflare Turnstile 等挑战环境。
    if ([BrowserRiskHostPolicy shouldSuppressPageAutomationForURL:url title:webView.title]) {
        return;
    }
    @try {
        NSArray<PagePack *> *packs = [[PagePackStore sharedStore] enabledPacksMatchingURL:url];
        for (PagePack *pack in packs) {
            if (phase == PagePackInjectionPhaseDocumentStart) {
                [self injectCSSForPack:pack webView:webView];
            }
            [self injectJSForPack:pack webView:webView phase:phase includeAll:NO];
        }
    } @catch (NSException *exception) {
        NSLog(@"[PagePack] injectMatchingPacks failed: %@", exception);
    }
}

- (void)hotApplyPack:(PagePack *)pack toWebView:(WKWebView *)webView URL:(NSURL *)url {
    if (!pack || !webView || ![PagePackSettings sharedSettings].pagePackEnabled) {
        return;
    }
    if ([BrowserRiskHostPolicy shouldSuppressPageAutomationForURL:url ?: webView.URL title:webView.title]) {
        return;
    }
    @try {
        if (!pack.enabled) {
            [self removeCSSForPackID:pack.packID fromWebView:webView];
            return;
        }
        if (url && ![PagePackMatcher URL:url matchesPack:pack]) {
            return;
        }
        [self injectCSSForPack:pack webView:webView];
        [self injectJSForPack:pack webView:webView phase:PagePackInjectionPhaseDocumentEnd includeAll:YES];
    } @catch (NSException *exception) {
        NSLog(@"[PagePack] hotApplyPack failed: %@", exception);
    }
}

- (void)removeCSSForPackID:(NSString *)packID fromWebView:(WKWebView *)webView {
    if (packID.length == 0 || !webView) {
        return;
    }
    [self evaluate:[self cssRemovalSourceForPackID:packID] inWebView:webView];
}

@end
