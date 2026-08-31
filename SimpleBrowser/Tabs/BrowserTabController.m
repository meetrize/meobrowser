#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserRiskHostPolicy.h"
#import "BrowsingPreferences.h"
#import <AppKit/AppKit.h>

static const NSUInteger kRecentlyClosedTabLimit = 20;
static const NSUInteger kMaxLiveWebViews = 8;
static const NSUInteger kMaxLiveWebViewsGlobal = 12;
static const NSTimeInterval kHibernateIdleSeconds = 600.0; // 10 minutes
static const NSTimeInterval kHibernateIdleSecondsMediaHeavy = 90.0;
static const NSTimeInterval kHibernateCheckInterval = 30.0;
/// 近期交互过的标签在宽限期内不参与预算回收（快速切回时不重载）。
static const NSTimeInterval kHibernateGraceSeconds = 120.0;
/// 切标签后延迟执行预算回收，避免连续切换时同步销毁刚失焦的 WebView。
static const NSTimeInterval kBudgetEnforcementDelaySeconds = 5.0;

static NSTimeInterval BrowserTabLastInteractionTimestamp(BrowserTab *tab) {
    return MAX(tab.lastActiveTimestamp, tab.lastDeactivatedTimestamp);
}

static BOOL BrowserTabIsWithinHibernationGrace(BrowserTab *tab, NSTimeInterval now) {
    return (now - BrowserTabLastInteractionTimestamp(tab)) < kHibernateGraceSeconds;
}

static BOOL BrowserTabIsEligibleForBudgetHibernation(BrowserTab *tab, BrowserTab *selectedTab, NSTimeInterval now) {
    if (tab == selectedTab || tab.webView == nil || tab.isNewTabPage || tab.resistsHibernation) {
        return NO;
    }
    if (BrowserTabIsWithinHibernationGrace(tab, now)) {
        return NO;
    }
    return YES;
}

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
@property (nonatomic, strong, nullable) NSTimer *hibernateTimer;
@end

@implementation BrowserTabController

+ (NSHashTable<BrowserTabController *> *)registeredControllers {
    static NSHashTable<BrowserTabController *> *controllers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controllers = [NSHashTable weakObjectsHashTable];
    });
    return controllers;
}

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _mutableTabs = [[NSMutableArray alloc] init];
        _recentlyClosedEntries = [[NSMutableArray alloc] init];
        [[[self class] registeredControllers] addObject:self];
        [self startHibernateTimer];
    }
    return self;
}

- (void)dealloc {
    [self.hibernateTimer invalidate];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(performDeferredBudgetEnforcement)
                                               object:nil];
    [[[self class] registeredControllers] removeObject:self];
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
    [self selectTabInternal:tab notify:YES];
    return tab;
}

- (BrowserTab *)addTabWithURL:(NSURL *)url {
    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    url = [BrowserWebView publicURLFromInternalURL:url] ?: url;
    // 只占位，不在此处 load：等 refreshTabsUI 挂上 navigationDelegate 后再加载。
    tab.isNewTabPage = NO;
    tab.restorableURL = url;
    if (url.isFileURL) {
        NSString *name = url.lastPathComponent;
        tab.title = name.length > 0 ? name : @"本地文件";
    } else {
        tab.title = url.host.length > 0 ? url.host : (url.absoluteString.length > 0 ? url.absoluteString : @"新标签页");
    }
    [self.mutableTabs addObject:tab];
    [self selectTabInternal:tab notify:YES];
    return tab;
}

- (BrowserTab *)addTabWithHTMLString:(NSString *)html title:(NSString *)title {
    NSParameterAssert(html != nil);
    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    [tab prepareHTMLDocument:html title:title];
    [self.mutableTabs addObject:tab];
    [self selectTabInternal:tab notify:YES];
    return tab;
}

- (BrowserTab *)addRelatedPopupTabWithWebView:(WKWebView *)webView initialURL:(nullable NSURL *)url {
    BrowserTab *opener = self.selectedTab;
    BrowserTab *tab = [BrowserTab tabWithExistingWebView:webView];
    url = [BrowserWebView publicURLFromInternalURL:url] ?: url;
    // WebKit 会自行导航返回的 WebView；切勿再 loadRequest / pendingRestorableLoad。
    if ([BrowsingPreferences isPersistableURL:url]) {
        tab.restorableURL = url;
        tab.title = url.host.length > 0 ? url.host : url.absoluteString;
    } else if (url.isFileURL) {
        tab.restorableURL = url;
        NSString *name = url.lastPathComponent;
        tab.title = name.length > 0 ? name : @"本地文件";
    } else if (url.host.length > 0) {
        tab.title = url.host;
    } else {
        tab.title = @"登录";
    }
    if (opener != nil && opener != tab) {
        tab.relatedOpenerTab = opener;
        opener.relatedPopupRetainCount += 1;
    }
    [self.mutableTabs addObject:tab];
    [self selectTabInternal:tab notify:YES];
    return tab;
}

