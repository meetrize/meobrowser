#import "BrowserWebView.h"
#import "BrowsingPreferences.h"

// 查询参数名：document-start 脚本据此在页面脚本运行前写回 location.hash。
static NSString * const kMeoHashRestoreQueryItem = @"__meo_hf";

const NSTimeInterval BrowserMainFrameNavigationTimeout = 12.0;

@interface BrowserWebView ()
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuDownload;
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuOpenInNewWindow;
@property (nonatomic, weak) NSMenuItem *openResourceMenuItem;
@property (nonatomic, weak) NSMenuItem *openLinkInNewWindowMenuItem;
@property (nonatomic, strong, nullable) NSEvent *contextMenuEvent;
@end

@implementation BrowserWebView

+ (NSURLRequest *)requestByApplyingNavigationTimeout:(NSURLRequest *)request {
    if (!request) {
        return request;
    }
    // 默认 60s；不可达主机（如未代理访问境外站点）会空等到超时才失败。
    if (request.timeoutInterval <= BrowserMainFrameNavigationTimeout) {
        return request;
    }
    NSMutableURLRequest *timed = [request mutableCopy];
    timed.timeoutInterval = BrowserMainFrameNavigationTimeout;
    return timed;
}

/// replaceState 不会像原生 #锚点导航那样滚动；补上 id/name 定位（与浏览器行为对齐）。
/// 使用 behavior:'instant'，避免站点 html{scroll-behavior:smooth} 把跳转拖成动画、与后续脚本抢滚动。
static NSString *MeoScrollToFragmentJS(void) {
    return
        @"function __meoScrollToFragment(h){"
        @"if(!h){try{window.scrollTo(0,0);}catch(e){}return true;}"
        @"var el=document.getElementById(h);"
        @"if(!el){var list=document.getElementsByName(h);if(list&&list.length)el=list[0];}"
        @"if(!el)return false;"
        @"try{el.scrollIntoView({block:'start',inline:'nearest',behavior:'instant'});}"
        @"catch(e){try{el.scrollIntoView(true);}catch(e2){}}"
        @"try{if(el.tabIndex<0)el.tabIndex=-1;el.focus({preventScroll:true});}catch(e3){"
        @"try{el.focus();}catch(e4){}"
        @"}"
        @"return true;"
        @"}"
        @"function __meoScrollToFragmentWhenReady(h){"
        @"if(__meoScrollToFragment(h))return;"
        @"var left=40;"
        @"var timer=setInterval(function(){"
        @"if(__meoScrollToFragment(h)||--left<=0)clearInterval(timer);"
        @"},50);"
        @"}";
}

+ (void)installFragmentRestoreScriptOnContentController:(WKUserContentController *)controller {
    if (controller == nil) {
        return;
    }
    // document-start：在页面脚本读 location 前，用 replaceState 写回 #hash（勿用 location.hash=
    // 或加载后再改 hash——代理下会变成带 # 的真实导航 → 404）。
    // replaceState 含 # 时 WebKit 可能一直 isLoading；DOMContentLoaded 后稍延迟 window.stop()
    // 结束幽灵加载，又给 SPA 留出发起接口请求的时间（过早 stop 会出现「连接服务器超时」）。
    // replaceState 不会滚到锚点，须在 DOM 就绪后补 scrollIntoView。
    NSString *restoreJS = [NSString stringWithFormat:
        @"(function(){"
        @"try{"
        @"%@;"
        @"var qs=new URLSearchParams(location.search);"
        @"if(!qs.has('__meo_hf'))return;"
        @"var h=qs.get('__meo_hf')||'';"
        @"qs.delete('__meo_hf');"
        @"var q=qs.toString();"
        @"history.replaceState(null,'',location.pathname+(q?('?'+q):'')+'#'+h);"
        @"var scroll=function(){__meoScrollToFragmentWhenReady(h);};"
        @"if(document.readyState==='loading'){"
        @"document.addEventListener('DOMContentLoaded',function(){"
        @"scroll();"
        @"setTimeout(function(){try{window.stop();}catch(e){}},150);"
        @"});"
        @"}else{"
        @"scroll();"
        @"setTimeout(function(){try{window.stop();}catch(e){}},150);"
        @"}"
        @"}catch(e){}"
        @"})();",
        MeoScrollToFragmentJS()];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:restoreJS
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:YES]];
}

