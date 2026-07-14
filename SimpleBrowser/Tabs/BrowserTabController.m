#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "BrowsingPreferences.h"

static const NSUInteger kRecentlyClosedTabLimit = 20;

@interface BrowserRecentlyClosedEntry : NSObject
@property (nonatomic, copy) NSString *sessionEntry;
@property (nonatomic, assign) NSUInteger insertionIndex;
@property (nonatomic, assign) BOOL wasPinned;
@end

@implementation BrowserRecentlyClosedEntry
@end

@interface BrowserTabController ()
@property (nonatomic, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *mutableTabs;
@property (nonatomic, strong, nullable) BrowserTab *selectedTab;
@property (nonatomic, strong) NSMutableArray<BrowserRecentlyClosedEntry *> *recentlyClosedEntries;
@end

@implementation BrowserTabController

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _mutableTabs = [[NSMutableArray alloc] init];
        _recentlyClosedEntries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSArray<BrowserTab *> *)tabs {
    return [self.mutableTabs copy];
}

- (BOOL)canRestoreRecentlyClosedTab {
    return self.recentlyClosedEntries.count > 0;
}

- (NSUInteger)pinnedTabCount {
    NSUInteger count = 0;
    for (BrowserTab *tab in self.mutableTabs) {
        if (!tab.isPinned) {
            break;
        }
        count++;
    }
    return count;
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
        [self rememberClosedTab:tab atIndex:index];
        [self.delegate tabControllerRequestsCloseWindow:self];
        return;
    }

    [self removeTabAtIndex:index rememberClosed:YES];
    [self notifyChange];
}

- (void)closeSelectedTab {
    if (self.selectedTab) {
        [self closeTab:self.selectedTab];
    }
}

- (void)closeOtherTabsExcept:(BrowserTab *)tab {
    NSUInteger keepIndex = [self.mutableTabs indexOfObject:tab];
    if (keepIndex == NSNotFound || self.mutableTabs.count <= 1) {
        return;
    }

    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.mutableTabs.count)];
    [indexes removeIndex:keepIndex];
    [self removeTabsAtIndexes:indexes];
}