- (void)closeTab:(BrowserTab *)tab {
    NSUInteger index = [self.mutableTabs indexOfObject:tab];
    if (index == NSNotFound) {
        return;
    }

    if (self.mutableTabs.count <= 1) {
        [self rememberClosedTab:tab atIndex:index];
        [tab prepareForClose];
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

- (nullable BrowserTab *)extractTabKeepingAlive:(BrowserTab *)tab {
    NSUInteger index = [self.mutableTabs indexOfObject:tab];
    if (index == NSNotFound) {
        return nil;
    }

    BOOL wasSelected = (tab == self.selectedTab);

    WKWebView *webView = tab.webView;
    if (webView != nil) {
        [webView removeFromSuperview];
        webView.navigationDelegate = nil;
        webView.UIDelegate = nil;
        if ([webView isKindOfClass:[BrowserWebView class]]) {
            BrowserWebView *browserWebView = (BrowserWebView *)webView;
            browserWebView.openURLHandler = nil;
            browserWebView.openURLInNewWindowHandler = nil;
            browserWebView.downloadURLHandler = nil;
        }
    }

    [self.mutableTabs removeObjectAtIndex:index];

    if (self.mutableTabs.count == 0) {
        self.selectedTab = nil;
        return tab;
    }

    if (wasSelected) {
        NSUInteger nextIndex = index > 0 ? index - 1 : 0;
        if (nextIndex >= self.mutableTabs.count) {
            nextIndex = self.mutableTabs.count - 1;
        }
        [self selectTabInternal:self.mutableTabs[nextIndex] notify:NO];
    }
    [self notifyChange];
    return tab;
}

- (void)adoptTab:(BrowserTab *)tab {
    NSUInteger index = self.mutableTabs.count;
    if (tab.isPinned) {
        index = self.pinnedTabCount;
    }
    [self adoptTab:tab atIndex:index];
}

- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index {
    if (!tab) {
        return;
    }
    if ([self.mutableTabs indexOfObject:tab] != NSNotFound) {
        [self selectTabInternal:tab notify:YES];
        return;
    }

    NSUInteger insertIndex = index;
    if (tab.isPinned) {
        insertIndex = MIN(insertIndex, self.pinnedTabCount);
    } else {
        insertIndex = MAX(insertIndex, self.pinnedTabCount);
    }
    insertIndex = MIN(insertIndex, self.mutableTabs.count);
    [self.mutableTabs insertObject:tab atIndex:insertIndex];
    [self selectTabInternal:tab notify:YES];
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

    BrowserTab *tab = [self tabFromSessionEntry:entry.sessionEntry materialize:NO];
    tab.pinned = entry.wasPinned;

    NSUInteger insertIndex = MIN(entry.insertionIndex, self.mutableTabs.count);
    if (tab.isPinned) {
        insertIndex = MIN(insertIndex, self.pinnedTabCount);
    } else {
        insertIndex = MAX(insertIndex, self.pinnedTabCount);
        insertIndex = MIN(insertIndex, self.mutableTabs.count);
    }
    [self.mutableTabs insertObject:tab atIndex:insertIndex];
    [self selectTabInternal:tab notify:YES];
    return tab;
}

- (void)selectTab:(BrowserTab *)tab {
    if (![self.mutableTabs containsObject:tab]) {
        return;
    }
    if (self.selectedTab == tab) {
        // 已选中但可能仍休眠：走 refreshTabsUI，保证先 attach 再 load。
        if (tab.isHibernated) {
            [self notifyChange];
        }
        return;
    }
    [self selectTabInternal:tab notify:YES];
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
    [self selectTabInternal:self.mutableTabs[nextIndex] notify:YES];
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
    [self selectTabInternal:self.mutableTabs[prevIndex] notify:YES];
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
        [tab prepareForClose];
    }
    [self.mutableTabs removeAllObjects];
    self.selectedTab = nil;

    NSUInteger clampedPinned = MIN(pinnedCount, entries.count);
    for (NSUInteger i = 0; i < entries.count; i++) {
        // 先全部占位；仅选中项在下方 materialize。
        BrowserTab *tab = [self tabFromSessionEntry:entries[i] materialize:NO];
        tab.pinned = (i < clampedPinned);
        [self.mutableTabs addObject:tab];
    }

    if (self.mutableTabs.count == 0) {
        [self addNewTab];
        return;
    }

    NSInteger clampedIndex = MAX(0, MIN(selectedIndex, (NSInteger)self.mutableTabs.count - 1));
    BrowserTab *selected = self.mutableTabs[(NSUInteger)clampedIndex];
    [self selectTabInternal:selected notify:YES];
}

- (NSInteger)indexOfSelectedTab {
    if (!self.selectedTab) {
        return NSNotFound;
    }
    return (NSInteger)[self.mutableTabs indexOfObject:self.selectedTab];
}

- (nullable BrowserTab *)tabForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return nil;
    }
    for (BrowserTab *tab in self.mutableTabs) {
        if (tab.webView == webView) {
            return tab;
        }
    }
    return nil;
}