/// 页面 commit 后清掉残留 __meo_hf；写回 hash 只用 replaceState，避免触发联网导航。
+ (void)cleanupHashRestoreQueryInWebView:(WKWebView *)webView {
    [self cleanupHashRestoreQueryInWebView:webView completion:nil];
}

+ (void)cleanupHashRestoreQueryInWebView:(WKWebView *)webView
                              completion:(void (^)(NSString *href))completion {
    if (webView == nil) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    NSString *js = [NSString stringWithFormat:
        @"(function(){"
        @"try{"
        @"%@;"
        @"var qs=new URLSearchParams(location.search);"
        @"if(!qs.has('__meo_hf'))return location.href;"
        @"var h=qs.get('__meo_hf')||'';"
        @"qs.delete('__meo_hf');"
        @"var q=qs.toString();"
        @"var path=location.pathname+(q?('?'+q):'');"
        @"var hash=(location.hash&&location.hash.length>1)?location.hash:('#'+h);"
        @"history.replaceState(null,'',path+hash);"
        @"var frag=hash.length>1?hash.substring(1):h;"
        @"__meoScrollToFragmentWhenReady(frag);"
        @"setTimeout(function(){try{window.stop();}catch(e){}},150);"
        @"return location.href;"
        @"}catch(e){return null;}"
        @"})();",
        MeoScrollToFragmentJS()];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (!completion) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            completion(nil);
            return;
        }
        completion((NSString *)result);
    }];
}

/// 同文档仅改 hash：用 replaceState，避免 http+# 经代理发网 404；并滚到锚点。
+ (void)applySameDocumentFragment:(NSString *)fragment inWebView:(WKWebView *)webView {
    [self applySameDocumentFragment:fragment inWebView:webView completion:nil];
}

+ (void)applySameDocumentFragment:(NSString *)fragment
                        inWebView:(WKWebView *)webView
                       completion:(void (^)(NSString *href))completion {
    if (webView == nil) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    NSString *frag = fragment ?: @"";
    NSString *escaped = [[[frag stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
        stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]
        stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    // 返回 location.href，便于原生侧立刻把地址栏写成带 # 的对外 URL。
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{"
        @"%@;"
        @"var h='%@';"
        @"var want=h.length?('#'+h):'';"
        @"var changed=location.hash!==want;"
        @"if(changed){"
        @"history.replaceState(null,'',location.pathname+location.search+want);"
        @"try{window.dispatchEvent(new HashChangeEvent('hashchange'));}catch(e){"
        @"try{window.dispatchEvent(new Event('hashchange'));}catch(e2){}"
        @"}"
        @"}"
        @"__meoScrollToFragmentWhenReady(h);"
        @"return location.href;"
        @"}catch(e){return null;}})();",
        MeoScrollToFragmentJS(), escaped];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (!completion) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            completion(nil);
            return;
        }
        completion((NSString *)result);
    }];
}

+ (NSURL *)URLByNormalizingEmbeddedFragment:(NSURL *)url {
    if (url == nil) {
        return url;
    }
    if (url.fragment.length > 0) {
        return url;
    }
    NSString *absolute = url.absoluteString;
    NSRange encodedHash = [absolute rangeOfString:@"%23" options:NSCaseInsensitiveSearch];
    if (encodedHash.location == NSNotFound) {
        return url;
    }
    NSString *before = [absolute substringToIndex:encodedHash.location];
    NSString *after = [absolute substringFromIndex:NSMaxRange(encodedHash)];
    NSURL *base = [NSURL URLWithString:before];
    if (base == nil) {
        return url;
    }
    NSString *fragment = [after stringByRemovingPercentEncoding] ?: after;
    NSURLComponents *components = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
    components.fragment = fragment;
    return components.URL ?: url;
}

