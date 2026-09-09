#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserRiskHostPolicy.h"
#import "BrowsingPreferences.h"
#import "BrowserTabUIDiagnostics.h"
#import "BrowserUserActivityMonitor.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

static const NSUInteger kRecentlyClosedTabLimit = 20;
static const NSUInteger kMaxLiveWebViews = 8;
static const NSUInteger kMaxLiveWebViewsGlobal = 12;
/// 空闲回收时把后台 live 压到此水位（活跃期不压）。
static const NSUInteger kLiveWebViewsIdleTarget = 4;
static const NSTimeInterval kHibernateIdleSeconds = 600.0; // 10 minutes
static const NSTimeInterval kHibernateIdleSecondsMediaHeavy = 90.0;
static const NSTimeInterval kHibernateCheckInterval = 30.0;
/// 单标签宽限期：仅在「空闲回收」路径里与预算一起考虑；活跃期整体跳过回收。
static const NSTimeInterval kHibernateGraceSeconds = 120.0;
/// 切标签后延迟检查预算；真正执行仍需已进入空闲。
static const NSTimeInterval kBudgetEnforcementDelaySeconds = 5.0;

static NSTimeInterval BrowserTabLastInteractionTimestamp(BrowserTab *tab) {
    return MAX(tab.lastActiveTimestamp, tab.lastDeactivatedTimestamp);
}

static BOOL BrowserTabIsWithinHibernationGrace(BrowserTab *tab, NSTimeInterval now) {
    return (now - BrowserTabLastInteractionTimestamp(tab)) < kHibernateGraceSeconds;
}

