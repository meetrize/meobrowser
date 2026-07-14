#import "BrowserTab.h"
#import "BrowserWebView.h"

@interface BrowserTab ()
@property (nonatomic, assign) BOOL hasPendingMainFrameNavigation;
@property (nonatomic, strong) NSMutableSet<WKNavigation *> *mainFrameNavigations;
@property (nonatomic, assign, readwrite) NSInteger titleUpdateGeneration;
@end

@implementation BrowserTab

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration {
    BrowserTab *tab = [[self alloc] init];
    tab->_tabID = [NSUUID UUID];
    tab->_webView = [[BrowserWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
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