+ (BOOL)shouldStripFragmentForNetworkLoadOfURL:(NSURL *)url {
    url = [self URLByNormalizingEmbeddedFragment:url];
    if (url.fragment.length == 0) {
        return NO;
    }
    // HTTPS 走 CONNECT，未见此问题；仅 http: 绝对形式代理请求会把 # 编成 %23。
    return [url.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame;
}

+ (BOOL)URL:(NSURL *)url isSameDocumentAsURL:(NSURL *)otherURL {
    if (url == nil || otherURL == nil) {
        return NO;
    }
    // about:blank 尚未落到真实文档，不能当成同文档。
    NSString *otherAbs = otherURL.absoluteString.lowercaseString;
    if ([otherAbs isEqualToString:@"about:blank"] || [otherAbs hasPrefix:@"about:blank?"]) {
        return NO;
    }
    url = [self URLByNormalizingEmbeddedFragment:url];
    otherURL = [self URLByNormalizingEmbeddedFragment:otherURL];
    NSURLComponents *a = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSURLComponents *b = [NSURLComponents componentsWithURL:otherURL resolvingAgainstBaseURL:NO];
    if (a == nil || b == nil) {
        return NO;
    }
    a.fragment = nil;
    b.fragment = nil;
    [self meo_removeHashRestoreQueryItemFromComponents:a];
    [self meo_removeHashRestoreQueryItemFromComponents:b];
    NSString *as = a.URL.absoluteString;
    NSString *bs = b.URL.absoluteString;
    return as.length > 0 && [as isEqualToString:bs];
}

+ (void)meo_removeHashRestoreQueryItemFromComponents:(NSURLComponents *)components {
    NSArray<NSURLQueryItem *> *items = components.queryItems;
    if (items.count == 0) {
        return;
    }
    NSMutableArray<NSURLQueryItem *> *filtered = [NSMutableArray arrayWithCapacity:items.count];
    for (NSURLQueryItem *item in items) {
        if ([item.name isEqualToString:kMeoHashRestoreQueryItem]) {
            continue;
        }
        [filtered addObject:item];
    }
    components.queryItems = filtered.count > 0 ? filtered : nil;
}

+ (NSURL *)networkLoadURLByStrippingFragment:(NSURL *)url {
    url = [self URLByNormalizingEmbeddedFragment:url];
    NSString *fragment = url.fragment;
    if (fragment.length == 0) {
        return url;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components == nil) {
        return url;
    }
    components.fragment = nil;
    [self meo_removeHashRestoreQueryItemFromComponents:components];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    if (components.queryItems.count > 0) {
        [items addObjectsFromArray:components.queryItems];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:kMeoHashRestoreQueryItem value:fragment]];
    components.queryItems = items;
    return components.URL ?: url;
}

+ (NSURL *)publicURLFromInternalURL:(NSURL *)url {
    if (url == nil) {
        return nil;
    }
    url = [self URLByNormalizingEmbeddedFragment:url];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components == nil) {
        return url;
    }

    NSString *restoreFragment = nil;
    NSMutableArray<NSURLQueryItem *> *filtered = [NSMutableArray array];
    BOOL sawRestoreItem = NO;
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:kMeoHashRestoreQueryItem]) {
            restoreFragment = item.value;
            sawRestoreItem = YES;
            continue;
        }
        [filtered addObject:item];
    }
    if (!sawRestoreItem) {
        return url;
    }

    components.queryItems = filtered.count > 0 ? filtered : nil;
    if (components.fragment.length == 0 && restoreFragment.length > 0) {
        components.fragment = restoreFragment;
    }
    return components.URL ?: url;
}

