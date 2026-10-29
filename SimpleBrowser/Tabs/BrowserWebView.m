#import "BrowserWebView.h"
#import "BrowsingPreferences.h"
#import "MeoContextMenuLocalizer.h"
#import "BrowserWindowController.h"
#import "BrowserAIAssistantPrompts.h"

#import <objc/message.h>

// 查询参数名：document-start 脚本据此在页面脚本运行前写回 location.hash。
static NSString * const kMeoHashRestoreQueryItem = @"__meo_hf";

@interface BrowserWebView ()
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuDownload;
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuOpenInNewWindow;
@property (nonatomic, weak) NSMenuItem *openResourceMenuItem;
@property (nonatomic, weak) NSMenuItem *openLinkInNewWindowMenuItem;
@property (nonatomic, strong, nullable) NSEvent *contextMenuEvent;
/// rightMouseDown 时记下的 DOM 坐标（比 willOpenMenu 的 event 更可靠）
@property (nonatomic, assign) NSPoint contextMenuDOMPoint;
@property (nonatomic, assign) BOOL contextMenuDOMPointValid;
/// WebKit 菜单含「下载/打开图像」→ 本次右键必是图片（不依赖 elementFromPoint）
@property (nonatomic, assign) BOOL contextMenuIsImageHit;
/// 右键弹出瞬间缓存的选区（点子菜单后 selection 常被清空）
@property (nonatomic, copy, nullable) NSString *contextMenuSelectedText;
/// 划词过程中持续刷新；willOpenMenu 不得清空，否则 rightMouseDown 的缓存会丢
@property (nonatomic, copy, nullable) NSString *meoStickySelectedText;
/// 右键弹出瞬间解析的引用 payload（选区 / 图片 / 链接 / 页面）
@property (nonatomic, copy, nullable) NSDictionary *contextMenuCitePayload;
@property (nonatomic, assign) BOOL contextMenuCiteDelivered;
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

+ (void)installCaretFallbackScriptOnContentController:(WKUserContentController *)controller {
    if (controller == nil) {
        return;
    }
    // AppKit 已让 WKWebView 成为 firstResponder，但未对 WebContent 发 SetFocused 时，
    // document.hasFocus() 为 false，原生 caret 不画。用轻量软件光标补视觉，避免 sync IPC。
    NSString *js =
        @"(function(){"
         "if(window.__meoCaretFallback)return;"
         "window.__meoCaretFallback=1;"
         "var caret=null,raf=0,target=null;"
         "function ensure(){"
         "if(caret&&caret.isConnected)return caret;"
         "caret=document.createElement('div');"
         "caret.id='__meo_caret';"
         "caret.setAttribute('aria-hidden','true');"
         "caret.style.cssText='position:absolute;width:1.5px;pointer-events:none;z-index:2147483647;"
         "background:Highlight;animation:__meoCaretBlink 1s step-end infinite;display:none;';"
         "if(!document.getElementById('__meoCaretStyle')){"
         "var s=document.createElement('style');s.id='__meoCaretStyle';"
         "s.textContent='@keyframes __meoCaretBlink{50%{opacity:0}}';"
         "(document.documentElement||document.head).appendChild(s);"
         "}"
         "(document.documentElement||document.body).appendChild(caret);"
         "return caret;"
         "}"
         "function hide(){if(caret)caret.style.display='none';target=null;}"
         "function isEditable(el){"
         "if(!el||el.nodeType!==1)return false;"
         "var t=el.tagName;"
         "if(t==='TEXTAREA')return !el.disabled&&!el.readOnly;"
         "if(t==='INPUT'){"
         "var ty=(el.type||'text').toLowerCase();"
         "if(el.disabled||el.readOnly)return false;"
         "return 'text search tel url email password number'.split(' ').indexOf(ty)>=0;"
         "}"
         "return !!el.isContentEditable;"
         "}"
         "function mirrorCaretRect(el){"
         "try{"
         "var cs=getComputedStyle(el);"
         "var mir=document.createElement('div');"
         "var props=['direction','boxSizing','width','height','overflowX','overflowY',"
         "'borderTopWidth','borderRightWidth','borderBottomWidth','borderLeftWidth','borderStyle',"
         "'paddingTop','paddingRight','paddingBottom','paddingLeft',"
         "'fontStyle','fontVariant','fontWeight','fontStretch','fontSize','fontSizeAdjust',"
         "'lineHeight','fontFamily','textAlign','textTransform','textIndent',"
         "'letterSpacing','wordSpacing','whiteSpace','wordBreak','overflowWrap'];"
         "for(var i=0;i<props.length;i++)mir.style[props[i]]=cs[props[i]];"
         "mir.style.position='absolute';"
         "mir.style.visibility='hidden';"
         "mir.style.whiteSpace=(el.tagName==='INPUT')?'pre':cs.whiteSpace;"
         "mir.style.overflow='hidden';"
         "mir.style.top='0';mir.style.left='-9999px';"
         "var v=el.value||'';"
         "var pos=typeof el.selectionStart==='number'?el.selectionStart:v.length;"
         "mir.textContent=v.substring(0,pos);"
         "var mark=document.createElement('span');"
         "mark.textContent=v.substring(pos)||'.';"
         "mir.appendChild(mark);"
         "document.body.appendChild(mir);"
         "var er=el.getBoundingClientRect();"
         "var mr=mark.getBoundingClientRect();"
         "var br=mir.getBoundingClientRect();"
         "var x=er.left+(mr.left-br.left)-el.scrollLeft;"
         "var y=er.top+(mr.top-br.top)-el.scrollTop;"
         "var h=mr.height||parseFloat(cs.lineHeight)||er.height;"
         "mir.remove();"
         "return {x:x+window.scrollX,y:y+window.scrollY,h:h,color:cs.color};"
         "}catch(e){return null;}"
         "}"
         "function contentCaretRect(el){"
         "try{"
         "var sel=window.getSelection();"
         "if(!sel||!sel.rangeCount)return null;"
         "var r=sel.getRangeAt(0);"
         "if(!el.contains(r.commonAncestorContainer))return null;"
         "var rects=r.getClientRects();"
         "var rc=rects.length?rects[rects.length-1]:r.getBoundingClientRect();"
         "if(!rc||(!rc.width&&!rc.height&&!r.collapsed))return null;"
         "var cs=getComputedStyle(el);"
         "var h=rc.height||parseFloat(cs.lineHeight)||16;"
         "return {x:rc.left+window.scrollX,y:rc.top+window.scrollY,h:h,color:cs.color};"
         "}catch(e){return null;}"
         "}"
         "function place(){"
         "raf=0;"
         "if(document.hasFocus()){hide();return;}"
         "var el=document.activeElement;"
         "if(!isEditable(el)){hide();return;}"
         "target=el;"
         "var info=(el.tagName==='INPUT'||el.tagName==='TEXTAREA')?mirrorCaretRect(el):contentCaretRect(el);"
         "if(!info){hide();return;}"
         "var c=ensure();"
         "c.style.display='block';"
         "c.style.left=info.x+'px';"
         "c.style.top=info.y+'px';"
         "c.style.height=info.h+'px';"
         "c.style.background=info.color||'Highlight';"
         "}"
         "function schedule(){if(!raf)raf=requestAnimationFrame(place);}"
         "document.addEventListener('focusin',schedule,true);"
         "document.addEventListener('focusout',function(){setTimeout(schedule,0);},true);"
         "document.addEventListener('selectionchange',schedule,true);"
         "document.addEventListener('input',schedule,true);"
         "document.addEventListener('keyup',schedule,true);"
         "document.addEventListener('click',schedule,true);"
         "window.addEventListener('scroll',schedule,true);"
         "window.addEventListener('resize',schedule,true);"
         "})();";
    [controller addUserScript:[[WKUserScript alloc] initWithSource:js
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:NO]];
}