- (void)closeTabsToTheRightOf:(BrowserTab *)tab {
    NSUInteger index = [self.mutableTabs indexOfObject:tab];
    if (index == NSNotFound || index + 1 >= self.mutableTabs.count) {
        return;
    }

    NSRange range = NSMakeRange(index + 1, self.mutableTabs.count - (index + 1));
    [self removeTabsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
}

- (nullable BrowserTab *)restoreRecentlyClosedTab {
    BrowserRecentlyClosedEntry *entry = self.recentlyClosedEntries.lastObject;
    if (!entry) {
        return nil;
    }
    [self.recentlyClosedEntries removeLastObject];

    BrowserTab *tab = [self tabFromSessionEntry:entry.sessionEntry];
    tab.pinned = entry.wasPinned;

    NSUInteger insertIndex = MIN(entry.insertionIndex, self.mutableTabs.count);
    if (tab.isPinned) {
        insertIndex = MIN(insertIndex, self.pinnedTabCount);
    } else {
        insertIndex = MAX(insertIndex, self.pinnedTabCount);
        insertIndex = MIN(insertIndex, self.mutableTabs.count);
    }
    [self.mutableTabs insertObject:tab atIndex:insertIndex];
    self.selectedTab = tab;
    [self notifyChange];
    return tab;
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

- (void)moveTab:(BrowserTab *)tab toIndex:(NSUInteger)toIndex {
    NSUInteger fromIndex = [self.mutableTabs indexOfObject:tab];
    if (fromIndex == NSNotFound || self.mutableTabs.count <= 1) {
        return;
    }

    // toIndex 为移动完成后的最终下标（0…count-1）；固定/普通标签不可越过分界。
    NSUInteger pinnedCount = self.pinnedTabCount;
    NSUInteger desired = MIN(toIndex, self.mutableTabs.count - 1);
    if (tab.isPinned) {
        if (pinnedCount == 0) {
            return;
        }
        desired = MIN(desired, pinnedCount - 1);
    } else {
        desired = MAX(desired, pinnedCount);
    }
    if (desired == fromIndex) {
        return;
    }

    [self.mutableTabs removeObjectAtIndex:fromIndex];
    NSUInteger insertIndex = MIN(desired, self.mutableTabs.count);
    [self.mutableTabs insertObject:tab atIndex:insertIndex];
    [self notifyChange];
}

- (void)setTab:(BrowserTab *)tab pinned:(BOOL)pinned {
    NSUInteger index = [self.mutableTabs indexOfObject:tab];
    if (index == NSNotFound || tab.isPinned == pinned) {
        return;
    }

    [self.mutableTabs removeObjectAtIndex:index];
    tab.pinned = pinned;
    NSUInteger insertIndex = MIN(self.pinnedTabCount, self.mutableTabs.count);
    [self.mutableTabs insertObject:tab atIndex:insertIndex];
    [self notifyChange];
}

- (void)restoreTabsFromEntries:(NSArray<NSString *> *)entries
                 selectedIndex:(NSInteger)selectedIndex
                   pinnedCount:(NSUInteger)pinnedCount {
    for (BrowserTab *tab in [self.mutableTabs copy]) {
        [tab.webView removeFromSuperview];
    }
    [self.mutableTabs removeAllObjects];
    self.selectedTab = nil;

    NSUInteger clampedPinned = MIN(pinnedCount, entries.count);
    for (NSUInteger i = 0; i < entries.count; i++) {
        BrowserTab *tab = [self tabFromSessionEntry:entries[i]];
        tab.pinned = (i < clampedPinned);
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

#pragma mark - Private

- (void)removeTabsAtIndexes:(NSIndexSet *)indexes {
    if (indexes.count == 0) {
        return;
    }

    // 从右往左移除；最近关闭栈用 LIFO，先关右侧的后恢复时也会先恢复更靠右的。
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse
                              usingBlock:^(NSUInteger idx, BOOL *stop) {
                                  (void)stop;
                                  [self removeTabAtIndex:idx rememberClosed:YES];
                              }];
    [self notifyChange];
}

- (void)removeTabAtIndex:(NSUInteger)index rememberClosed:(BOOL)rememberClosed {
    if (index >= self.mutableTabs.count) {
        return;
    }

    BrowserTab *tab = self.mutableTabs[index];
    if (rememberClosed) {
        [self rememberClosedTab:tab atIndex:index];
    }

    BOOL closingSelected = (tab == self.selectedTab);
    [tab.webView removeFromSuperview];
    [self.mutableTabs removeObjectAtIndex:index];

    if (closingSelected && self.mutableTabs.count > 0) {
        NSUInteger nextIndex = index > 0 ? index - 1 : 0;
        if (nextIndex >= self.mutableTabs.count) {
            nextIndex = self.mutableTabs.count - 1;
        }
        self.selectedTab = self.mutableTabs[nextIndex];
    }
}

- (void)rememberClosedTab:(BrowserTab *)tab atIndex:(NSUInteger)index {
    BrowserRecentlyClosedEntry *entry = [[BrowserRecentlyClosedEntry alloc] init];
    entry.sessionEntry = [self sessionEntryForTab:tab];
    entry.insertionIndex = index;
    entry.wasPinned = tab.isPinned;
    [self.recentlyClosedEntries addObject:entry];
    while (self.recentlyClosedEntries.count > kRecentlyClosedTabLimit) {
        [self.recentlyClosedEntries removeObjectAtIndex:0];
    }
}

- (NSString *)sessionEntryForTab:(BrowserTab *)tab {
    if (tab.isNewTabPage) {
        return BrowserTabSessionNewTabMarker;
    }
    if ([BrowsingPreferences isPersistableURL:tab.webView.URL]) {
        return tab.webView.URL.absoluteString;
    }
    return BrowserTabSessionNewTabMarker;
}

- (BrowserTab *)tabFromSessionEntry:(NSString *)entry {
    if ([entry isEqualToString:BrowserTabSessionNewTabMarker]) {
        BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
        [tab loadNewTabPage];
        return tab;
    }

    NSURL *url = [NSURL URLWithString:entry];
    if (!url) {
        BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
        [tab loadNewTabPage];
        return tab;
    }

    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    [tab loadURL:url];
    return tab;
}

- (void)notifyChange {
    [self.delegate tabControllerDidChange:self];
}

@end