- (nullable WKNavigation *)loadRequest:(NSURLRequest *)request {
    request = [BrowserWebView requestByApplyingNavigationTimeout:request];
    NSURL *url = request.URL;
    // 会话里若仍残留 __meo_hf，先还原成 #hash，再走统一剥离逻辑。
    NSURL *publicURL = [BrowserWebView publicURLFromInternalURL:url];
    if (publicURL != nil && ![publicURL.absoluteString isEqualToString:url.absoluteString]) {
        NSMutableURLRequest *normalized = [request mutableCopy];
        normalized.URL = publicURL;
        request = [BrowserWebView requestByApplyingNavigationTimeout:normalized];
        url = publicURL;
    }
    if (![BrowserWebView shouldStripFragmentForNetworkLoadOfURL:url]) {
        return [super loadRequest:request];
    }

    NSURL *stripped = [BrowserWebView networkLoadURLByStrippingFragment:url];
    if (stripped == nil || [stripped.absoluteString isEqualToString:url.absoluteString]) {
        return [super loadRequest:request];
    }

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.URL = stripped;
    return [super loadRequest:[BrowserWebView requestByApplyingNavigationTimeout:mutableRequest]];
}

- (nullable WKNavigation *)reload {
    // WKWebView.reload 会按当前 URL（含 #hash）发网，代理下易把 # 编成 %23 → 404。
    NSURL *publicURL = [BrowserWebView publicURLFromInternalURL:self.URL] ?: self.URL;
    if ([BrowserWebView shouldStripFragmentForNetworkLoadOfURL:publicURL]) {
        return [self loadRequest:[NSURLRequest requestWithURL:publicURL]];
    }
    return [super reload];
}

- (nullable WKNavigation *)reloadFromOrigin {
    NSURL *publicURL = [BrowserWebView publicURLFromInternalURL:self.URL] ?: self.URL;
    if ([BrowserWebView shouldStripFragmentForNetworkLoadOfURL:publicURL]) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:publicURL];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        return [self loadRequest:request];
    }
    return [super reloadFromOrigin];
}

- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super willOpenMenu:menu withEvent:event];

    self.contextMenuEvent = event;
    self.pendingContextMenuDownload = NO;
    self.pendingContextMenuOpenInNewWindow = NO;
    self.openResourceMenuItem = nil;
    self.openLinkInNewWindowMenuItem = nil;

    NSMenuItem *downloadItem = nil;
    NSMenuItem *openImageItem = nil;
    NSMenuItem *openMediaItem = nil;
    NSMenuItem *openLinkInNewWindowItem = nil;
    NSMenuItem *searchWebItem = nil;

    NSString *engineName = [BrowsingPreferences displayNameForSearchEngineID:[BrowsingPreferences defaultSearchEngineID]];
    NSString *searchTitle = [NSString stringWithFormat:@"使用「%@」搜索", engineName];

    for (NSMenuItem *item in menu.itemArray) {
        if ([self isSearchWebMenuItem:item]) {
            item.title = searchTitle;
            item.target = self;
            item.action = @selector(meo_searchSelectionWithDefaultEngine:);
            searchWebItem = item;
            continue;
        }

        NSString *identifier = item.identifier;
        if ([identifier isEqualToString:@"WKMenuItemIdentifierDownloadImage"] ||
            [identifier isEqualToString:@"WKMenuItemIdentifierDownloadMedia"]) {
            downloadItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenImageInNewWindow"]) {
            openImageItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenMediaInNewWindow"]) {
            openMediaItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenLinkInNewWindow"]) {
            openLinkInNewWindowItem = item;
        }
    }

    // WebKit 该项实际会走 createWebView → 本应用开新标签，标题改为与行为一致。
    if (openLinkInNewWindowItem) {
        openLinkInNewWindowItem.title = @"在新标签页中打开链接";
        self.openLinkInNewWindowMenuItem = openLinkInNewWindowItem;

        NSInteger index = [menu indexOfItem:openLinkInNewWindowItem];
        if (index != NSNotFound) {
            NSMenuItem *openInWindow = [[NSMenuItem alloc] initWithTitle:@"在新窗口中打开链接"
                                                                  action:@selector(meo_openLinkInNewWindow:)
                                                           keyEquivalent:@""];
            openInWindow.target = self;
            openInWindow.representedObject = openLinkInNewWindowItem;
            [menu insertItem:openInWindow atIndex:index + 1];
        }
    }

    // 选中文本含 http(s):// 时，提供「在新标签中打开」（已有链接菜单时不必重复）。
    if (!openLinkInNewWindowItem) {
        [self meo_insertOpenSelectionURLItemInMenu:menu nearItem:searchWebItem];
    }

    if (downloadItem) {
        // WebKit 系统「Download Image/Media」常不触发 WKDownload；改为劫持 Open*InNewWindow 取 URL。
        NSMenuItem *openItem = nil;
        if ([downloadItem.identifier isEqualToString:@"WKMenuItemIdentifierDownloadMedia"]) {
            openItem = openMediaItem ?: openImageItem;
        } else {
            openItem = openImageItem ?: openMediaItem;
        }
        self.openResourceMenuItem = openItem;
        downloadItem.target = self;
        downloadItem.action = @selector(meo_downloadContextResource:);
        downloadItem.representedObject = openItem;
    }
}

- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super didCloseMenu:menu withEvent:event];
    // createWebView 异步到达，稍后再清标记，避免误伤普通弹窗导航。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingContextMenuDownload = NO;
        strongSelf.pendingContextMenuOpenInNewWindow = NO;
        strongSelf.openResourceMenuItem = nil;
        strongSelf.openLinkInNewWindowMenuItem = nil;
        strongSelf.contextMenuEvent = nil;
    });
}

- (BOOL)isSearchWebMenuItem:(NSMenuItem *)item {
    NSString *identifier = item.identifier;
    if ([identifier isEqualToString:@"WKMenuItemIdentifierSearchWeb"]) {
        return YES;
    }

    NSString *title = item.title ?: @"";
    if (title.length == 0) {
        return NO;
    }

    NSString *lower = title.lowercaseString;
    // 英文：Search with Google / Search DuckDuckGo…
    if ([lower containsString:@"search with "] ||
        [lower hasPrefix:@"search google"] ||
        [lower hasPrefix:@"search duckduckgo"] ||
        [lower hasPrefix:@"search bing"] ||
        [lower hasPrefix:@"search yahoo"] ||
        [lower hasPrefix:@"search ecosia"] ||
        [lower hasPrefix:@"search baidu"]) {
        return YES;
    }

    // 中文：使用「Google」搜索 / 用 Google 搜索
    BOOL looksLikeChineseSearch = [title containsString:@"搜索"] &&
        ([title containsString:@"使用"] || [title hasPrefix:@"用"]);
    if (looksLikeChineseSearch) {
        return YES;
    }

    return NO;
}

- (void)meo_insertOpenSelectionURLItemInMenu:(NSMenu *)menu nearItem:(NSMenuItem *)nearItem {
    NSMenuItem *openSelectionURLItem = [[NSMenuItem alloc] initWithTitle:@"在新标签中打开"
                                                                  action:@selector(meo_openSelectionURLInNewTab:)
                                                           keyEquivalent:@""];
    openSelectionURLItem.target = self;
    openSelectionURLItem.hidden = YES;

    if (nearItem) {
        NSInteger index = [menu indexOfItem:nearItem];
        if (index != NSNotFound) {
            [menu insertItem:openSelectionURLItem atIndex:index];
        } else {
            [menu insertItem:openSelectionURLItem atIndex:0];
        }
    } else {
        [menu insertItem:openSelectionURLItem atIndex:0];
    }

    __weak typeof(self) weakSelf = self;
    __weak NSMenu *weakMenu = menu;
    __weak NSMenuItem *weakItem = openSelectionURLItem;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        NSMenu *strongMenu = weakMenu;
        NSMenuItem *strongItem = weakItem;
        if (!strongSelf || !strongMenu || !strongItem) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            if ([strongMenu.itemArray containsObject:strongItem]) {
                [strongMenu removeItem:strongItem];
            }
            return;
        }

        NSString *urlString = [strongSelf meo_HTTPURLStringFromSelectedText:(NSString *)result];
        if (urlString.length == 0) {
            if ([strongMenu.itemArray containsObject:strongItem]) {
                [strongMenu removeItem:strongItem];
            }
            return;
        }

        strongItem.representedObject = urlString;
        strongItem.hidden = NO;
    }];
}