+ (NSString *)meo_selectionCacheInstallJavaScript {
    return
        @"(function(){"
         "if(window.__meoSelectionCacheInstalled)return 'ok';"
         "window.__meoSelectionCacheInstalled=1;"
         "window.__meoLastSelection=window.__meoLastSelection||'';"
         "function readSelection(){"
         "  try{"
         "    var ae=document.activeElement;"
         "    if(ae&&(ae.tagName==='TEXTAREA'||ae.tagName==='INPUT')&&typeof ae.selectionStart==='number'){"
         "      var a=ae.selectionStart,b=ae.selectionEnd;"
         "      if(typeof a==='number'&&typeof b==='number'&&b>a){"
         "        return String(ae.value||'').substring(a,b);"
         "      }"
         "    }"
         "    var sel=window.getSelection&&window.getSelection();"
         "    if(sel){var t=String(sel.toString()||''); if(t) return t;}"
         "  }catch(e){}"
         "  return '';"
         "}"
         "function cacheSelection(){"
         "  var t=readSelection();"
         "  if(t&&t.trim()){ window.__meoLastSelection=t; }"
         "}"
         "document.addEventListener('selectionchange',cacheSelection,true);"
         "document.addEventListener('mouseup',cacheSelection,true);"
         "document.addEventListener('keyup',cacheSelection,true);"
         "document.addEventListener('pointerup',cacheSelection,true);"
         // 右键按下瞬间：一定再抓一次（比原生 willOpenMenu 更早）
         "document.addEventListener('contextmenu',function(){ cacheSelection(); },true);"
         "window.__meoGetCachedSelection=function(){"
         "  var live=readSelection();"
         "  if(live&&live.trim()) return live;"
         "  return window.__meoLastSelection||'';"
         "};"
         "cacheSelection();"
         "return 'ok';"
         "})();";
}

+ (void)installSelectionCacheScriptOnContentController:(WKUserContentController *)controller {
    if (controller == nil) {
        return;
    }
    // 原生右键菜单弹出前，WebKit 常会清掉 selection；必须在页面 contextmenu 捕获阶段先存起来。
    [controller addUserScript:[[WKUserScript alloc] initWithSource:[self meo_selectionCacheInstallJavaScript]
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:NO]];
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

+ (BOOL)URLContainsHashRestoreQuery:(NSURL *)url {
    if (url == nil) {
        return NO;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:kMeoHashRestoreQueryItem]) {
            return YES;
        }
    }
    return NO;
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
    id controller = self.window.windowController;
    if ([controller isKindOfClass:[BrowserWindowController class]] &&
        [(BrowserWindowController *)controller shouldSuppressContextMenuForTransparentRightDrag]) {
        [menu cancelTracking];
        while (menu.numberOfItems > 0) {
            [menu removeItemAtIndex:0];
        }
        return;
    }

    [super willOpenMenu:menu withEvent:event];

    self.contextMenuEvent = event;
    if (!self.contextMenuDOMPointValid) {
        self.contextMenuDOMPoint = [self meo_domPointFromEvent:event];
        self.contextMenuDOMPointValid = (self.contextMenuDOMPoint.x >= 0);
    }
    self.pendingContextMenuDownload = NO;
    self.pendingContextMenuOpenInNewWindow = NO;
    self.openResourceMenuItem = nil;
    self.openLinkInNewWindowMenuItem = nil;
    self.contextMenuIsImageHit = NO;
    // 保留 rightMouseDown / sticky 划词，勿先清空再读（菜单弹出时 page selection 常已空）
    NSString *preservedSel = [self.contextMenuSelectedText copy];
    if (preservedSel.length == 0) {
        preservedSel = [self.meoStickySelectedText copy];
    }
    NSDictionary *preservedPayload = [self.contextMenuCitePayload copy];
    self.contextMenuCiteDelivered = NO;

    // Accessibility 往往在 JS selection 被清掉后仍能读到高亮文本
    NSString *axText = [self meo_accessibilitySelectedTextDeep];
    if (axText.length > 0) {
        [self meo_rememberSelectedText:axText];
        self.contextMenuCitePayload = @{ @"kind": @"text", @"text": axText };
    } else if (preservedSel.length > 0) {
        self.contextMenuSelectedText = preservedSel;
        self.meoStickySelectedText = preservedSel;
        if ([preservedPayload isKindOfClass:[NSDictionary class]]) {
            self.contextMenuCitePayload = preservedPayload;
        } else {
            self.contextMenuCitePayload = @{ @"kind": @"text", @"text": preservedSel };
        }
    } else {
        self.contextMenuSelectedText = nil;
        self.contextMenuCitePayload = nil;
    }

    // 立刻抓选区与命中元素，避免进入「问问 AI」子菜单后 selection 丢失
    [self meo_ensureSelectionCacheInstalled];
    [self meo_captureContextMenuAIContext];

    NSMenuItem *downloadItem = nil;
    NSMenuItem *openImageItem = nil;
    NSMenuItem *openMediaItem = nil;
    NSMenuItem *openLinkInNewWindowItem = nil;
    NSMenuItem *searchWebItem = nil;
    NSMenuItem *copySelectionItem = nil;
    BOOL hasLinkMenu = NO;

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
            if ([identifier isEqualToString:@"WKMenuItemIdentifierDownloadImage"]) {
                self.contextMenuIsImageHit = YES;
            }
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenImageInNewWindow"]) {
            openImageItem = item;
            self.contextMenuIsImageHit = YES;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierCopyImage"]) {
            self.contextMenuIsImageHit = YES;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenMediaInNewWindow"]) {
            openMediaItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenLinkInNewWindow"]) {
            openLinkInNewWindowItem = item;
            hasLinkMenu = YES;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenLink"] ||
                   [identifier isEqualToString:@"WKMenuItemIdentifierCopyLink"] ||
                   [identifier isEqualToString:@"WKMenuItemIdentifierDownloadLinkedFile"]) {
            hasLinkMenu = YES;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierCopy"]) {
            copySelectionItem = item;
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

    // 链接菜单通常不含选区项；有选区时合并「搜索 / 拷贝」。
    if (hasLinkMenu) {
        [self meo_augmentLinkMenuWithSelectionItems:menu
                                        searchTitle:searchTitle
                                  existingSearchItem:searchWebItem
                                    existingCopyItem:copySelectionItem];
    }

    // 选中文本含 http(s):// 时，提供「在新标签中打开」（已有链接菜单时不必重复）。
    if (!openLinkInNewWindowItem) {
        [self meo_insertOpenSelectionURLItemInMenu:menu nearItem:searchWebItem];
    }

    // 「问问 AI」：有选区针对选区；无选区用当前页 URL/标题作上下文。
    [self meo_insertAIAssistantMenuInMenu:menu nearItem:searchWebItem ?: copySelectionItem];

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

    [menu addItem:[NSMenuItem separatorItem]];

    // 在 iframe 内点击时，提供「重新载入框架」：仅刷新此 iframe，不影响主页面。
    NSMenuItem *reloadFrame = [[NSMenuItem alloc] initWithTitle:@"重新载入框架"
                                                         action:@selector(meo_reloadFrame:)
                                                  keyEquivalent:@""];
    reloadFrame.target = self;
    reloadFrame.hidden = YES;
    [menu addItem:reloadFrame];

    NSMenuItem *viewSource = [[NSMenuItem alloc] initWithTitle:@"查看网页源代码"
                                                        action:@selector(meo_viewPageSource:)
                                                 keyEquivalent:@""];
    viewSource.target = self;
    [menu addItem:viewSource];

    // 分栏 pane 内:追加本栏缩放(直接以 WindowController 为 target,用 representedObject 传 webView;
    // target=nil 走 responder 链在 WKWebView 右键菜单里到不了 WindowController,会导致菜单灰掉/点击无反应)
    id wc = self.window.windowController;
    if ([wc isKindOfClass:[BrowserWindowController class]] && [(BrowserWindowController *)wc isSplitActive]) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSArray *zoomDefs = @[
            @[@"放大本栏", @"splitZoomInPane:"],
            @[@"缩小本栏", @"splitZoomOutPane:"],
            @[@"本栏实际大小", @"splitZoomResetPane:"],
        ];
        for (NSArray *def in zoomDefs) {
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:def[0] action:NSSelectorFromString(def[1]) keyEquivalent:@""];
            it.target = wc;
            it.representedObject = self;
            [menu addItem:it];
        }
    }

    [MeoContextMenuLocalizer localizeMenu:menu];

    // 异步检查右键点是否在 iframe 内，若在则显示「重新载入框架」。
    [self meo_probeContextMenuForFrameHitAndShowReloadItem:reloadFrame];
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
        strongSelf.contextMenuDOMPointValid = NO;
        strongSelf.contextMenuIsImageHit = NO;
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

