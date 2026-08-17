#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserUserAgent.h"
#import "BrowsingPreferences.h"
#import "BrowserFeedReader.h"
#import "BrowserLocalFileSupport.h"
#import "BrowserWebInspector.h"
#import "BrowserNavigationSession.h"

static void *kBrowserTabWebViewTitleContext = &kBrowserTabWebViewTitleContext;

@interface BrowserTab ()
@property (nonatomic, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, strong, nullable, readwrite) WKWebView *webView;
@property (nonatomic, assign) BOOL hasPendingMainFrameNavigation;
@property (nonatomic, strong) NSMutableSet<WKNavigation *> *mainFrameNavigations;
/// WebKit 在部分主框架导航（跨站支付跳转等）会传入 nil WKNavigation，NSSet 不能存 nil，改用计数跟踪。
@property (nonatomic, assign) NSUInteger nilMainFrameNavigationCount;
@property (nonatomic, assign, readwrite) NSInteger titleUpdateGeneration;
/// 已创建 WebView、待 navigationDelegate 挂上后再加载 restorableURL。
@property (nonatomic, assign) BOOL pendingRestorableLoad;
@property (nonatomic, assign) BOOL observingWebViewTitle;
@property (nonatomic, assign) NSInteger navigationGenerationCounter;
@end

@implementation BrowserTab

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration {
    BrowserTab *tab = [[self alloc] init];
    tab->_tabID = [NSUUID UUID];
    tab->_configuration = configuration;
    tab.title = @"新标签页";
    tab.isNewTabPage = YES;
    tab.lastActiveTimestamp = [NSDate date].timeIntervalSince1970;
    return tab;
}

+ (instancetype)tabWithExistingWebView:(WKWebView *)webView {
    NSParameterAssert(webView != nil);
    BrowserTab *tab = [[self alloc] init];
    tab->_tabID = [NSUUID UUID];
    tab->_configuration = webView.configuration;
    tab.webView = webView;
    tab.title = @"新窗口";
    tab.isNewTabPage = NO;
    tab.lastActiveTimestamp = [NSDate date].timeIntervalSince1970;
    [BrowserWebInspector applyInspectableToWebView:webView];
    [tab startObservingWebViewTitle];
    return tab;
}

- (BOOL)resistsHibernation {
    return self.relatedPopupRetainCount > 0 || self.relatedOpenerTab != nil;
}

- (void)detachRelatedPopupOpener {
    BrowserTab *opener = self.relatedOpenerTab;
    if (opener == nil) {
        return;
    }
    self.relatedOpenerTab = nil;
    if (opener.relatedPopupRetainCount > 0) {
        opener.relatedPopupRetainCount -= 1;
    }
}

- (BOOL)isHibernated {
    return !self.isNewTabPage && self.webView == nil && self.restorableURL != nil;
}

- (nullable NSURL *)currentOrRestorableURL {
    if (self.isNewTabPage) {
        return nil;
    }
    NSURL *liveURL = [BrowserFeedReader publicURLForInternalURL:self.webView.URL];
    liveURL = [BrowserWebView publicURLFromInternalURL:liveURL];
    NSURL *restored = [BrowserWebView publicURLFromInternalURL:self.restorableURL] ?: self.restorableURL;

    // 同文档锚点经 replaceState 后，WKWebView.URL 有时尚未带上 #；保留 restorable 中的 fragment。
    if (liveURL != nil && restored.fragment.length > 0 && liveURL.fragment.length == 0
        && [BrowserWebView URL:liveURL isSameDocumentAsURL:restored]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:liveURL resolvingAgainstBaseURL:NO];
        components.fragment = restored.fragment;
        NSURL *merged = components.URL;
        if ([self isAddressBarDisplayableURL:merged]) {
            return merged;
        }
    }

    if ([self isAddressBarDisplayableURL:liveURL]) {
        return liveURL;
    }
    if ([self isAddressBarDisplayableURL:restored]) {
        return restored;
    }
    return nil;
}

- (BOOL)isAddressBarDisplayableURL:(nullable NSURL *)url {
    if (!url) {
        return NO;
    }
    if ([BrowsingPreferences isPersistableURL:url]) {
        return YES;
    }
    // 本地 HTML 不进会话，但仍应显示在地址栏。
    return url.isFileURL;
}