#pragma mark - Private

- (void)selectTabInternal:(BrowserTab *)tab notify:(BOOL)notify {
    BrowserTab *previousTab = self.selectedTab;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (previousTab != nil && previousTab != tab) {
        previousTab.lastDeactivatedTimestamp = now;
        // 失焦也视为近期活跃，避免长时间驻留后一切走即因旧时间戳被预算回收。
        previousTab.lastActiveTimestamp = now;
    }
    self.selectedTab = tab;
    tab.lastActiveTimestamp = now;
    // 不在此处 wake+load：由 refreshTabsUI 先 attach navigationDelegate 再加载。
    if (notify) {
        [self notifyChange];
    }
    [self scheduleDeferredBudgetEnforcement];
}

- (void)scheduleDeferredBudgetEnforcement {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(performDeferredBudgetEnforcement)
                                               object:nil];
    [self performSelector:@selector(performDeferredBudgetEnforcement)
               withObject:nil
               afterDelay:kBudgetEnforcementDelaySeconds];
}

- (void)performDeferredBudgetEnforcement {
    BOOL changed = NO;
    if ([self enforceLiveWebViewBudget]) {
        changed = YES;
    }
    if ([[self class] enforceGlobalLiveWebViewBudget]) {
        changed = YES;
    }
    if (changed) {
        [self notifyChange];
    }
}

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
    [tab prepareForClose];
    [self.mutableTabs removeObjectAtIndex:index];

    if (closingSelected && self.mutableTabs.count > 0) {
        NSUInteger nextIndex = index > 0 ? index - 1 : 0;
        if (nextIndex >= self.mutableTabs.count) {
            nextIndex = self.mutableTabs.count - 1;
        }
        [self selectTabInternal:self.mutableTabs[nextIndex] notify:NO];
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
    NSURL *url = [tab currentOrRestorableURL];
    if ([BrowsingPreferences isPersistableURL:url]) {
        return url.absoluteString;
    }
    return BrowserTabSessionNewTabMarker;
}

- (BrowserTab *)tabFromSessionEntry:(NSString *)entry materialize:(BOOL)materialize {
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
    if (materialize) {
        [tab loadURL:url];
    } else {
        tab.isNewTabPage = NO;
        tab.restorableURL = url;
        tab.title = url.host.length > 0 ? url.host : url.absoluteString;
    }
    return tab;
}

#pragma mark - Hibernation

- (void)startHibernateTimer {
    __weak typeof(self) weakSelf = self;
    self.hibernateTimer = [NSTimer scheduledTimerWithTimeInterval:kHibernateCheckInterval
                                                          repeats:YES
                                                            block:^(NSTimer *timer) {
                                                                (void)timer;
                                                                [weakSelf evaluateHibernation];
                                                            }];
    self.hibernateTimer.tolerance = 5.0;
}

- (void)evaluateHibernation {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    BOOL changed = NO;

    for (BrowserTab *tab in self.mutableTabs) {
        if (tab == self.selectedTab || tab.webView == nil || tab.isNewTabPage || tab.resistsHibernation) {
            continue;
        }
        NSURL *protectURL = tab.webView.URL ?: tab.restorableURL;
        if ([BrowserRiskHostPolicy URLIsHibernationProtected:protectURL]) {
            continue;
        }
        NSTimeInterval idleLimit = tab.mediaHeavy ? kHibernateIdleSecondsMediaHeavy : kHibernateIdleSeconds;
        if (now - BrowserTabLastInteractionTimestamp(tab) >= idleLimit) {
            [tab hibernate];
            changed = YES;
        }
    }

    if ([self liveWebViewCount] > kMaxLiveWebViews) {
        if ([self enforceLiveWebViewBudget]) {
            changed = YES;
        }
    }

    if ([[self class] globalLiveWebViewCount] > kMaxLiveWebViewsGlobal) {
        if ([[self class] enforceGlobalLiveWebViewBudget]) {
            changed = YES;
        }
    }

    if (changed) {
        [self notifyChange];
    }
}

- (NSUInteger)liveWebViewCount {
    NSUInteger count = 0;
    for (BrowserTab *tab in self.mutableTabs) {
        if (tab.webView != nil) {
            count++;
        }
    }
    return count;
}