/// 链接菜单 + 非空选区：在菜单顶部补齐选区「搜索 / 拷贝」（与链接项并存）。
- (void)meo_augmentLinkMenuWithSelectionItems:(NSMenu *)menu
                                  searchTitle:(NSString *)searchTitle
                            existingSearchItem:(nullable NSMenuItem *)existingSearchItem
                              existingCopyItem:(nullable NSMenuItem *)existingCopyItem {
    if (!menu) {
        return;
    }

    NSMutableArray<NSMenuItem *> *insertedItems = [NSMutableArray array];
    NSInteger insertIndex = 0;

    if (!existingSearchItem) {
        NSMenuItem *searchItem = [[NSMenuItem alloc] initWithTitle:searchTitle ?: @"搜索"
                                                            action:@selector(meo_searchSelectionWithDefaultEngine:)
                                                     keyEquivalent:@""];
        searchItem.target = self;
        searchItem.hidden = YES;
        [menu insertItem:searchItem atIndex:insertIndex++];
        [insertedItems addObject:searchItem];
    }

    if (!existingCopyItem) {
        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"拷贝"
                                                          action:@selector(meo_copySelection:)
                                                   keyEquivalent:@""];
        copyItem.target = self;
        copyItem.hidden = YES;
        [menu insertItem:copyItem atIndex:insertIndex++];
        [insertedItems addObject:copyItem];
    }

    if (insertedItems.count == 0) {
        return;
    }

    NSMenuItem *separator = [NSMenuItem separatorItem];
    separator.hidden = YES;
    [menu insertItem:separator atIndex:insertIndex];
    [insertedItems addObject:separator];

    __weak typeof(self) weakSelf = self;
    __weak NSMenu *weakMenu = menu;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        NSMenu *strongMenu = weakMenu;
        if (!strongSelf || !strongMenu) {
            return;
        }

        BOOL hasSelection = NO;
        if (!error && [result isKindOfClass:[NSString class]]) {
            NSString *trimmed = [(NSString *)result stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            hasSelection = trimmed.length > 0;
        }

        for (NSMenuItem *item in insertedItems) {
            if (![strongMenu.itemArray containsObject:item]) {
                continue;
            }
            if (hasSelection) {
                item.hidden = NO;
            } else {
                [strongMenu removeItem:item];
            }
        }
    }];
}

- (void)meo_copySelection:(id)sender {
#pragma unused(sender)
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *text = (NSString *)result;
        if (text.length == 0) {
            return;
        }
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:text forType:NSPasteboardTypeString];
    }];
}

- (void)meo_insertAIAssistantMenuInMenu:(NSMenu *)menu nearItem:(nullable NSMenuItem *)nearItem {
    if (!menu) {
        return;
    }
    // 菜单名：「问问 AI」——有选区针对选区，无选区针对当前页。
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"问问 AI"];
    NSMenuItem *sumPage = [[NSMenuItem alloc] initWithTitle:@"总结该网页"
                                                     action:@selector(meo_aiAssistantSummarizePage:)
                                              keyEquivalent:@""];
    sumPage.target = self;
    sumPage.toolTip = @"采集当前页正文并总结（忽略选区）";
    [submenu addItem:sumPage];
    NSMenuItem *askPage = [[NSMenuItem alloc] initWithTitle:@"问答本页…"
                                                     action:@selector(meo_aiAssistantAskPage:)
                                              keyEquivalent:@""];
    askPage.target = self;
    askPage.toolTip = @"采集正文并打开助手，自行补充问题后发送";
    [submenu addItem:askPage];
    [submenu addItem:[NSMenuItem separatorItem]];
    NSArray<NSDictionary *> *actions = @[
        @{@"title": @"直接问问", @"key": BrowserAIAssistantActionAsk},
        @{@"title": @"解释", @"key": BrowserAIAssistantActionExplain},
        @{@"title": @"总结", @"key": BrowserAIAssistantActionSummarize},
        @{@"title": @"翻译 / 说明", @"key": BrowserAIAssistantActionTranslate},
    ];
    for (NSDictionary *a in actions) {
        NSMenuItem *child = [[NSMenuItem alloc] initWithTitle:a[@"title"]
                                                       action:@selector(meo_aiAssistantAction:)
                                                keyEquivalent:@""];
        child.target = self;
        child.representedObject = a[@"key"];
        [submenu addItem:child];
    }
    [submenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *cite = [[NSMenuItem alloc] initWithTitle:@"加入引用"
                                                  action:@selector(meo_aiAssistantAddCitation:)
                                           keyEquivalent:@""];
    cite.target = self;
    cite.toolTip = @"加入 AI 助手对话框作为上下文，不直接发送";
    [submenu addItem:cite];

    NSMenuItem *aiItem = [[NSMenuItem alloc] initWithTitle:@"问问 AI" action:nil keyEquivalent:@""];
    aiItem.submenu = submenu;

    NSInteger insertIndex = 0;
    if (nearItem) {
        NSInteger idx = [menu indexOfItem:nearItem];
        if (idx != NSNotFound) {
            insertIndex = idx;
        }
    }
    [menu insertItem:aiItem atIndex:insertIndex];
}

- (nullable NSString *)meo_pageContextString {
    NSURL *url = [BrowserWebView publicURLFromInternalURL:self.URL] ?: self.URL;
    NSString *urlStr = url.absoluteString ?: @"";
    NSString *title = self.title ?: @"";
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (title.length > 0 && urlStr.length > 0) {
        return [NSString stringWithFormat:@"标题：%@\n地址：%@", title, urlStr];
    }
    if (urlStr.length > 0) {
        return [NSString stringWithFormat:@"地址：%@", urlStr];
    }
    if (title.length > 0) {
        return [NSString stringWithFormat:@"标题：%@", title];
    }
    return nil;
}

/// 右键事件 → 页面 DOM 坐标（与 elementFromPoint / getBoundingClientRect 一致）。
/// WKWebView.isFlipped=YES，convert 后已是左上原点，不可再 height-y。
- (NSPoint)meo_domPointFromEvent:(nullable NSEvent *)event {
    if (!event) {
        return NSMakePoint(-1, -1);
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.isFlipped) {
        p.y = NSHeight(self.bounds) - p.y;
    }
    return p;
}

/// 把任意字符串安全编成 JS 字符串字面量。不使用 NSJSONSerialization（其对非 Array/Dict 顶层会直接抛异常崩溃）。
+ (NSString *)meo_jsStringLiteral:(nullable id)value {
    NSString *s = @"";
    if ([value isKindOfClass:[NSString class]]) {
        s = (NSString *)value;
    } else if (value != nil && value != [NSNull null]) {
        s = [value description] ?: @"";
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length + 2];
    [out appendString:@"\""];
    NSUInteger len = s.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '\\': [out appendString:@"\\\\"]; break;
            case '"':  [out appendString:@"\\\""]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            case '\b': [out appendString:@"\\b"]; break;
            case '\f': [out appendString:@"\\f"]; break;
            default:
                if (c < 0x20) {
                    [out appendFormat:@"\\u%04x", (unsigned)c];
                } else {
                    [out appendFormat:@"%C", c];
                }
                break;
        }
    }
    [out appendString:@"\""];
    return out;
}