- (WKWebView *)ensureWebView {
    if (self.webView != nil) {
        return self.webView;
    }
    self.webView = [[BrowserWebView alloc] initWithFrame:NSZeroRect configuration:self.configuration];
    self.webView.customUserAgent = [BrowserUserAgent safariAlignedUserAgent];
    [BrowserWebInspector applyInspectableToWebView:self.webView];
    [self startObservingWebViewTitle];
    return self.webView;
}

- (void)startObservingWebViewTitle {
    if (self.observingWebViewTitle || self.webView == nil) {
        return;
    }
    [self.webView addObserver:self
                   forKeyPath:@"title"
                      options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                      context:kBrowserTabWebViewTitleContext];
    self.observingWebViewTitle = YES;
}

- (void)stopObservingWebViewTitle {
    if (!self.observingWebViewTitle || self.webView == nil) {
        self.observingWebViewTitle = NO;
        return;
    }
    @try {
        [self.webView removeObserver:self
                          forKeyPath:@"title"
                             context:kBrowserTabWebViewTitleContext];
    } @catch (__unused NSException *exception) {
    }
    self.observingWebViewTitle = NO;
}

- (void)applyPageTitle:(NSString *)pageTitle {
    if (self.isNewTabPage) {
        return;
    }
    NSString *trimmed = [pageTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    if ([self.title isEqualToString:trimmed]) {
        return;
    }
    self.title = trimmed;
    void (^handler)(BrowserTab *) = self.titleDidChangeHandler;
    if (handler) {
        handler(self);
    }
}

- (void)pullDocumentTitleFromWebView {
    WKWebView *webView = self.webView;
    if (webView == nil || self.isNewTabPage) {
        return;
    }

    // 先用 WKWebView.title（与 <title> / document.title 同步）。
    [self applyPageTitle:webView.title];

    // 再读 document.title，覆盖 SPA 晚到或 KVO 偶发漏报。
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    [webView evaluateJavaScript:@"document.title || ''"
              completionHandler:^(id result, NSError *error) {
        (void)error;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView || strongSelf.webView != strongWebView) {
            return;
        }
        if (![result isKindOfClass:[NSString class]]) {
            return;
        }
        [strongSelf applyPageTitle:(NSString *)result];
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context == kBrowserTabWebViewTitleContext) {
        if (object == self.webView && [keyPath isEqualToString:@"title"]) {
            [self applyPageTitle:self.webView.title];
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)discardWebView {
    WKWebView *webView = self.webView;
    if (webView == nil) {
        return;
    }
    [self stopObservingWebViewTitle];
    self.titleDidChangeHandler = nil;
    [webView stopLoading];
    // 关闭标签 / 休眠前退出 HTML5 全屏与 PiP，避免残留全屏窗口。
    if (@available(macOS 11.3, *)) {
        [webView closeAllMediaPresentationsWithCompletionHandler:^{}];
    }
    webView.navigationDelegate = nil;
    webView.UIDelegate = nil;
    if ([webView isKindOfClass:[BrowserWebView class]]) {
        BrowserWebView *browserWebView = (BrowserWebView *)webView;
        browserWebView.openURLHandler = nil;
        browserWebView.openURLInNewWindowHandler = nil;
        browserWebView.downloadURLHandler = nil;
    }
    [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
    [webView removeFromSuperview];
    self.webView = nil;
    self.isLoading = NO;
    self.connectionSecurityState = BrowserConnectionSecurityStateUnknown;
    [self clearNavigationSession];
    [self.mainFrameNavigations removeAllObjects];
    self.nilMainFrameNavigationCount = 0;
    self.hasPendingMainFrameNavigation = NO;
}

- (void)prepareForClose {
    [self detachRelatedPopupOpener];
    [self discardWebView];
    self.restorableURL = nil;
    self.pendingHTMLString = nil;
}

- (void)hibernate {
    if (self.resistsHibernation) {
        return;
    }
    if (self.isNewTabPage || self.webView == nil) {
        return;
    }
    // 源代码等内存 HTML 页：保留 pendingHTMLString，丢弃 WebView。
    if (self.pendingHTMLString.length > 0) {
        self.restorableURL = nil;
        [self discardWebView];
        return;
    }
    NSURL *url = [BrowserFeedReader publicURLForInternalURL:self.webView.URL];
    url = [BrowserWebView publicURLFromInternalURL:url];
    if ([BrowsingPreferences isPersistableURL:url]) {
        self.restorableURL = url;
        if (self.title.length == 0 || [self.title isEqualToString:@"新标签页"]) {
            self.title = url.host.length > 0 ? url.host : url.absoluteString;
        }
    } else if (url.isFileURL) {
        self.restorableURL = url;
        if (self.title.length == 0 || [self.title isEqualToString:@"新标签页"]) {
            NSString *name = url.lastPathComponent;
            self.title = name.length > 0 ? name : @"本地文件";
        }
    } else if (self.restorableURL.isFileURL) {
        // 保留已有 file:// 恢复点。
    } else if (![BrowsingPreferences isPersistableURL:self.restorableURL]) {
        // 无可恢复 URL 时退回 NTP，避免留下无内容僵尸标签。
        [self loadNewTabPage];
        return;
    }
    [self discardWebView];
}

- (void)forceDiscardWebViewForHardRecover {
    if (self.isNewTabPage || self.webView == nil) {
        self.isLoading = NO;
        [self clearNavigationSession];
        return;
    }
    // 与 hibernate 相同保留 restorable；但忽略 resistsHibernation。
    if (self.pendingHTMLString.length > 0) {
        // 内存 HTML：硬恢复后退回可再加载的 pending。
        [self discardWebView];
        self.pendingRestorableLoad = NO;
        return;
    }
    NSURL *url = [BrowserFeedReader publicURLForInternalURL:self.webView.URL];
    url = [BrowserWebView publicURLFromInternalURL:url];
    if ([BrowsingPreferences isPersistableURL:url] || url.isFileURL) {
        self.restorableURL = url;
    }
    [self discardWebView];
    self.pendingRestorableLoad = NO;
}

- (void)wakeFromHibernationIfNeeded {
    if (self.isNewTabPage) {
        return;
    }
    if (self.webView != nil) {
        return;
    }
    if (self.pendingHTMLString.length > 0) {
        [self ensureWebView];
        self.pendingRestorableLoad = YES;
        return;
    }
    NSURL *url = [BrowserWebView publicURLFromInternalURL:self.restorableURL] ?: self.restorableURL;
    BOOL canRestore = [BrowsingPreferences isPersistableURL:url] || url.isFileURL;
    if (!canRestore) {
        [self loadNewTabPage];
        return;
    }
    self.restorableURL = url;
    [self ensureWebView];
    // 不在这里 loadRequest：须等窗口把 navigationDelegate 挂上，否则 #hash 恢复会未经拦截直接发网 → 代理下 404。
    self.pendingRestorableLoad = YES;
}

- (void)loadPendingRestorableURLIfNeeded {
    if (!self.pendingRestorableLoad || self.webView == nil) {
        return;
    }
    // 硬恢复等待用户确认：只重建 WebView，不自动导航。
    if (self.pendingHardRecover) {
        self.pendingRestorableLoad = NO;
        return;
    }
    self.pendingRestorableLoad = NO;
    if (self.pendingHTMLString.length > 0) {
        NSString *html = self.pendingHTMLString;
        // 勿用自定义 scheme 作 baseURL：会被 decidePolicy 当成外链交接。
        [self beginNavigationSessionWithURL:nil];
        [self.webView loadHTMLString:html baseURL:[NSURL URLWithString:@"about:blank"]];
        return;
    }
    NSURL *url = [BrowserWebView publicURLFromInternalURL:self.restorableURL] ?: self.restorableURL;
    if ([BrowsingPreferences isPersistableURL:url]) {
        self.restorableURL = url;
        [self beginNavigationSessionWithURL:url];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        return;
    }
    // 本地 file:// 不进会话，但外部打开 / 休眠唤醒仍需加载。
    if (url.isFileURL) {
        self.restorableURL = url;
        [self beginNavigationSessionWithURL:url];
        if (![BrowserLocalFileSupport loadFileURL:url inWebView:self.webView]) {
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }
}

- (void)loadNewTabPage {
    self.isNewTabPage = YES;
    self.title = @"新标签页";
    self.addressBarDraft = nil;
    self.restorableURL = nil;
    self.pendingHTMLString = nil;
    self.pendingRestorableLoad = NO;
    self.pendingHardRecover = NO;
    self.hardRecoverMessage = nil;
    [self discardWebView];
}

- (void)prepareHTMLDocument:(NSString *)html title:(NSString *)title {
    NSParameterAssert(html != nil);
    self.isNewTabPage = NO;
    self.addressBarDraft = nil;
    self.restorableURL = nil;
    self.pendingHTMLString = [html copy];
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.title = trimmed.length > 0 ? trimmed : @"源代码";
    // 等 refreshTabsUI：wake → attach navigationDelegate → loadPendingRestorableURLIfNeeded。
    self.pendingRestorableLoad = YES;
}

- (void)loadURL:(NSURL *)url {
    url = [BrowserWebView publicURLFromInternalURL:url] ?: url;
    self.isNewTabPage = NO;
    self.addressBarDraft = nil;
    self.restorableURL = url;
    self.pendingHardRecover = NO;
    self.hardRecoverMessage = nil;
    [self ensureWebView];
    // 尚无 navigationDelegate 时只记 pending，等窗口 attach 后再加载（避免 #hash 恢复竞态）。
    if (self.webView.navigationDelegate == nil) {
        self.pendingRestorableLoad = YES;
    } else {
        self.pendingRestorableLoad = NO;
        [self beginNavigationSessionWithURL:url];
        if (url.isFileURL) {
            if (![BrowserLocalFileSupport loadFileURL:url inWebView:self.webView]) {
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
            }
        } else {
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }
}

- (BrowserNavigationSession *)beginNavigationSessionWithURL:(NSURL *)url {
    self.navigationGenerationCounter += 1;
    BrowserNavigationSession *session =
        [BrowserNavigationSession sessionWithGeneration:self.navigationGenerationCounter
                                                  tabID:self.tabID
                                                    URL:url];
    if ([BrowserWebView URLContainsHashRestoreQuery:url]) {
        session.usesShortDocumentLoadGrace = YES;
    }
    self.navigationSession = session;
    self.isLoading = YES;
    void (^handler)(BrowserTab *, BrowserNavigationSession *) = self.navigationSessionDidBeginHandler;
    if (handler) {
        handler(self, session);
    }
    return session;
}

- (void)clearNavigationSession {
    self.navigationSession = nil;
}

- (void)markNavigationSessionProvisional {
    BrowserNavigationSession *session = self.navigationSession;
    if (!session) {
        return;
    }
    session.phase = BrowserNavigationSessionPhaseProvisional;
}

- (void)markNavigationSessionCommitted {
    BrowserNavigationSession *session = self.navigationSession;
    if (!session) {
        return;
    }
    session.phase = BrowserNavigationSessionPhaseCommitted;
}

- (NSString *)displayTitle {
    if (self.title.length > 0) {
        return self.title;
    }
    return @"新标签页";
}

- (void)notePendingMainFrameNavigation {
    self.hasPendingMainFrameNavigation = YES;
}

- (BOOL)beginMainFrameNavigation:(WKNavigation *)navigation {
    // WebKit 仅对主框架调用 didStartProvisionalNavigation；即使 decidePolicy 漏记 pending
    //（如 targetFrame == nil 的 loadRequest），也必须接纳，否则标题/进度永远不同步。
    // navigation 可能为 nil（支付跳转 / 部分跨站重定向等），不可直接 addObject:。
    self.hasPendingMainFrameNavigation = NO;
    if (navigation) {
        if (!self.mainFrameNavigations) {
            self.mainFrameNavigations = [NSMutableSet set];
        }
        [self.mainFrameNavigations addObject:navigation];
    } else {
        self.nilMainFrameNavigationCount++;
    }
    self.titleUpdateGeneration++;
    return YES;
}

- (BOOL)isMainFrameNavigation:(WKNavigation *)navigation {
    if (navigation) {
        return [self.mainFrameNavigations containsObject:navigation];
    }
    return self.nilMainFrameNavigationCount > 0;
}

- (void)endMainFrameNavigation:(WKNavigation *)navigation {
    if (navigation) {
        [self.mainFrameNavigations removeObject:navigation];
    } else if (self.nilMainFrameNavigationCount > 0) {
        self.nilMainFrameNavigationCount--;
    }
}

- (void)dealloc {
    [self stopObservingWebViewTitle];
}

@end
