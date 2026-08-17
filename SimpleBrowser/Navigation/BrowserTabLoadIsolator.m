#import "BrowserTabLoadIsolator.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserFeedReader.h"
#import "BrowsingPreferences.h"
#import "BrowserNavigationDiagnostics.h"

@implementation BrowserTabLoadIsolator

+ (WKWebView *)forceAbandonWebViewInTab:(BrowserTab *)tab failingURL:(NSURL *)failingURL {
    if (!tab || tab.isNewTabPage) {
        return nil;
    }

    WKWebView *webView = tab.webView;
    NSURL *url = [BrowserWebView publicURLFromInternalURL:failingURL] ?: failingURL;
    if (!url) {
        url = [BrowserFeedReader publicURLForInternalURL:webView.URL];
        url = [BrowserWebView publicURLFromInternalURL:url] ?: tab.restorableURL;
    }

    if ([BrowsingPreferences isPersistableURL:url] || url.isFileURL) {
        tab.restorableURL = url;
    }

    tab.pendingHardRecover = YES;
    tab.isLoading = NO;
    [tab clearNavigationSession];

    BrowserNavigationLog(@"hard-abandon tab=%@ url=%@ hadWebView=%d",
                         tab.tabID.UUIDString,
                         url.absoluteString ?: @"(nil)",
                         webView != nil);

    // 绕过 resistsHibernation：僵死恢复优先于 related popup 保留。
    [tab forceDiscardWebViewForHardRecover];
    return webView;
}

@end