- (NSString *)meo_contextMenuCiteScriptAtX:(CGFloat)x y:(CGFloat)y forceImage:(BOOL)forceImage {
    // 选区缓存安装复用 meo_selectionCacheInstallJavaScript，避免两套逻辑漂移
    return [NSString stringWithFormat:
        @"%@;(function(x, y, forceImage) {"
         "  function absUrl(u) {"
         "    try { return new URL(u, document.baseURI).href; } catch (e) { return u || ''; }"
         "  }"
         "  function readSel() {"
         "    try {"
         "      if (typeof window.__meoGetCachedSelection === 'function') {"
         "        var c = window.__meoGetCachedSelection();"
         "        if (c && String(c).trim()) return String(c);"
         "      }"
         "      if (window.__meoLastSelection && String(window.__meoLastSelection).trim()) {"
         "        return String(window.__meoLastSelection);"
         "      }"
         "      var ae = document.activeElement;"
         "      if (ae && (ae.tagName === 'TEXTAREA' || ae.tagName === 'INPUT') && typeof ae.selectionStart === 'number') {"
         "        var a = ae.selectionStart, b = ae.selectionEnd;"
         "        if (b > a) return String(ae.value || '').substring(a, b);"
         "      }"
         "      var sel = window.getSelection && window.getSelection();"
         "      if (sel) return String(sel.toString() || '');"
         "    } catch (e) {}"
         "    return '';"
         "  }"
         "  function thumbFromImg(img) {"
         "    try {"
         "      var w = img.naturalWidth || 0, h = img.naturalHeight || 0;"
         "      if (!w || !h) return '';"
         "      var max = 128, s = Math.min(1, max / Math.max(w, h));"
         "      var c = document.createElement('canvas');"
         "      c.width = Math.max(1, Math.round(w * s));"
         "      c.height = Math.max(1, Math.round(h * s));"
         "      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);"
         "      return c.toDataURL('image/jpeg', 0.72);"
         "    } catch (e) { return ''; }"
         "  }"
         "  function imgUrl(img) {"
         "    if (!img) return '';"
         "    return absUrl(img.currentSrc || img.getAttribute('data-src') || img.src || '');"
         "  }"
         "  function imagePayload(img) {"
         "    var iu = imgUrl(img);"
         "    if (!iu) return null;"
         "    return { kind: 'image', url: iu, title: ((img.alt || img.getAttribute('title') || '').trim()),"
         "             pageURL: absUrl(location.href), pageTitle: (document.title || '').trim(),"
         "             thumb: thumbFromImg(img) };"
         "  }"
         "  function findImgInNode(n) {"
         "    while (n) {"
         "      if (n.tagName === 'IMG') return n;"
         "      if (n.tagName === 'PICTURE') {"
         "        var img = n.querySelector && n.querySelector('img');"
         "        if (img) return img;"
         "      }"
         "      if (n.tagName === 'IMAGE' || (n.namespaceURI === 'http://www.w3.org/2000/svg' && String(n.tagName).toLowerCase() === 'image')) {"
         "        return n;"
         "      }"
         "      n = n.parentElement;"
         "    }"
         "    return null;"
         "  }"
         // 1) elementsFromPoint：穿透透明遮罩
         "  var stack = [];"
         "  try { stack = document.elementsFromPoint(x, y) || []; } catch (e) {"
         "    try { var one = document.elementFromPoint(x, y); if (one) stack = [one]; } catch (e2) {}"
         "  }"
         "  for (var si = 0; si < stack.length; si++) {"
         "    var hitImg = findImgInNode(stack[si]);"
         "    if (hitImg && hitImg.tagName === 'IMG') {"
         "      var p1 = imagePayload(hitImg); if (p1) return p1;"
         "    }"
         "  }"
         // 2) 几何命中：点落在哪张图的矩形内（坐标稍偏也能找到）
         "  try {"
         "    var list = document.images || [];"
         "    var best = null, bestArea = 1e15;"
         "    for (var i = 0; i < list.length; i++) {"
         "      var im = list[i];"
         "      var r = im.getBoundingClientRect();"
         "      if (r.width < 2 || r.height < 2) continue;"
         "      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {"
         "        var area = r.width * r.height;"
         "        if (area < bestArea) { bestArea = area; best = im; }"
         "      }"
         "    }"
         "    if (best) { var p2 = imagePayload(best); if (p2) return p2; }"
         "  } catch (e) {}"
         // 3) 背景图
         "  for (var bi = 0; bi < stack.length; bi++) {"
         "    var bn = stack[bi];"
         "    while (bn && bn !== document.documentElement) {"
         "      var bg = '';"
         "      try { bg = getComputedStyle(bn).backgroundImage || ''; } catch (e) {}"
         "      var m = bg && bg.match(/url\\([\"']?([^\"')]+)[\"']?\\)/);"
         "      if (m && m[1] && m[1] !== 'none') {"
         "        return { kind: 'image', url: absUrl(m[1]), title: '',"
         "                 pageURL: absUrl(location.href), pageTitle: (document.title || '').trim(), thumb: '' };"
         "      }"
         "      bn = bn.parentElement;"
         "    }"
         "  }"
         // 4) WebKit 已确认是图片菜单：用最近大图兜底，绝不退回网页 URL
         "  if (forceImage) {"
         "    try {"
         "      var imgs = document.images || [];"
         "      var near = null, nearD = 1e15;"
         "      for (var j = 0; j < imgs.length; j++) {"
         "        var im2 = imgs[j];"
         "        var u2 = imgUrl(im2);"
         "        if (!u2 || u2.indexOf('data:') === 0) continue;"
         "        if (/logo|icon|avatar|sprite|emoji/i.test(u2) && (im2.naturalWidth||im2.width||0) < 120) continue;"
         "        var r2 = im2.getBoundingClientRect();"
         "        if (r2.width < 24 || r2.height < 24) continue;"
         "        var cx = r2.left + r2.width / 2, cy = r2.top + r2.height / 2;"
         "        var d = (cx - x) * (cx - x) + (cy - y) * (cy - y);"
         "        if (d < nearD) { nearD = d; near = im2; }"
         "      }"
         "      if (near) { var p3 = imagePayload(near); if (p3) return p3; }"
         "    } catch (e) {}"
         "  }"
         "  var pageHref = absUrl(location.href);"
         "  var pageTitle = (document.title || '').trim();"
         "  if (forceImage) {"
         "    return { kind: 'url', url: pageHref, title: pageTitle, _missImage: 1 };"
         "  }"
         "  var sel = (readSel() || '').trim();"
         "  if (sel) { return { kind: 'text', text: sel, url: pageHref, title: pageTitle }; }"
         "  var el = stack.length ? stack[0] : null;"
         "  var n = el;"
         "  while (n) {"
         "    if (n.tagName === 'A' && n.href) {"
         "      var href = absUrl(n.href);"
         "      var label = (n.innerText || n.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 80);"
         "      var path = '';"
         "      try { path = new URL(href).pathname || ''; } catch (e) {}"
         "      var ext = (path.split('.').pop() || '').toLowerCase();"
         "      var imgExt = {jpg:1,jpeg:1,png:1,gif:1,webp:1,svg:1,bmp:1,avif:1,ico:1};"
         "      var fileExt = {pdf:1,zip:1,rar:1,7z:1,tar:1,gz:1,doc:1,docx:1,xls:1,xlsx:1,ppt:1,pptx:1,"
         "        csv:1,json:1,xml:1,txt:1,md:1,dmg:1,pkg:1,mp3:1,mp4:1,mov:1,wav:1};"
         "      if (imgExt[ext]) {"
         "        return { kind: 'image', url: href, title: label, pageURL: pageHref, pageTitle: pageTitle };"
         "      }"
         "      if (fileExt[ext]) { return { kind: 'file', url: href, title: label || path.split('/').pop() }; }"
         "      return { kind: 'link', url: href, title: label };"
         "    }"
         "    n = n.parentElement;"
         "  }"
         "  return { kind: 'url', url: pageHref, title: pageTitle };"
         "})(%f, %f, %@)",
        [BrowserWebView meo_selectionCacheInstallJavaScript],
        x, y, forceImage ? @"true" : @"false"];
}

- (void)meo_rememberSelectedText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return;
    }
    self.contextMenuSelectedText = trimmed;
    self.meoStickySelectedText = trimmed;
}

