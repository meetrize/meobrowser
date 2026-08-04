#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserUserAgent.h"
#import "BrowsingPreferences.h"
#import "BrowserFeedReader.h"
#import "BrowserLocalFileSupport.h"

static void *kBrowserTabWebViewTitleContext = &kBrowserTabWebViewTitleContext;

@interface BrowserTab ()
@property (nonatomic, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, strong, nullable, readwrite) WKWebView *webView;
@property (nonatomic, assign) BOOL hasPendingMainFrameNavigation;
@property (nonatomic, strong) NSMutableSet<WKNavigation *> *mainFrameNavigations;
@property (nonatomic, assign, readwrite) NSInteger titleUpdateGeneration;
/// 已创建 WebView、待 navigationDelegate 挂上后再加载 restorableURL。
@property (nonatomic, assign) BOOL pendingRestorableLoad;
@property (nonatomic, assign) BOOL observingWebViewTitle;
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
    [self.mainFrameNavigations removeAllObjects];
    self.hasPendingMainFrameNavigation = NO;
}

- (void)prepareForClose {
    [self discardWebView];
    self.restorableURL = nil;
}

- (void)hibernate {
    if (self.isNewTabPage || self.webView == nil) {
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

- (void)wakeFromHibernationIfNeeded {
    if (self.isNewTabPage) {
        return;
    }
    if (self.webView != nil) {
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
    self.pendingRestorableLoad = NO;
    NSURL *url = [BrowserWebView publicURLFromInternalURL:self.restorableURL] ?: self.restorableURL;
    if ([BrowsingPreferences isPersistableURL:url]) {
        self.restorableURL = url;
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        return;
    }
    // 本地 file:// 不进会话，但外部打开 / 休眠唤醒仍需加载。
    if (url.isFileURL) {
        self.restorableURL = url;
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
    self.pendingRestorableLoad = NO;
    [self discardWebView];
}

- (void)loadURL:(NSURL *)url {
    url = [BrowserWebView publicURLFromInternalURL:url] ?: url;
    self.isNewTabPage = NO;
    self.addressBarDraft = nil;
    self.restorableURL = url;
    [self ensureWebView];
    // 尚无 navigationDelegate 时只记 pending，等窗口 attach 后再加载（避免 #hash 恢复竞态）。
    if (self.webView.navigationDelegate == nil) {
        self.pendingRestorableLoad = YES;
    } else {
        self.pendingRestorableLoad = NO;
        if (url.isFileURL) {
            if (![BrowserLocalFileSupport loadFileURL:url inWebView:self.webView]) {
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
            }
        } else {
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }
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
    self.hasPendingMainFrameNavigation = NO;
    if (!self.mainFrameNavigations) {
        self.mainFrameNavigations = [NSMutableSet set];
    }
    [self.mainFrameNavigations addObject:navigation];
    self.titleUpdateGeneration++;
    return YES;
}

- (BOOL)isMainFrameNavigation:(WKNavigation *)navigation {
    return [self.mainFrameNavigations containsObject:navigation];
}

- (void)endMainFrameNavigation:(WKNavigation *)navigation {
    [self.mainFrameNavigations removeObject:navigation];
}

- (void)dealloc {
    [self stopObservingWebViewTitle];
}

@end