/// ignoreGrace=YES：硬回收（仍跳过选中 / NTP / resistsHibernation）。
static BOOL BrowserTabIsEligibleForBudgetHibernation(BrowserTab *tab,
                                                     BrowserTab *selectedTab,
                                                     NSTimeInterval now,
                                                     BOOL ignoreGrace) {
    if (tab == selectedTab || tab.webView == nil || tab.isNewTabPage || tab.resistsHibernation) {
        return NO;
    }
    if (!ignoreGrace && BrowserTabIsWithinHibernationGrace(tab, now)) {
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
    CFTimeInterval t0 = CACurrentMediaTime();
    BrowserTab *tab = [BrowserTab tabWithConfiguration:self.configuration];
    [tab loadNewTabPage];
    [self.mutableTabs addObject:tab];
    // 活跃期不强制回收；空闲后由 evaluateHibernation / deferred budget 再压水位。
    [self selectTabInternal:tab notify:YES];
    NSTimeInterval ms = (CACurrentMediaTime() - t0) * 1000.0;
    BrowserTabUILog(@"addNewTab total=%.1fms tabs=%lu live=%lu/%lu active=%d idleForReclaim=%d",
                    ms,
                    (unsigned long)self.mutableTabs.count,
                    (unsigned long)[self liveWebViewCount],
                    (unsigned long)[[self class] globalLiveWebViewCount],
                    BrowserUserActivityMonitor.sharedMonitor.userActivelyBrowsing ? 1 : 0,
                    BrowserUserActivityMonitor.sharedMonitor.idleForReclaim ? 1 : 0);
    BrowserTabUILogInventory(self.tabs,
                             self.selectedTab,
                             [self liveWebViewCount],
                             [[self class] globalLiveWebViewCount]);
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
    // 不在活跃期抢杀；固定短延迟后检查，若仍活跃则再推迟。
    [self performSelector:@selector(performDeferredBudgetEnforcement)
               withObject:nil
               afterDelay:kBudgetEnforcementDelaySeconds];
}

- (void)performDeferredBudgetEnforcement {
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        BrowserTabUILog(@"budget skip (user active, %.0fs since input) live=%lu — wait for idle",
                        BrowserUserActivityMonitor.sharedMonitor.secondsSinceLastInput,
                        (unsigned long)[self liveWebViewCount]);
        // 不在此处死循环重试；空闲后由 30s hibernate 定时器回收。
        return;
    }

    NSUInteger liveBefore = [self liveWebViewCount];
    NSUInteger globalBefore = [[self class] globalLiveWebViewCount];
    CFTimeInterval t0 = CACurrentMediaTime();
    BOOL changed = NO;
    if ([self enforceLiveWebViewBudget]) {
        changed = YES;
    }
    if ([[self class] enforceGlobalLiveWebViewBudget]) {
        changed = YES;
    }
    // 空闲且仍偏多：再压到更低水位，优先地球/视频。
    if ([self liveWebViewCount] > kLiveWebViewsIdleTarget) {
        if ([self hibernateLiveWebViewsDownTo:kLiveWebViewsIdleTarget ignoringGrace:YES]) {
            changed = YES;
        }
    }
    NSTimeInterval ms = (CACurrentMediaTime() - t0) * 1000.0;
    if (changed || liveBefore > kMaxLiveWebViews || globalBefore > kMaxLiveWebViewsGlobal) {
        BrowserTabUILog(@"budgetEnforcement %.1fms changed=%d live %lu→%lu global %lu→%lu (cap %lu/%lu idle)",
                        ms,
                        changed ? 1 : 0,
                        (unsigned long)liveBefore,
                        (unsigned long)[self liveWebViewCount],
                        (unsigned long)globalBefore,
                        (unsigned long)[[self class] globalLiveWebViewCount],
                        (unsigned long)kMaxLiveWebViews,
                        (unsigned long)kMaxLiveWebViewsGlobal);
        if (changed) {
            BrowserTabUILogInventory(self.tabs,
                                     self.selectedTab,
                                     [self liveWebViewCount],
                                     [[self class] globalLiveWebViewCount]);
        }
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
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        return;
    }

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
        // GPU 重页在「用户空闲」后更快收。
        if ([BrowserRiskHostPolicy URLPrefersEarlyHibernation:protectURL]) {
            idleLimit = MIN(idleLimit, kHibernateIdleSecondsMediaHeavy);
        }
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

    if ([self liveWebViewCount] > kLiveWebViewsIdleTarget) {
        if ([self hibernateLiveWebViewsDownTo:kLiveWebViewsIdleTarget ignoringGrace:YES]) {
            changed = YES;
        }
    }

    if (changed) {
        BrowserTabUILog(@"evaluateHibernation idle reclaim live→%lu",
                        (unsigned long)[self liveWebViewCount]);
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

/// 预算淘汰优先级：GPU 重页优先杀；非保护优先；mediaHeavy 更易被杀；同级再比非 key 窗、再比最久未活动。
+ (NSInteger)hibernationVictimRankForTab:(BrowserTab *)tab isNonKeyWindow:(BOOL)isNonKey {
    NSURL *url = tab.webView.URL ?: tab.restorableURL;
    BOOL early = [BrowserRiskHostPolicy URLPrefersEarlyHibernation:url];
    BOOL protectedHost = [BrowserRiskHostPolicy URLIsHibernationProtected:url];
    // 更大 = 更不宜被杀；选择时取 rank 更小者。
    NSInteger rank = 0;
    if (early) {
        rank -= 50;
    }
    if (protectedHost) {
        rank += 100;
    }
    if (!tab.mediaHeavy) {
        rank += 5;
    } else {
        rank -= 10;
    }
    if (!isNonKey) {
        rank += 10;
    }
    return rank;
}

+ (nullable BrowserTab *)pickGlobalBudgetVictimIgnoringGrace:(BOOL)ignoreGrace
                                                         now:(NSTimeInterval)now {
    BrowserTabController *keyController = [self keyWindowTabController];
    BrowserTab *victim = nil;
    NSInteger bestRank = NSIntegerMax;
    NSTimeInterval oldest = DBL_MAX;

    for (BrowserTabController *controller in [self registeredControllers]) {
        BOOL isNonKey = (controller != keyController);
        for (BrowserTab *tab in controller.mutableTabs) {
            if (!BrowserTabIsEligibleForBudgetHibernation(tab, controller.selectedTab, now, ignoreGrace)) {
                continue;
            }
            NSInteger rank = [self hibernationVictimRankForTab:tab isNonKeyWindow:isNonKey];
            NSTimeInterval interaction = BrowserTabLastInteractionTimestamp(tab);
            if (victim == nil ||
                rank < bestRank ||
                (rank == bestRank && interaction < oldest)) {
                victim = tab;
                bestRank = rank;
                oldest = interaction;
            }
        }
    }
    return victim;
}

+ (BOOL)enforceGlobalLiveWebViewBudget {
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        return NO;
    }
    BOOL changed = NO;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    BOOL ignoreGrace = NO;
    while ([self globalLiveWebViewCount] > kMaxLiveWebViewsGlobal) {
        BrowserTab *victim = [self pickGlobalBudgetVictimIgnoringGrace:ignoreGrace now:now];
        if (!victim && !ignoreGrace) {
            // 软回收无人可杀（多在 120s 宽限内）→ 硬回收，否则 live 会堆到 20+。
            ignoreGrace = YES;
            BrowserTabUILog(@"globalBudget soft empty → hard (ignoreGrace) live=%lu",
                            (unsigned long)[self globalLiveWebViewCount]);
            continue;
        }
        if (!victim) {
            break;
        }
        NSURL *url = victim.webView.URL ?: victim.restorableURL;
        BrowserTabUILog(@"globalBudget hibernate host=%@ mediaHeavy=%d protected=%d hard=%d",
                        url.host ?: @"?",
                        victim.mediaHeavy ? 1 : 0,
                        [BrowserRiskHostPolicy URLIsHibernationProtected:url] ? 1 : 0,
                        ignoreGrace ? 1 : 0);
        [victim hibernate];
        changed = YES;
    }
    return changed;
}

- (NSArray<BrowserTab *> *)budgetHibernationCandidatesIgnoringGrace:(BOOL)ignoreGrace
                                                                now:(NSTimeInterval)now {
    NSMutableArray<BrowserTab *> *candidates = [NSMutableArray array];
    for (BrowserTab *tab in self.mutableTabs) {
        if (!BrowserTabIsEligibleForBudgetHibernation(tab, self.selectedTab, now, ignoreGrace)) {
            continue;
        }
        [candidates addObject:tab];
    }
    [candidates sortUsingComparator:^NSComparisonResult(BrowserTab *a, BrowserTab *b) {
        BOOL aEarly = [BrowserRiskHostPolicy URLPrefersEarlyHibernation:(a.webView.URL ?: a.restorableURL)];
        BOOL bEarly = [BrowserRiskHostPolicy URLPrefersEarlyHibernation:(b.webView.URL ?: b.restorableURL)];
        if (aEarly != bEarly) {
            // GPU 重页排前（先休眠）。
            return aEarly ? NSOrderedAscending : NSOrderedDescending;
        }
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
    return candidates;
}

- (void)logBudgetEligibilitySkipReasonsNow:(NSTimeInterval)now {
    if (!BrowserTabUIDiagnosticsEnabled()) {
        return;
    }
    NSUInteger grace = 0;
    NSUInteger protectedHost = 0;
    NSUInteger resists = 0;
    NSUInteger noView = 0;
    for (BrowserTab *tab in self.mutableTabs) {
        if (tab == self.selectedTab) {
            continue;
        }
        if (tab.webView == nil || tab.isNewTabPage) {
            noView++;
            continue;
        }
        if (tab.resistsHibernation) {
            resists++;
        }
        if (BrowserTabIsWithinHibernationGrace(tab, now)) {
            grace++;
        }
        NSURL *url = tab.webView.URL ?: tab.restorableURL;
        if ([BrowserRiskHostPolicy URLIsHibernationProtected:url]) {
            protectedHost++;
        }
    }
    BrowserTabUILog(@"budget skipReasons grace=%lu protected=%lu resists=%lu noViewOrNtp=%lu (soft needs !grace)",
                    (unsigned long)grace,
                    (unsigned long)protectedHost,
                    (unsigned long)resists,
                    (unsigned long)noView);
}

- (BOOL)hibernateLiveWebViewsDownTo:(NSUInteger)target ignoringGrace:(BOOL)ignoreGrace {
    if ([self liveWebViewCount] <= target) {
        return NO;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSArray<BrowserTab *> *candidates = [self budgetHibernationCandidatesIgnoringGrace:ignoreGrace now:now];
    if (candidates.count == 0 && !ignoreGrace) {
        candidates = [self budgetHibernationCandidatesIgnoringGrace:YES now:now];
        ignoreGrace = YES;
    }
    BOOL changed = NO;
    for (BrowserTab *tab in candidates) {
        if ([self liveWebViewCount] <= target) {
            break;
        }
        NSURL *url = tab.webView.URL ?: tab.restorableURL;
        BrowserTabUILog(@"uiHeadroom hibernate host=%@ early=%d mediaHeavy=%d hard=%d target=%lu",
                        url.host ?: @"?",
                        [BrowserRiskHostPolicy URLPrefersEarlyHibernation:url] ? 1 : 0,
                        tab.mediaHeavy ? 1 : 0,
                        ignoreGrace ? 1 : 0,
                        (unsigned long)target);
        [tab hibernate];
        changed = YES;
    }
    return changed;
}

- (void)reclaimLiveWebViewsForUIResponsiveness {
    // 保留 API：仅空闲时压水位；活跃期 no-op。
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        return;
    }
    NSUInteger live = [self liveWebViewCount];
    if (live <= kLiveWebViewsIdleTarget) {
        return;
    }
    CFTimeInterval t0 = CACurrentMediaTime();
    BOOL changed = [self hibernateLiveWebViewsDownTo:kLiveWebViewsIdleTarget ignoringGrace:YES];
    BrowserTabUILog(@"uiHeadroom reclaim %.1fms changed=%d live %lu→%lu (target %lu)",
                    (CACurrentMediaTime() - t0) * 1000.0,
                    changed ? 1 : 0,
                    (unsigned long)live,
                    (unsigned long)[self liveWebViewCount],
                    (unsigned long)kLiveWebViewsIdleTarget);
}

+ (void)reclaimBeforeCreatingWebViewIfNeeded {
    // 活跃期不杀页抢名额（避免切标签/点快捷方式时突然丢地球）。
    // 空闲后再由预算与 evaluateHibernation 回收。
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        return;
    }
    BrowserTabController *controller = [self keyWindowTabController];
    if (controller == nil) {
        if ([self globalLiveWebViewCount] > kMaxLiveWebViewsGlobal) {
            (void)[self enforceGlobalLiveWebViewBudget];
        }
        return;
    }
    NSUInteger live = [controller liveWebViewCount];
    if (live < kMaxLiveWebViews) {
        return;
    }
    NSUInteger target = kMaxLiveWebViews > 0 ? (kMaxLiveWebViews - 1) : 0;
    CFTimeInterval t0 = CACurrentMediaTime();
    BOOL changed = [controller hibernateLiveWebViewsDownTo:target ignoringGrace:YES];
    BrowserTabUILog(@"preCreateWebView reclaim %.1fms changed=%d live %lu→%lu",
                    (CACurrentMediaTime() - t0) * 1000.0,
                    changed ? 1 : 0,
                    (unsigned long)live,
                    (unsigned long)[controller liveWebViewCount]);
}

- (BOOL)enforceLiveWebViewBudget {
    if (!BrowserUserActivityMonitor.sharedMonitor.idleForReclaim) {
        return NO;
    }
    NSUInteger live = [self liveWebViewCount];
    if (live <= kMaxLiveWebViews) {
        return NO;
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    BOOL ignoreGrace = NO;
    NSArray<BrowserTab *> *candidates = [self budgetHibernationCandidatesIgnoringGrace:NO now:now];
    if (candidates.count == 0) {
        [self logBudgetEligibilitySkipReasonsNow:now];
        ignoreGrace = YES;
        candidates = [self budgetHibernationCandidatesIgnoringGrace:YES now:now];
        BrowserTabUILog(@"windowBudget soft empty → hard candidates=%lu live=%lu",
                        (unsigned long)candidates.count,
                        (unsigned long)live);
    }
    if (candidates.count == 0) {
        return NO;
    }

    BOOL changed = NO;
    for (BrowserTab *tab in candidates) {
        if ([self liveWebViewCount] <= kMaxLiveWebViews) {
            break;
        }
        NSURL *url = tab.webView.URL ?: tab.restorableURL;
        BrowserTabUILog(@"windowBudget hibernate host=%@ mediaHeavy=%d protected=%d hard=%d",
                        url.host ?: @"?",
                        tab.mediaHeavy ? 1 : 0,
                        [BrowserRiskHostPolicy URLIsHibernationProtected:url] ? 1 : 0,
                        ignoreGrace ? 1 : 0);
        [tab hibernate];
        changed = YES;
    }
    return changed;
}

- (void)notifyChange {
    [self.delegate tabControllerDidChange:self];
}

@end