- (void)meo_applyCapturedCitePayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *kind = [payload[@"kind"] isKindOfClass:[NSString class]] ? payload[@"kind"] : @"";
    NSString *text = [payload[@"text"] isKindOfClass:[NSString class]] ? payload[@"text"] : @"";
    // 命中图片/链接时覆盖缓存（右键落点优先）；仅「裸页面 URL」不要盖掉已有选区
    BOOL hitMedia = [kind isEqualToString:@"image"]
        || [kind isEqualToString:@"file"]
        || [kind isEqualToString:@"link"];
    if (!hitMedia && ![kind isEqualToString:@"text"]) {
        NSString *existingSel = [self.contextMenuSelectedText stringByTrimmingCharactersInSet:
                                 NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (existingSel.length == 0) {
            existingSel = [self.meoStickySelectedText stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        if (existingSel.length > 0) {
            return;
        }
    }
    self.contextMenuCitePayload = payload;
    if ([kind isEqualToString:@"text"] && text.length > 0) {
        [self meo_rememberSelectedText:text];
    }
}

- (void)meo_ensureSelectionCacheInstalled {
    [self evaluateJavaScript:[BrowserWebView meo_selectionCacheInstallJavaScript]
           completionHandler:nil];
}

- (void)meo_syncStickySelectionFromPageClearIfEmpty:(BOOL)clearIfEmpty {
    static NSString *const kRead =
        @"(function(){try{"
         "if(typeof window.__meoGetCachedSelection==='function'){"
         "  var c=window.__meoGetCachedSelection(); if(c&&String(c).trim()) return String(c);"
         "}"
         "if(window.__meoLastSelection&&String(window.__meoLastSelection).trim())"
         "  return String(window.__meoLastSelection);"
         "var s=window.getSelection&&window.getSelection();"
         "return s?String(s.toString()||''):'';"
         "}catch(e){return '';}})()";
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:kRead completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) return;
        NSString *trimmed = [(NSString *)result stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            [strongSelf meo_rememberSelectedText:trimmed];
        } else if (clearIfEmpty) {
            strongSelf.meoStickySelectedText = nil;
        }
    }];
}

/// 从 Accessibility 树读取当前高亮选区（JS selection 被清掉后仍可能可读）。
- (nullable NSString *)meo_accessibilitySelectedTextDeep {
    NSMutableArray *queue = [NSMutableArray array];
    [queue addObject:self];
    NSInteger budget = 80;
    while (queue.count > 0 && budget-- > 0) {
        id node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        @try {
            NSString *text = nil;
            if ([node respondsToSelector:@selector(accessibilitySelectedText)]) {
                text = [node accessibilitySelectedText];
            }
            if (![text isKindOfClass:[NSString class]] || text.length == 0) {
                if ([node respondsToSelector:@selector(accessibilityAttributeValue:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    id v = [node accessibilityAttributeValue:NSAccessibilitySelectedTextAttribute];
#pragma clang diagnostic pop
                    if ([v isKindOfClass:[NSString class]]) {
                        text = v;
                    }
                }
            }
            if ([text isKindOfClass:[NSString class]]) {
                NSString *trimmed = [text stringByTrimmingCharactersInSet:
                                     NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (trimmed.length > 0) {
                    return trimmed;
                }
            }
            NSArray *children = nil;
            if ([node respondsToSelector:@selector(accessibilityChildren)]) {
                children = [node accessibilityChildren];
            }
            if ([children isKindOfClass:[NSArray class]] && children.count) {
                NSUInteger limit = MIN(children.count, (NSUInteger)12);
                for (NSUInteger i = 0; i < limit; i++) {
                    [queue addObject:children[i]];
                }
            }
        } @catch (__unused NSException *ex) {
        }
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    [self meo_ensureSelectionCacheInstalled];
    [super mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event {
    [super mouseUp:event];
    // 划词松手后立刻同步到原生 sticky；无选区则清掉旧 sticky
    [self meo_syncStickySelectionFromPageClearIfEmpty:YES];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self meo_ensureSelectionCacheInstalled];
    // 在 WebKit 清 selection / 弹菜单前锁定 DOM 坐标
    self.contextMenuEvent = event;
    self.contextMenuDOMPoint = [self meo_domPointFromEvent:event];
    self.contextMenuDOMPointValid = (self.contextMenuDOMPoint.x >= 0 && self.contextMenuDOMPoint.y >= 0);
    self.contextMenuIsImageHit = NO;
    // 右键前再尽量同步读一次 AX（不等 JS）
    NSString *axText = [self meo_accessibilitySelectedTextDeep];
    if (axText.length > 0) {
        [self meo_rememberSelectedText:axText];
        self.contextMenuCitePayload = @{ @"kind": @"text", @"text": axText };
    } else if (self.meoStickySelectedText.length > 0) {
        self.contextMenuSelectedText = self.meoStickySelectedText;
        self.contextMenuCitePayload = @{ @"kind": @"text", @"text": self.meoStickySelectedText };
    }
    // 右键时页面 selection 可能已被清：空结果不要抹掉 sticky
    [self meo_syncStickySelectionFromPageClearIfEmpty:NO];
    [super rightMouseDown:event];
}

- (NSPoint)meo_contextMenuDOMPointResolved {
    if (self.contextMenuDOMPointValid) {
        return self.contextMenuDOMPoint;
    }
    return [self meo_domPointFromEvent:self.contextMenuEvent];
}

- (void)meo_captureContextMenuAIContext {
    NSPoint dom = [self meo_contextMenuDOMPointResolved];
    NSString *script = [self meo_contextMenuCiteScriptAtX:dom.x
                                                         y:dom.y
                                                forceImage:self.contextMenuIsImageHit];
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error) {
            return;
        }
        if ([result isKindOfClass:[NSDictionary class]]) {
            [strongSelf meo_applyCapturedCitePayload:(NSDictionary *)result];
        } else if ([result isKindOfClass:[NSString class]]) {
            // 极少数桥接只返回选区字符串
            NSString *sel = [(NSString *)result stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (sel.length) {
                [strongSelf meo_applyCapturedCitePayload:@{ @"kind": @"text", @"text": sel }];
            }
        }
    }];
}

- (NSDictionary *)meo_enrichCitePayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return payload;
    }
    NSString *kind = [payload[@"kind"] isKindOfClass:[NSString class]] ? payload[@"kind"] : @"";
    NSMutableDictionary *enriched = [payload mutableCopy];
    NSURL *pageURL = [BrowserWebView publicURLFromInternalURL:self.URL] ?: self.URL;
    NSString *pageAbs = pageURL.absoluteString ?: @"";
    NSString *pageTitle = [self.title stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";

    if ([kind isEqualToString:@"text"]) {
        NSString *existingURL = [enriched[@"url"] isKindOfClass:[NSString class]] ? enriched[@"url"] : @"";
        NSString *existingTitle = [enriched[@"title"] isKindOfClass:[NSString class]] ? enriched[@"title"] : @"";
        if (existingURL.length == 0 && pageAbs.length > 0) {
            enriched[@"url"] = pageAbs;
        }
        if (existingTitle.length == 0 && pageTitle.length > 0) {
            enriched[@"title"] = pageTitle;
        }
        return enriched;
    }

    if ([kind isEqualToString:@"image"]) {
        NSString *existingPage = [enriched[@"pageURL"] isKindOfClass:[NSString class]] ? enriched[@"pageURL"] : @"";
        NSString *existingPageTitle = [enriched[@"pageTitle"] isKindOfClass:[NSString class]] ? enriched[@"pageTitle"] : @"";
        if (existingPage.length == 0 && pageAbs.length > 0) {
            enriched[@"pageURL"] = pageAbs;
        }
        if (existingPageTitle.length == 0 && pageTitle.length > 0) {
            enriched[@"pageTitle"] = pageTitle;
        }
    }
    return enriched;
}

/// 用 WKWebView 截取页面上已渲染的图片区域（跨域 / 代理场景下 canvas·外链都会失败）。
- (void)meo_snapshotImageThumbnailForURL:(NSString *)imageURL
                              completion:(void (^)(NSImage *_Nullable image))completion {
    if (!completion) return;
    if (imageURL.length == 0) {
        completion(nil);
        return;
    }
    NSPoint click = [self meo_contextMenuDOMPointResolved];
    CGFloat clickX = click.x;
    CGFloat clickY = click.y;
    NSString *urlJSON = [BrowserWebView meo_jsStringLiteral:imageURL];
    NSString *js = [NSString stringWithFormat:
        @"(function(target, cx, cy){"
         "  function same(a,b){"
         "    if(!a||!b) return false;"
         "    if(a===b) return true;"
         "    try{"
         "      var ua=new URL(a, location.href), ub=new URL(b, location.href);"
         "      return ua.host===ub.host && ua.pathname===ub.pathname;"
         "    }catch(e){ return (a.indexOf(b)>=0)||(b.indexOf(a)>=0); }"
         "  }"
         "  function rectOf(el){"
         "    if(!el||!el.getBoundingClientRect) return null;"
         "    var r=el.getBoundingClientRect();"
         "    if(r.width<2||r.height<2) return null;"
         "    return {x:r.left,y:r.top,w:r.width,h:r.height};"
         "  }"
         "  var list=document.images||[];"
         "  for(var i=0;i<list.length;i++){"
         "    var im=list[i];"
         "    var u=im.currentSrc||im.src||'';"
         "    if(same(u,target)||same(im.src,target)){"
         "      var rr=rectOf(im); if(rr) return rr;"
         "    }"
         "  }"
         "  if(cx>=0&&cy>=0){"
         "    try{"
         "      var el=document.elementFromPoint(cx,cy);"
         "      var n=el;"
         "      while(n){"
         "        if(n.tagName==='IMG'){ var r2=rectOf(n); if(r2) return r2; }"
         "        if(n.tagName==='PICTURE'){"
         "          var img=n.querySelector('img'); var r3=rectOf(img); if(r3) return r3;"
         "        }"
         "        n=n.parentElement;"
         "      }"
         "    }catch(e){}"
         "  }"
         "  return null;"
         "})(%@, %f, %f)", urlJSON, clickX, clickY];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil);
            return;
        }
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            completion(nil);
            return;
        }
        NSDictionary *r = (NSDictionary *)result;
        CGFloat x = [r[@"x"] respondsToSelector:@selector(doubleValue)] ? [r[@"x"] doubleValue] : 0;
        CGFloat y = [r[@"y"] respondsToSelector:@selector(doubleValue)] ? [r[@"y"] doubleValue] : 0;
        CGFloat w = [r[@"w"] respondsToSelector:@selector(doubleValue)] ? [r[@"w"] doubleValue] : 0;
        CGFloat h = [r[@"h"] respondsToSelector:@selector(doubleValue)] ? [r[@"h"] doubleValue] : 0;
        if (w < 2 || h < 2) {
            completion(nil);
            return;
        }
        CGRect rect = CGRectMake(x, y, w, h);
        rect = CGRectIntersection(rect, strongSelf.bounds);
        if (CGRectIsEmpty(rect) || rect.size.width < 2 || rect.size.height < 2) {
            completion(nil);
            return;
        }
        if (@available(macOS 10.13, *)) {
            WKSnapshotConfiguration *config = [[WKSnapshotConfiguration alloc] init];
            config.rect = rect;
            config.afterScreenUpdates = NO;
            [strongSelf takeSnapshotWithConfiguration:config completionHandler:^(NSImage *snapshot, NSError *snapErr) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion((!snapErr && snapshot) ? snapshot : nil);
                });
            }];
        } else {
            completion(nil);
        }
    }];
}