- (nullable NSString *)meo_HTTPURLStringFromSelectedText:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSRange httpsRange = [trimmed rangeOfString:@"https://" options:NSCaseInsensitiveSearch];
    NSRange httpRange = [trimmed rangeOfString:@"http://" options:NSCaseInsensitiveSearch];

    NSUInteger start = NSNotFound;
    if (httpsRange.location != NSNotFound && httpRange.location != NSNotFound) {
        start = MIN(httpsRange.location, httpRange.location);
    } else if (httpsRange.location != NSNotFound) {
        start = httpsRange.location;
    } else if (httpRange.location != NSNotFound) {
        start = httpRange.location;
    }
    if (start == NSNotFound) {
        return nil;
    }

    NSString *fromURL = [trimmed substringFromIndex:start];
    NSRange whitespace = [fromURL rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (whitespace.location != NSNotFound) {
        fromURL = [fromURL substringToIndex:whitespace.location];
    }

    static NSCharacterSet *trailingPunctuation;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trailingPunctuation = [NSCharacterSet characterSetWithCharactersInString:@". ,;:)]}\"'" ];
    });
    while (fromURL.length > 0) {
        unichar last = [fromURL characterAtIndex:fromURL.length - 1];
        if (![trailingPunctuation characterIsMember:last]) {
            break;
        }
        fromURL = [fromURL substringToIndex:fromURL.length - 1];
    }

    NSURL *url = [NSURL URLWithString:fromURL];
    if (!url.scheme.length || !url.host.length) {
        return nil;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }

    return fromURL;
}

- (void)meo_openSelectionURLInNewTab:(id)sender {
    NSString *urlString = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        id represented = [(NSMenuItem *)sender representedObject];
        if ([represented isKindOfClass:[NSString class]]) {
            urlString = (NSString *)represented;
        }
    }

    __weak typeof(self) weakSelf = self;
    void (^openURL)(NSString *) = ^(NSString *candidate) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || candidate.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:candidate];
        if (!url) {
            return;
        }
        if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        } else {
            [strongSelf loadRequest:[NSURLRequest requestWithURL:url]];
        }
    };

    if (urlString.length > 0) {
        openURL(urlString);
        return;
    }

    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *extracted = [strongSelf meo_HTTPURLStringFromSelectedText:(NSString *)result];
        openURL(extracted);
    }];
}

- (void)meo_searchSelectionWithDefaultEngine:(id)sender {
#pragma unused(sender)
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSURL *url = [BrowsingPreferences searchURLForQuery:(NSString *)result];
        if (!url) {
            return;
        }
        if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        } else {
            [strongSelf loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }];
}

- (void)meo_openLinkInNewWindow:(id)sender {
    NSMenuItem *openItem = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        openItem = [(NSMenuItem *)sender representedObject];
    }
    if (![openItem isKindOfClass:[NSMenuItem class]]) {
        openItem = self.openLinkInNewWindowMenuItem;
    }

    if (openItem.action && openItem.target) {
        self.pendingContextMenuOpenInNewWindow = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [openItem.target performSelector:openItem.action withObject:openItem];
#pragma clang diagnostic pop
        return;
    }

    [self meo_openLinkAtContextMenuPointInNewWindow];
}

- (void)meo_openLinkAtContextMenuPointInNewWindow {
    NSEvent *event = self.contextMenuEvent;
    if (!event) {
        return;
    }

    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = locationInView.x;
    CGFloat y = NSHeight(self.bounds) - locationInView.y;

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  function absUrl(u) {"
         "    try { return new URL(u, document.baseURI).href; } catch (e) { return u; }"
         "  }"
         "  var el = document.elementFromPoint(x, y);"
         "  while (el) {"
         "    if (el.tagName === 'A' && el.href) { return absUrl(el.href); }"
         "    el = el.parentElement;"
         "  }"
         "  return null;"
         "})(%f, %f)", x, y];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *urlString = (NSString *)result;
        if (urlString.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            return;
        }
        if (strongSelf.openURLInNewWindowHandler) {
            strongSelf.openURLInNewWindowHandler(url);
        } else if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        }
    }];
}

