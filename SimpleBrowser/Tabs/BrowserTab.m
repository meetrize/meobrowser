#import "BrowserTab.h"

@implementation BrowserTab

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration {
    BrowserTab *tab = [[self alloc] init];
    tab->_tabID = [NSUUID UUID];
    tab->_webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    tab.title = @"新标签页";
    tab.isNewTabPage = YES;
    return tab;
}

- (void)loadNewTabPage {
    self.isNewTabPage = YES;
    self.title = @"新标签页";
    [self.webView stopLoading];
}

- (void)loadURL:(NSURL *)url {
    self.isNewTabPage = NO;
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (NSString *)displayTitle {
    if (self.isLoading) {
        return @"加载中…";
    }
    if (self.title.length > 0) {
        return self.title;
    }
    return @"新标签页";
}

@end