- (void)meo_deliverCitePayload:(NSDictionary *)payload {
    if (self.contextMenuCiteDelivered) return;
    if (![payload isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *finalPayload = [self meo_enrichCitePayload:payload];
    NSString *kind = [finalPayload[@"kind"] isKindOfClass:[NSString class]] ? finalPayload[@"kind"] : @"";
    NSString *url = [finalPayload[@"url"] isKindOfClass:[NSString class]] ? finalPayload[@"url"] : @"";
    NSString *text = [finalPayload[@"text"] isKindOfClass:[NSString class]] ? finalPayload[@"text"] : @"";
    if ([kind isEqualToString:@"text"] && text.length == 0) return;
    if (![kind isEqualToString:@"text"] && url.length == 0 && text.length == 0) return;
    self.contextMenuCiteDelivered = YES;
    id wc = self.window.windowController;
    if (![wc isKindOfClass:[BrowserWindowController class]]) {
        return;
    }
    BrowserWindowController *controller = (BrowserWindowController *)wc;
    [controller addAIAssistantCitation:finalPayload];

    // 图片缩略图：优先截取页面已渲染区域（跨域 canvas / 代理下外链常失败）
    if ([kind isEqualToString:@"image"] && url.length > 0) {
        NSString *existingThumb = [finalPayload[@"thumb"] isKindOfClass:[NSString class]] ? finalPayload[@"thumb"] : @"";
        if ([existingThumb hasPrefix:@"data:image"]) {
            return;
        }
        __weak typeof(self) weakSelf = self;
        [self meo_snapshotImageThumbnailForURL:url completion:^(NSImage *image) {
            (void)weakSelf;
            if (image) {
                [controller updateAIAssistantCitationPreviewImage:image forImageURL:url];
                return;
            }
            // 截图失败再试 dataURL（同源 canvas）；侧栏自身仍有 URLSession 兜底
            [weakSelf meo_captureImageDataURLForURL:url completion:^(NSString *dataURL) {
                if (dataURL.length) {
                    [controller updateAIAssistantCitationThumbnail:dataURL forImageURL:url];
                }
            }];
        }];
    }
}

/// 同源 canvas / 页面 fetch 兜底（跨域常失败）。
- (void)meo_captureImageDataURLForURL:(NSString *)imageURL
                           completion:(void (^)(NSString *_Nullable dataURL))completion {
    if (imageURL.length == 0 || !completion) {
        if (completion) completion(nil);
        return;
    }
    if ([imageURL hasPrefix:@"data:image"]) {
        completion(imageURL);
        return;
    }
    NSString *urlJSON = [BrowserWebView meo_jsStringLiteral:imageURL];
    NSString *js = [NSString stringWithFormat:
        @"(function(target){"
         "  function same(a,b){"
         "    if(!a||!b) return false; if(a===b) return true;"
         "    try{ var ua=new URL(a),ub=new URL(b); return ua.host===ub.host&&ua.pathname===ub.pathname; }"
         "    catch(e){ return a.indexOf(b)>=0||b.indexOf(a)>=0; }"
         "  }"
         "  function canvasThumb(img){"
         "    try{"
         "      var w=img.naturalWidth||0,h=img.naturalHeight||0;"
         "      if(!w||!h) return '';"
         "      var max=128,s=Math.min(1,max/Math.max(w,h));"
         "      var c=document.createElement('canvas');"
         "      c.width=Math.max(1,Math.round(w*s)); c.height=Math.max(1,Math.round(h*s));"
         "      c.getContext('2d').drawImage(img,0,0,c.width,c.height);"
         "      return c.toDataURL('image/jpeg',0.72);"
         "    }catch(e){return '';}"
         "  }"
         "  try{"
         "    var list=document.images||[];"
         "    for(var i=0;i<list.length;i++){"
         "      var im=list[i], u=im.currentSrc||im.src||'';"
         "      if(same(u,target)||same(im.src,target)){"
         "        var t=canvasThumb(im); if(t) return Promise.resolve(t);"
         "      }"
         "    }"
         "  }catch(e){}"
         "  return fetch(target,{credentials:'include',mode:'cors',cache:'force-cache'})"
         "    .then(function(r){ if(!r.ok) throw new Error('bad'); return r.blob(); })"
         "    .then(function(b){ return new Promise(function(res,rej){"
         "      var fr=new FileReader(); fr.onload=function(){res(String(fr.result||''));};"
         "      fr.onerror=function(){rej(new Error('fr'));}; fr.readAsDataURL(b);"
         "    }); })"
         "    .catch(function(){ return ''; });"
         "})(%@)", urlJSON];
    [self evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSString class]]) {
            completion(nil);
            return;
        }
        NSString *s = [(NSString *)result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        completion([s hasPrefix:@"data:image"] ? s : nil);
    }];
}

