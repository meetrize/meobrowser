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
    if ([BrowsingPreferences isPersistableURL:liveURL]) {
        return liveURL;
    }
    if ([BrowsingPreferences isPersistableURL:self.restorableURL]) {
        return self.restorableURL;
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
    NSURL *url = self.restorableURL;
    if (![BrowsingPreferences isPersistableURL:url]) {
        [self loadNewTabPage];
        return;
    }
    [self ensureWebView];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)loadNewTabPage {
    self.isNewTabPage = YES;
    self.title = @"新标签页";
    self.addressBarDraft = nil;
    self.restorableURL = nil;
    [self discardWebView];
}

- (void)loadURL:(NSURL *)url {
    self.isNewTabPage = NO;
    self.addressBarDraft = nil;
    self.restorableURL = url;
    [self ensureWebView];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
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