- (void)meo_downloadContextResource:(id)sender {
    NSMenuItem *openItem = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        openItem = [(NSMenuItem *)sender representedObject];
    }
    if (![openItem isKindOfClass:[NSMenuItem class]]) {
        openItem = self.openResourceMenuItem;
    }

    if (openItem.action && openItem.target) {
        self.pendingContextMenuDownload = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [openItem.target performSelector:openItem.action withObject:openItem];
#pragma clang diagnostic pop
        return;
    }

    // 找不到 Open Image/Media 时，用点击坐标兜底解析图片 URL。
    [self meo_downloadResourceAtContextMenuPoint];
}

- (void)meo_downloadResourceAtContextMenuPoint {
    NSEvent *event = self.contextMenuEvent;
    if (!event) {
        return;
    }

    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = locationInView.x;
    // AppKit 原点在左下；elementFromPoint 使用视口左上原点。
    CGFloat y = NSHeight(self.bounds) - locationInView.y;

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  function absUrl(u) {"
         "    try { return new URL(u, document.baseURI).href; } catch (e) { return u; }"
         "  }"
         "  var el = document.elementFromPoint(x, y);"
         "  if (!el) { return null; }"
         "  var n = el;"
         "  while (n) {"
         "    if (n.tagName === 'IMG') {"
         "      return absUrl(n.currentSrc || n.src);"
         "    }"
         "    if (n.tagName === 'VIDEO' || n.tagName === 'AUDIO' || n.tagName === 'SOURCE') {"
         "      var src = n.currentSrc || n.src;"
         "      if (src) { return absUrl(src); }"
         "    }"
         "    if (n.tagName === 'PICTURE') {"
         "      var img = n.querySelector('img');"
         "      if (img) { return absUrl(img.currentSrc || img.src); }"
         "    }"
         "    n = n.parentElement;"
         "  }"
         "  n = el;"
         "  while (n && n !== document.documentElement) {"
         "    var bg = getComputedStyle(n).backgroundImage;"
         "    var m = bg && bg.match(/url\\([\"']?([^\"')]+)[\"']?\\)/);"
         "    if (m && m[1] && m[1] !== 'none') { return absUrl(m[1]); }"
         "    n = n.parentElement;"
         "  }"
         "  return null;"
         "})(%f, %f)", x, y];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *urlString = (NSString *)result;
        if (urlString.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            return;
        }
        [strongSelf meo_deliverDownloadURL:url];
    }];
}

- (nullable NSURL *)consumePendingContextMenuDownloadURL:(NSURL *)candidateURL {
    if (!self.pendingContextMenuDownload) {
        return nil;
    }
    self.pendingContextMenuDownload = NO;
    self.openResourceMenuItem = nil;
    if (!candidateURL) {
        return nil;
    }
    return candidateURL;
}

- (nullable NSURL *)consumePendingContextMenuOpenInNewWindowURL:(NSURL *)candidateURL {
    if (!self.pendingContextMenuOpenInNewWindow) {
        return nil;
    }
    self.pendingContextMenuOpenInNewWindow = NO;
    self.openLinkInNewWindowMenuItem = nil;
    if (!candidateURL) {
        return nil;
    }
    return candidateURL;
}

- (void)meo_deliverDownloadURL:(NSURL *)url {
    if (!url) {
        return;
    }
    if (self.downloadURLHandler) {
        self.downloadURLHandler(url);
    } else if (@available(macOS 11.3, *)) {
        [self startDownloadUsingRequest:[NSURLRequest requestWithURL:url]
                      completionHandler:^(__unused WKDownload *download) {
        }];
    }
}

@end