- (void)meo_aiAssistantSummarizePage:(id)sender {
#pragma unused(sender)
    id wc = self.window.windowController;
    if ([wc isKindOfClass:[BrowserWindowController class]]) {
        [(BrowserWindowController *)wc openAIAssistantSummarizeCurrentPage];
    }
}

- (void)meo_aiAssistantAskPage:(id)sender {
#pragma unused(sender)
    id wc = self.window.windowController;
    if ([wc isKindOfClass:[BrowserWindowController class]]) {
        [(BrowserWindowController *)wc openAIAssistantAskCurrentPage];
    }
}

- (void)meo_aiAssistantAction:(id)sender {
    NSMenuItem *item = [sender isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)sender : nil;
    NSString *actionKey = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : BrowserAIAssistantActionAsk;

    // 优先用菜单弹出时缓存的选区
    NSString *cached = [self.contextMenuSelectedText stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (cached.length == 0) {
        cached = [self.meoStickySelectedText stringByTrimmingCharactersInSet:
                  NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (cached.length > 0) {
        id wc = self.window.windowController;
        if ([wc isKindOfClass:[BrowserWindowController class]]) {
            [(BrowserWindowController *)wc openAIAssistantWithAction:actionKey
                                                             context:cached
                                                         pageContext:NO];
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *selJS =
        @"(function(){try{"
         "if(typeof window.__meoGetCachedSelection==='function'){"
         "  var c=window.__meoGetCachedSelection(); if(c&&String(c).trim()) return String(c);"
         "}"
         "if(window.__meoLastSelection&&String(window.__meoLastSelection).trim()) return String(window.__meoLastSelection);"
         "var sel=window.getSelection&&window.getSelection();"
         "return sel?String(sel.toString()||''):'';"
         "}catch(e){return '';}})()";
    [self evaluateJavaScript:selJS
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *trimmed = @"";
        if (!error && [result isKindOfClass:[NSString class]]) {
            trimmed = [(NSString *)result stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (trimmed.length == 0) {
            trimmed = [strongSelf.contextMenuSelectedText stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        }
        BOOL pageContext = trimmed.length == 0;
        NSString *context = trimmed;
        if (pageContext) {
            context = [strongSelf meo_pageContextString] ?: @"";
            if (context.length == 0) {
                return;
            }
        }
        id wc = strongSelf.window.windowController;
        if ([wc isKindOfClass:[BrowserWindowController class]]) {
            [(BrowserWindowController *)wc openAIAssistantWithAction:actionKey
                                                             context:context
                                                         pageContext:pageContext];
        }
    }];
}

- (nullable NSDictionary *)meo_readyCitePayloadFromCache {
    if ([self.contextMenuCitePayload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *cached = self.contextMenuCitePayload;
        NSString *kind = [cached[@"kind"] isKindOfClass:[NSString class]] ? cached[@"kind"] : @"";
        // 右键落点命中的图片/文件/链接优先于划词 sticky
        if ([kind isEqualToString:@"image"] || [kind isEqualToString:@"file"] || [kind isEqualToString:@"link"]) {
            return cached;
        }
        if ([kind isEqualToString:@"url"]) {
            NSString *url = [cached[@"url"] isKindOfClass:[NSString class]] ? cached[@"url"] : @"";
            if (url.length > 0) {
                // 若同时有选区，选区更具体；否则用页面
                NSString *cachedSel = [self.contextMenuSelectedText stringByTrimmingCharactersInSet:
                                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (cachedSel.length == 0) {
                    cachedSel = [self.meoStickySelectedText stringByTrimmingCharactersInSet:
                                 NSCharacterSet.whitespaceAndNewlineCharacterSet];
                }
                if (cachedSel.length == 0) {
                    return cached;
                }
            }
        }
        if ([kind isEqualToString:@"text"]) {
            NSString *text = [cached[@"text"] isKindOfClass:[NSString class]] ? cached[@"text"] : @"";
            if (text.length > 0) {
                return cached;
            }
        }
    }
    NSString *cachedSel = [self.contextMenuSelectedText stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (cachedSel.length == 0) {
        cachedSel = [self.meoStickySelectedText stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (cachedSel.length > 0) {
        return @{ @"kind": @"text", @"text": cachedSel };
    }
    return nil;
}

- (BOOL)meo_citeKindIsHitMedia:(NSString *)kind {
    return [kind isEqualToString:@"image"]
        || [kind isEqualToString:@"file"]
        || [kind isEqualToString:@"link"];
}

- (void)meo_fallbackLiveCiteCapture {
    NSPoint dom = [self meo_contextMenuDOMPointResolved];
    BOOL forceImage = self.contextMenuIsImageHit;
    NSString *script = [self meo_contextMenuCiteScriptAtX:dom.x y:dom.y forceImage:forceImage];
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.contextMenuCiteDelivered) return;

        void (^forceImageOrPage)(void) = ^{
            if (forceImage) {
                [strongSelf meo_resolveForcedImageCitationThenDeliver];
            } else {
                NSURL *u = [BrowserWebView publicURLFromInternalURL:strongSelf.URL] ?: strongSelf.URL;
                [strongSelf meo_deliverCitePayload:@{
                    @"kind": @"url",
                    @"url": u.absoluteString ?: @"",
                    @"title": strongSelf.title ?: @"",
                }];
            }
        };

        if (!error && [result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *hit = (NSDictionary *)result;
            NSString *kind = [hit[@"kind"] isKindOfClass:[NSString class]] ? hit[@"kind"] : @"";
            // WebKit 菜单已标明是图片：拒绝退回「网页」引用
            if (forceImage && ![kind isEqualToString:@"image"]) {
                [strongSelf meo_resolveForcedImageCitationThenDeliver];
                return;
            }
            if ([strongSelf meo_citeKindIsHitMedia:kind] || [kind isEqualToString:@"url"] || [kind isEqualToString:@"text"]) {
                [strongSelf meo_applyCapturedCitePayload:hit];
                [strongSelf meo_deliverCitePayload:hit];
                return;
            }
        } else if (forceImage) {
            [strongSelf meo_resolveForcedImageCitationThenDeliver];
            return;
        }

        NSDictionary *ready = [strongSelf meo_readyCitePayloadFromCache];
        if (ready) {
            NSString *rk = [ready[@"kind"] isKindOfClass:[NSString class]] ? ready[@"kind"] : @"";
            if (forceImage && ![rk isEqualToString:@"image"]) {
                [strongSelf meo_resolveForcedImageCitationThenDeliver];
                return;
            }
            [strongSelf meo_deliverCitePayload:ready];
            return;
        }

        forceImageOrPage();
    }];
}

/// WebKit 已确认点的是图，但坐标 hit-test 失败时：取视口内面积最大的内容图。
- (void)meo_resolveForcedImageCitationThenDeliver {
    if (self.contextMenuCiteDelivered) return;
    NSString *js =
        @"(function(){"
         "  function absUrl(u){ try{return new URL(u,document.baseURI).href;}catch(e){return u||'';} }"
         "  var pageHref=absUrl(location.href), pageTitle=(document.title||'').trim();"
         "  var imgs=document.images||[], best=null, bestArea=0;"
         "  for(var i=0;i<imgs.length;i++){"
         "    var im=imgs[i];"
         "    var u=absUrl(im.currentSrc||im.getAttribute('data-src')||im.src||'');"
         "    if(!u||u.indexOf('data:')===0) continue;"
         "    if(/\\/(logo|icon|avatar|favicon|sprite)/i.test(u) && (im.naturalWidth||im.width||0)<160) continue;"
         "    var r=im.getBoundingClientRect();"
         "    if(r.width<40||r.height<40) continue;"
         "    if(r.bottom<0||r.right<0||r.top>innerHeight||r.left>innerWidth) continue;"
         "    var area=r.width*r.height;"
         "    if(area>bestArea){ bestArea=area; best=im; }"
         "  }"
         "  if(!best) return null;"
         "  return {kind:'image', url:absUrl(best.currentSrc||best.getAttribute('data-src')||best.src),"
         "          title:(best.alt||'').trim(), pageURL:pageHref, pageTitle:pageTitle, thumb:''};"
         "})()";
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.contextMenuCiteDelivered) return;
        if (!error && [result isKindOfClass:[NSDictionary class]]) {
            [strongSelf meo_deliverCitePayload:(NSDictionary *)result];
            return;
        }
        // 最后兜底：仍带上当前页，并在状态里可感知失败（侧栏会显示网页引用）
        NSURL *u = [BrowserWebView publicURLFromInternalURL:strongSelf.URL] ?: strongSelf.URL;
        [strongSelf meo_deliverCitePayload:@{
            @"kind": @"url",
            @"url": u.absoluteString ?: @"",
            @"title": strongSelf.title ?: @"",
        }];
    }];
}

/// 加入引用：图片菜单强制走取图；否则优先用已捕获/sticky 缓存，缺再现场 hit-test。
- (void)meo_aiAssistantAddCitation:(id)sender {
    (void)sender;
    if (self.contextMenuIsImageHit) {
        NSString *kind = [self.contextMenuCitePayload[@"kind"] isKindOfClass:[NSString class]]
            ? self.contextMenuCitePayload[@"kind"] : @"";
        if ([kind isEqualToString:@"image"]) {
            [self meo_deliverCitePayload:self.contextMenuCitePayload];
            return;
        }
        [self meo_fallbackLiveCiteCapture];
        return;
    }
    if ([self.contextMenuCitePayload isKindOfClass:[NSDictionary class]]) {
        NSString *kind = [self.contextMenuCitePayload[@"kind"] isKindOfClass:[NSString class]]
            ? self.contextMenuCitePayload[@"kind"] : @"";
        if ([self meo_citeKindIsHitMedia:kind] || [kind isEqualToString:@"text"]) {
            [self meo_deliverCitePayload:self.contextMenuCitePayload];
            return;
        }
    }
    NSDictionary *ready = [self meo_readyCitePayloadFromCache];
    if (ready) {
        [self meo_deliverCitePayload:ready];
        return;
    }
    [self meo_fallbackLiveCiteCapture];
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

- (void)meo_viewPageSource:(id)sender {
    (void)sender;
    id responder = self.window.firstResponder;
    // 走窗口控制器的 viewPageSource:（响应链 / 直接查找）。
    NSWindowController *wc = self.window.windowController;
    if ([wc respondsToSelector:@selector(viewPageSource:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [wc performSelector:@selector(viewPageSource:) withObject:nil];
#pragma clang diagnostic pop
        return;
    }
    (void)responder;
    [NSApp sendAction:@selector(viewPageSource:) to:nil from:self];
}

#pragma mark - 右键「重新载入框架」

/// 用右键点击坐标向上查找最近的 <iframe>，若命中则让 reloadFrameItem 显示。
- (void)meo_probeContextMenuForFrameHitAndShowReloadItem:(NSMenuItem *)reloadFrameItem {
    if (!reloadFrameItem) {
        return;
    }
    if (!self.contextMenuEvent) {
        return;
    }
    NSPoint dom = [self meo_domPointFromEvent:self.contextMenuEvent];

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  var el = document.elementFromPoint(x, y);"
         "  if (!el) { return false; }"
         "  var n = el;"
         "  while (n && n !== document.documentElement) {"
         "    if (n.tagName === 'IFRAME' || n.tagName === 'FRAME') { return true; }"
         "    n = n.parentElement;"
         "  }"
         "  return false;"
         "})(%f, %f)", dom.x, dom.y];

    __weak typeof(self) weakSelf = self;
    __weak NSMenuItem *weakItem = reloadFrameItem;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        NSMenuItem *item = weakItem;
        if (!strongSelf || !item) {
            return;
        }
        if (error) {
            return;
        }
        BOOL hitFrame = [result respondsToSelector:@selector(boolValue)] && [result boolValue];
        // 菜单已关闭（异步探测可能晚于关闭）则不再修改可见性。
        if (item.menu == nil) {
            return;
        }
        item.hidden = !hitFrame;
    }];
}

/// 仅刷新右键点击位置所在的 iframe，不影响主页面或兄弟 iframe。
- (void)meo_reloadFrame:(id)sender {
    (void)sender;
    if (!self.contextMenuEvent) {
        return;
    }
    NSPoint dom = [self meo_domPointFromEvent:self.contextMenuEvent];

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  var el = document.elementFromPoint(x, y);"
         "  if (!el) { return false; }"
         "  var n = el;"
         "  while (n && n !== document.documentElement) {"
         "    if (n.tagName === 'IFRAME' || n.tagName === 'FRAME') {"
         "      try {"
         "        if (n.contentWindow && typeof n.contentWindow.location.reload === 'function') {"
         "          n.contentWindow.location.reload();"
         "          return true;"
         "        }"
         "      } catch (e) {"
         "        try {"
         "          n.src = n.src;"
         "          return true;"
         "        } catch (e2) { return false; }"
         "      }"
         "    }"
         "    n = n.parentElement;"
         "  }"
         "  return false;"
         "})(%f, %f)", dom.x, dom.y];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        (void)weakSelf;
        (void)error;
    }];
}

- (void)meo_openLinkAtContextMenuPointInNewWindow {
    if (!self.contextMenuEvent) {
        return;
    }
    NSPoint dom = [self meo_domPointFromEvent:self.contextMenuEvent];

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
         "})(%f, %f)", dom.x, dom.y];

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
    if (!self.contextMenuEvent) {
        return;
    }
    // WKWebView.isFlipped=YES：勿再 height-y，否则命不中图片
    NSPoint dom = [self meo_domPointFromEvent:self.contextMenuEvent];

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
         "      return absUrl(n.currentSrc || n.src || n.getAttribute('data-src'));"
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
         "})(%f, %f)", dom.x, dom.y];

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

#pragma mark - First responder（避开 WebKit 同步 SetFocused IPC）

/// 直接调用 NSView 的实现，跳过 WKWebView 里对 WebContent 的 sync IPC。
/// objc_msgSendSuper 的 super_class 表示从其父类开始查找，故传 WKWebView → 落到 NSView。
/// 该 IPC 在重页/直播等场景下会阻塞主线程约 3s；表单光标改由软件 caret 脚本补上。
static BOOL MeoCallNSViewFocusMethod(BrowserWebView *view, SEL selector) {
    struct objc_super superNSView = {
        .receiver = view,
        .super_class = [WKWebView class],
    };
    return ((BOOL (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superNSView, selector);
}

- (BOOL)becomeFirstResponder {
    BOOL ok = MeoCallNSViewFocusMethod(self, _cmd);
    if (ok) {
        // 通知地址栏：网页重新获焦后，下次点击地址栏应全选 URL。
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"BrowserWebViewDidBecomeFirstResponder"
                          object:self];
    }
    return ok;
}

- (BOOL)resignFirstResponder {
    BOOL ok = MeoCallNSViewFocusMethod(self, _cmd);
    // AppKit 侧已失焦；页面内 caret 异步 blur，避免阻塞 chrome。
    [self evaluateJavaScript:
         @"try{var a=document.activeElement;"
          "if(a&&a!==document.body&&a.blur)a.blur();}"
          "catch(e){}"
           completionHandler:nil];
    return ok;
}

@end

@implementation BrowserChromeWindow

- (BOOL)makeFirstResponder:(NSResponder *)responder {
    // WK 常把内部 NSView 设为 firstResponder；对该视图 resign/become 会 sync IPC。
    // 一律改绑到外层 BrowserWebView，走上面的无 IPC 实现。
    if ([responder isKindOfClass:[NSView class]]) {
        for (NSView *v = (NSView *)responder; v != nil; v = v.superview) {
            if ([v isKindOfClass:[BrowserWebView class]]) {
                if (responder != v) {
                    return [super makeFirstResponder:v];
                }
                break;
            }
        }
    }
    return [super makeFirstResponder:responder];
}

@end