+ (NSUInteger)globalLiveWebViewCount {
    NSUInteger count = 0;
    for (BrowserTabController *controller in [self registeredControllers]) {
        count += [controller liveWebViewCount];
    }
    return count;
}

+ (nullable BrowserTabController *)keyWindowTabController {
    id windowController = NSApp.keyWindow.windowController;
    if (![windowController respondsToSelector:@selector(tabController)]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id tabController = [windowController performSelector:@selector(tabController)];
#pragma clang diagnostic pop
    if ([tabController isKindOfClass:[BrowserTabController class]]) {
        return tabController;
    }
    return nil;
}

/// 预算淘汰优先级：非保护优先；mediaHeavy 更易被杀；同级再比非 key 窗、再比最久未活动。
+ (NSInteger)hibernationVictimRankForTab:(BrowserTab *)tab isNonKeyWindow:(BOOL)isNonKey {
    NSURL *url = tab.webView.URL ?: tab.restorableURL;
    BOOL protectedHost = [BrowserRiskHostPolicy URLIsHibernationProtected:url];
    // 更大 = 更不宜被杀；选择时取 rank 更小者。
    NSInteger rank = 0;
    if (protectedHost) {
        rank += 100;
    }
    if (!tab.mediaHeavy) {
        rank += 5;
    }
    if (!isNonKey) {
        rank += 10;
    }
    return rank;
}

+ (BOOL)enforceGlobalLiveWebViewBudget {
    BOOL changed = NO;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    while ([self globalLiveWebViewCount] > kMaxLiveWebViewsGlobal) {
        BrowserTabController *keyController = [self keyWindowTabController];
        BrowserTab *victim = nil;
        BrowserTabController *victimController = nil;
        NSInteger bestRank = NSIntegerMax;
        NSTimeInterval oldest = DBL_MAX;

        for (BrowserTabController *controller in [self registeredControllers]) {
            BOOL isNonKey = (controller != keyController);
            for (BrowserTab *tab in controller.mutableTabs) {
                if (!BrowserTabIsEligibleForBudgetHibernation(tab, controller.selectedTab, now)) {
                    continue;
                }
                NSInteger rank = [self hibernationVictimRankForTab:tab isNonKeyWindow:isNonKey];
                NSTimeInterval interaction = BrowserTabLastInteractionTimestamp(tab);
                if (victim == nil ||
                    rank < bestRank ||
                    (rank == bestRank && interaction < oldest)) {
                    victim = tab;
                    victimController = controller;
                    bestRank = rank;
                    oldest = interaction;
                }
            }
        }

        if (!victim) {
            break;
        }
        [victim hibernate];
        changed = YES;
        (void)victimController;
    }
    return changed;
}

- (BOOL)enforceLiveWebViewBudget {
    NSUInteger live = [self liveWebViewCount];
    if (live <= kMaxLiveWebViews) {
        return NO;
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableArray<BrowserTab *> *candidates = [NSMutableArray array];
    for (BrowserTab *tab in self.mutableTabs) {
        if (!BrowserTabIsEligibleForBudgetHibernation(tab, self.selectedTab, now)) {
            continue;
        }
        [candidates addObject:tab];
    }
    if (candidates.count == 0) {
        return NO;
    }
    [candidates sortUsingComparator:^NSComparisonResult(BrowserTab *a, BrowserTab *b) {
        BOOL aProtected = [BrowserRiskHostPolicy URLIsHibernationProtected:(a.webView.URL ?: a.restorableURL)];
        BOOL bProtected = [BrowserRiskHostPolicy URLIsHibernationProtected:(b.webView.URL ?: b.restorableURL)];
        if (aProtected != bProtected) {
            // 非保护排前（先休眠）。
            return aProtected ? NSOrderedDescending : NSOrderedAscending;
        }
        if (a.mediaHeavy != b.mediaHeavy) {
            // mediaHeavy 排前（先休眠）。
            return a.mediaHeavy ? NSOrderedAscending : NSOrderedDescending;
        }
        NSTimeInterval aInteraction = BrowserTabLastInteractionTimestamp(a);
        NSTimeInterval bInteraction = BrowserTabLastInteractionTimestamp(b);
        if (aInteraction < bInteraction) {
            return NSOrderedAscending;
        }
        if (aInteraction > bInteraction) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    BOOL changed = NO;
    for (BrowserTab *tab in candidates) {
        if ([self liveWebViewCount] <= kMaxLiveWebViews) {
            break;
        }
        [tab hibernate];
        changed = YES;
    }
    return changed;
}

- (void)notifyChange {
    [self.delegate tabControllerDidChange:self];
}

@end
