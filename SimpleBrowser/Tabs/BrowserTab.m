#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserUserAgent.h"
#import "BrowsingPreferences.h"
#import "BrowserFeedReader.h"

@interface BrowserTab ()
@property (nonatomic, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, strong, nullable, readwrite) WKWebView *webView;
@property (nonatomic, assign) BOOL hasPendingMainFrameNavigation;
@property (nonatomic, strong) NSMutableSet<WKNavigation *> *mainFrameNavigations;
@property (nonatomic, assign, readwrite) NSInteger titleUpdateGeneration;
/// 已创建 WebView、待 navigationDelegate 挂上后再加载 restorableURL。
@property (nonatomic, assign) BOOL pendingRestorableLoad;
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
    if ([BrowsingPreferences isPersistableURL:liveURL]) {
        return liveURL;
    }
    NSURL *restored = [BrowserWebView publicURLFromInternalURL:self.restorableURL] ?: self.restorableURL;
    if ([BrowsingPreferences isPersistableURL:restored]) {
        return restored;
    }
    return nil;
}

- (WKWebView *)ensureWebView {
    if (self.webView != nil) {
        return self.webView;
    }
    self.webView = [[BrowserWebView alloc] initWithFrame:NSZeroRect configuration:self.configuration];
    self.webView.customUserAgent = [BrowserUserAgent safariAlignedUserAgent];
    return self.webView;
}

- (void)discardWebView {
    WKWebView *webView = self.webView;
    if (webView == nil) {
        return;
    }
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
    if (![BrowsingPreferences isPersistableURL:url]) {
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
    if (![BrowsingPreferences isPersistableURL:url]) {
        return;
    }
    self.restorableURL = url;
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
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
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
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
    if (!self.hasPendingMainFrameNavigation) {
        return NO;
    }
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

@end
