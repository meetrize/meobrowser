#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "BrowsingPreferences.h"

@interface BrowserTabController ()
@property (nonatomic, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *mutableTabs;
@property (nonatomic, strong, nullable) BrowserTab *selectedTab;
@end

@implementation BrowserTabController

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _mutableTabs = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSArray<BrowserTab *> *)tabs {
    return [self.mutableTabs copy];
}

- (BrowserTab *)addNewTab {
    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    [tab loadNewTabPage];
    [self.mutableTabs addObject:tab];
    self.selectedTab = tab;
    [self notifyChange];
    return tab;
}

- (BrowserTab *)addTabWithURL:(NSURL *)url {
    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    [tab loadURL:url];
    [self.mutableTabs addObject:tab];
    self.selectedTab = tab;
    [self notifyChange];
    return tab;
}

- (void)closeTab:(BrowserTab *)tab {
    NSUInteger index = [self.mutableTabs indexOfObject:tab];
    if (index == NSNotFound) {
        return;
    }

    if (self.mutableTabs.count <= 1) {
        [self.delegate tabControllerRequestsCloseWindow:self];
        return;
    }

    BOOL closingSelected = (tab == self.selectedTab);
    [tab.webView removeFromSuperview];
    [self.mutableTabs removeObjectAtIndex:index];

    if (closingSelected) {
        NSUInteger nextIndex = index > 0 ? index - 1 : 0;
        self.selectedTab = self.mutableTabs[nextIndex];
    }

    [self notifyChange];
}

- (void)closeSelectedTab {
    if (self.selectedTab) {
        [self closeTab:self.selectedTab];
    }
}

- (void)selectTab:(BrowserTab *)tab {
    if (![self.mutableTabs containsObject:tab]) {
        return;
    }
    self.selectedTab = tab;
    [self notifyChange];
}

- (void)selectNextTab {
    if (self.mutableTabs.count <= 1) {
        return;
    }
    NSUInteger index = [self.mutableTabs indexOfObject:self.selectedTab];
    if (index == NSNotFound) {
        return;
    }
    NSUInteger nextIndex = (index + 1) % self.mutableTabs.count;
    self.selectedTab = self.mutableTabs[nextIndex];
    [self notifyChange];
}

- (void)selectPreviousTab {
    if (self.mutableTabs.count <= 1) {
        return;
    }
    NSUInteger index = [self.mutableTabs indexOfObject:self.selectedTab];
    if (index == NSNotFound) {
        return;
    }
    NSUInteger prevIndex = index == 0 ? self.mutableTabs.count - 1 : index - 1;
    self.selectedTab = self.mutableTabs[prevIndex];
    [self notifyChange];
}

- (void)restoreTabsFromEntries:(NSArray<NSString *> *)entries selectedIndex:(NSInteger)selectedIndex {
    for (BrowserTab *tab in [self.mutableTabs copy]) {
        [tab.webView removeFromSuperview];
    }
    [self.mutableTabs removeAllObjects];
    self.selectedTab = nil;

    for (NSString *entry in entries) {
        if ([entry isEqualToString:BrowserTabSessionNewTabMarker]) {
            BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
            [tab loadNewTabPage];
            [self.mutableTabs addObject:tab];
            continue;
        }

        NSURL *url = [NSURL URLWithString:entry];
        if (!url) {
            continue;
        }
        BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
        [tab loadURL:url];
        [self.mutableTabs addObject:tab];
    }

    if (self.mutableTabs.count == 0) {
        [self addNewTab];
        return;
    }

    NSInteger clampedIndex = MAX(0, MIN(selectedIndex, (NSInteger)self.mutableTabs.count - 1));
    self.selectedTab = self.mutableTabs[(NSUInteger)clampedIndex];
    [self notifyChange];
}

- (NSInteger)indexOfSelectedTab {
    if (!self.selectedTab) {
        return NSNotFound;
    }
    return (NSInteger)[self.mutableTabs indexOfObject:self.selectedTab];
}

- (nullable BrowserTab *)tabForWebView:(WKWebView *)webView {
    for (BrowserTab *tab in self.mutableTabs) {
        if (tab.webView == webView) {
            return tab;
        }
    }
    return nil;
}

- (void)notifyChange {
    [self.delegate tabControllerDidChange:self];
}

@end
