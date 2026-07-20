#import "BrowserFindBarController.h"
#import "BrowserFindBarView.h"
#import "BrowserFindEngine.h"
#import "BrowserFindSession.h"
#import "BrowserWindowController.h"
#import "BrowserTab.h"
#import "BrowserTabController.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kFindModeDefaultsKey = @"BrowserFindLastMode";
static NSString * const kFindCaseDefaultsKey = @"BrowserFindLastCaseSensitive";
static const NSTimeInterval kFindDebounceSeconds = 0.1;
static const NSUInteger kSelectionFillMaxLength = 200;

@interface BrowserFindBarController () <BrowserFindBarViewDelegate>
@property (nonatomic, strong, readwrite) BrowserFindBarView *findBarView;
@property (nonatomic, weak) NSView *contentContainer;
@property (nonatomic, strong) NSLayoutConstraint *barTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *barTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *barWidthConstraint;
@property (nonatomic, assign, readwrite, getter=isVisible) BOOL visible;
@property (nonatomic, strong, nullable) dispatch_block_t pendingSearch;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, weak, nullable) BrowserTab *boundTab;
@property (nonatomic, weak, nullable) WKWebView *boundWebView;
@property (nonatomic, assign) CFTimeInterval lastNavigateAt;
@end

@implementation BrowserFindBarController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _findBarView = [[BrowserFindBarView alloc] initWithFrame:NSZeroRect];
        _findBarView.delegate = self;
        _findBarView.translatesAutoresizingMaskIntoConstraints = NO;
        _findBarView.hidden = YES;
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
    if (self.pendingSearch) {
        dispatch_block_cancel(self.pendingSearch);
    }
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [BrowserFindEngine installOnConfiguration:configuration];
}

- (void)installInContentContainer:(NSView *)contentContainer {
    self.contentContainer = contentContainer;
    if (self.findBarView.superview != contentContainer) {
        [self.findBarView removeFromSuperview];
        [contentContainer addSubview:self.findBarView positioned:NSWindowAbove relativeTo:nil];
        self.barTopConstraint = [self.findBarView.topAnchor constraintEqualToAnchor:contentContainer.topAnchor constant:10];
        self.barTrailingConstraint = [self.findBarView.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-12];
        self.barWidthConstraint = [self.findBarView.widthAnchor constraintEqualToConstant:400];
        [NSLayoutConstraint activateConstraints:@[
            self.barTopConstraint,
            self.barTrailingConstraint,
            self.barWidthConstraint,
            [self.findBarView.heightAnchor constraintEqualToConstant:36],
            [self.findBarView.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentContainer.leadingAnchor constant:12],
        ]];
    }
    [self restoreWindowPreferencesIntoBar];
}

- (void)restoreWindowPreferencesIntoBar {
    NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:kFindModeDefaultsKey];
    BOOL caseSensitive = [[NSUserDefaults standardUserDefaults] boolForKey:kFindCaseDefaultsKey];
    [self.findBarView setMode:(mode == BrowserFindModeWildcard) ? BrowserFindModeWildcard : BrowserFindModeLiteral];
    [self.findBarView setCaseSensitive:caseSensitive];
}

- (BOOL)canFindInCurrentPage {
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    if (tab == nil || tab.isNewTabPage) {
        return NO;
    }
    if (tab.webView == nil) {
        [tab wakeFromHibernationIfNeeded];
    }
    return tab.webView != nil;
}

- (BrowserFindSession *)sessionForTab:(BrowserTab *)tab {
    if (!tab.findSession) {
        BrowserFindSession *session = [[BrowserFindSession alloc] init];
        session.mode = self.findBarView.mode;
        session.caseSensitive = self.findBarView.caseSensitive;
        tab.findSession = session;
    }
    return tab.findSession;
}

- (void)bringBarToFront {
    if (self.findBarView.superview) {
        [self.findBarView.superview addSubview:self.findBarView positioned:NSWindowAbove relativeTo:nil];
    } else if (self.contentContainer) {
        [self installInContentContainer:self.contentContainer];
    }
}

- (IBAction)showFindBar:(id)sender {
    (void)sender;
    if (![self canFindInCurrentPage]) {
        return;
    }
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    BrowserFindSession *session = [self sessionForTab:tab];

    if (self.visible) {
        [self.findBarView applySession:session];
        [self.findBarView setFindEnabled:YES];
        [self.findBarView focusAndSelectAll];
        [self bringBarToFront];
        return;
    }

    // 先同步打开，避免等选区 JS 回调导致「点击无反应」。
    [self presentFindBarWithSession:session fillFromSelection:NO];

    WKWebView *webView = tab.webView;
    __weak typeof(self) weakSelf = self;
    [BrowserFindEngine selectionTextInWebView:webView completion:^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.visible) {
            return;
        }
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            return;
        }
        if (trimmed.length > kSelectionFillMaxLength) {
            trimmed = [trimmed substringToIndex:kSelectionFillMaxLength];
        }
        // 仅当用户尚未改词时填入选区。
        NSString *current = [strongSelf.findBarView.queryField.stringValue ?: @""
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (current.length > 0) {
            return;
        }
        BrowserFindSession *liveSession = [strongSelf sessionForTab:strongSelf.windowController.tabController.selectedTab];
        liveSession.query = trimmed;
        [strongSelf.findBarView applySession:liveSession];
        [strongSelf.findBarView focusAndSelectAll];
        [strongSelf performSearchImmediately];
    }];
}

- (IBAction)toggleFindBar:(id)sender {
    (void)sender;
    if (self.visible) {
        [self hideFindBarClearingHighlights:YES];
        return;
    }
    [self showFindBar:sender];
}

- (void)presentFindBarWithSession:(BrowserFindSession *)session fillFromSelection:(BOOL)filled {
    session.mode = self.findBarView.mode;
    session.caseSensitive = self.findBarView.caseSensitive;
    [self bringBarToFront];
    self.visible = YES;
    self.findBarView.hidden = NO;
    self.findBarView.alphaValue = 1;
    [self.findBarView applySession:session];
    [self.findBarView setFindEnabled:YES];
    [self installKeyMonitor];
    [self bindTabState];
    [self.findBarView focusAndSelectAll];
    if (filled || session.query.length > 0) {
        [self performSearchImmediately];
    }
}

- (void)bindTabState {
    self.boundTab = self.windowController.tabController.selectedTab;
    self.boundWebView = self.boundTab.webView;
}

- (void)hideFindBarClearingHighlights:(BOOL)clearHighlights {
    if (!self.visible && self.findBarView.hidden) {
        if (clearHighlights) {
            [self clearHighlightsOnBoundWebView];
        }
        return;
    }
    if (self.pendingSearch) {
        dispatch_block_cancel(self.pendingSearch);
        self.pendingSearch = nil;
    }
    [self uninstallKeyMonitor];
    self.visible = NO;

    WKWebView *webView = self.boundWebView ?: self.windowController.webView;
    BrowserTab *tab = self.boundTab;
    void (^finish)(void) = ^{
        self.findBarView.hidden = YES;
        self.findBarView.alphaValue = 1;
        [self.windowController.window makeFirstResponder:webView];
    };

    if (clearHighlights && webView) {
        [BrowserFindEngine clearInWebView:webView completion:^{
            if (tab.findSession) {
                [tab.findSession resetHighlightsKeepingQuery];
            }
            finish();
        }];
    } else {
        finish();
    }
}

- (void)clearHighlightsOnBoundWebView {
    WKWebView *webView = self.boundWebView ?: self.windowController.webView;
    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    if (!webView) {
        return;
    }
    [BrowserFindEngine clearInWebView:webView completion:^{
        [tab.findSession resetHighlightsKeepingQuery];
    }];
}

- (IBAction)findNext:(id)sender {
    (void)sender;
    if (!self.visible) {
        [self showFindBar:sender];
        return;
    }
    [self navigateMatchForward:YES];
}

- (IBAction)findPrevious:(id)sender {
    (void)sender;
    if (!self.visible) {
        [self showFindBar:sender];
        return;
    }
    [self navigateMatchForward:NO];
}

- (IBAction)useSelectionForFind:(id)sender {
    (void)sender;
    if (![self canFindInCurrentPage]) {
        return;
    }
    WKWebView *webView = self.windowController.webView;
    __weak typeof(self) weakSelf = self;
    [BrowserFindEngine selectionTextInWebView:webView completion:^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            [strongSelf showFindBar:nil];
            return;
        }
        if (trimmed.length > kSelectionFillMaxLength) {
            trimmed = [trimmed substringToIndex:kSelectionFillMaxLength];
        }
        BrowserTab *tab = strongSelf.windowController.tabController.selectedTab;
        BrowserFindSession *session = [strongSelf sessionForTab:tab];
        session.query = trimmed;
        if (!strongSelf.visible) {
            [strongSelf presentFindBarWithSession:session fillFromSelection:YES];
        } else {
            [strongSelf.findBarView applySession:session];
            [strongSelf.findBarView focusAndSelectAll];
            [strongSelf performSearchImmediately];
        }
    }];
}

- (void)syncWithSelectedTab {
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    if (!self.visible) {
        self.boundTab = tab;
        self.boundWebView = tab.webView;
        return;
    }

    if (![self canFindInCurrentPage]) {
        [self hideFindBarClearingHighlights:YES];
        return;
    }

    if (tab == self.boundTab) {
        return;
    }

    // 离开旧标签时清高亮但保留其 session.query
    WKWebView *oldWebView = self.boundWebView;
    if (oldWebView) {
        [BrowserFindEngine clearInWebView:oldWebView completion:nil];
        [self.boundTab.findSession resetHighlightsKeepingQuery];
    }

    self.boundTab = tab;
    self.boundWebView = tab.webView;
    BrowserFindSession *session = [self sessionForTab:tab];
    session.mode = self.findBarView.mode;
    session.caseSensitive = self.findBarView.caseSensitive;
    [self.findBarView applySession:session];
    if (session.query.length > 0) {
        [self performSearchImmediately];
    } else {
        [self.findBarView updateMatchCount:0 total:0 truncated:NO invalid:NO];
        [self.findBarView setNavigationEnabled:NO];
    }
}

- (void)noteNavigationCommittedInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self.windowController.tabController tabForWebView:webView];
    if (!tab) {
        return;
    }
    [BrowserFindEngine clearInWebView:webView completion:nil];
    [tab.findSession resetHighlightsKeepingQuery];
    if (self.visible && tab == self.boundTab) {
        [self.findBarView updateMatchCount:0 total:0 truncated:NO invalid:NO];
        [self.findBarView setNavigationEnabled:NO];
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self.windowController.tabController tabForWebView:webView];
    if (!self.visible || tab != self.boundTab) {
        return;
    }
    self.boundWebView = webView;
    BrowserFindSession *session = tab.findSession;
    if (session.query.length > 0) {
        [self performSearchImmediately];
    }
}

#pragma mark - Search

- (void)scheduleSearch {
    if (self.pendingSearch) {
        dispatch_block_cancel(self.pendingSearch);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf performSearchImmediately];
    });
    self.pendingSearch = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFindDebounceSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)performSearchImmediately {
    self.pendingSearch = nil;
    if (!self.visible || ![self canFindInCurrentPage]) {
        return;
    }
    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    WKWebView *webView = tab.webView;
    BrowserFindSession *session = [self sessionForTab:tab];
    session.query = self.findBarView.queryField.stringValue ?: @"";
    session.mode = self.findBarView.mode;
    session.caseSensitive = self.findBarView.caseSensitive;

    NSString *trimmed = [session.query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [BrowserFindEngine clearInWebView:webView completion:^{
            [session resetHighlightsKeepingQuery];
            [self.findBarView updateMatchCount:0 total:0 truncated:NO invalid:NO];
            [self.findBarView setNavigationEnabled:NO];
        }];
        return;
    }

    [BrowserFindEngine searchInWebView:webView
                                 query:trimmed
                                  mode:session.mode
                         caseSensitive:session.caseSensitive
                            completion:^(BrowserFindResult *result) {
        session.matchCount = result.matchCount;
        session.currentIndex = result.currentIndex;
        session.truncated = result.truncated;
        [self.findBarView updateMatchCount:result.currentIndex
                                     total:result.matchCount
                                 truncated:result.truncated
                                   invalid:result.invalidQuery];
        [self.findBarView setNavigationEnabled:result.matchCount > 0];
    }];
}

/// 下一处 / 上一处：若高亮尚未就绪（防抖未完成）则先同步搜索再跳转。
- (void)navigateMatchForward:(BOOL)forward {
    if (![self canFindInCurrentPage] || !self.visible) {
        return;
    }
    // 防止同一按键被 monitor + 菜单 / Return 委托各处理一次。
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastNavigateAt < 0.12) {
        return;
    }
    self.lastNavigateAt = now;

    if (self.pendingSearch) {
        dispatch_block_cancel(self.pendingSearch);
        self.pendingSearch = nil;
    }

    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    WKWebView *webView = tab.webView ?: self.windowController.webView;
    if (!webView) {
        return;
    }
    BrowserFindSession *session = [self sessionForTab:tab];
    NSString *raw = self.findBarView.queryField.stringValue ?: @"";
    NSString *query = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    session.query = raw;
    session.mode = self.findBarView.mode;
    session.caseSensitive = self.findBarView.caseSensitive;

    if (query.length == 0) {
        return;
    }

    void (^applyResult)(BrowserFindResult *) = ^(BrowserFindResult *result) {
        session.matchCount = result.matchCount;
        session.currentIndex = result.currentIndex;
        session.truncated = result.truncated;
        [self.findBarView updateMatchCount:result.currentIndex
                                     total:result.matchCount
                                 truncated:result.truncated
                                   invalid:result.invalidQuery];
        [self.findBarView setNavigationEnabled:result.matchCount > 0];
        if (result.wrapped) {
            [self.findBarView flashWrapHint];
        }
    };

    void (^step)(void) = ^{
        if (forward) {
            [BrowserFindEngine nextInWebView:webView completion:applyResult];
        } else {
            [BrowserFindEngine previousInWebView:webView completion:applyResult];
        }
    };

    // 已有高亮结果 → 直接跳；否则先 search（落在第 1 处）。
    if (session.matchCount > 0) {
        step();
        return;
    }

    [BrowserFindEngine searchInWebView:webView
                                 query:query
                                  mode:session.mode
                         caseSensitive:session.caseSensitive
                            completion:^(BrowserFindResult *result) {
        applyResult(result);
        if (result.matchCount == 0 || result.invalidQuery) {
            return;
        }
        // 新搜索已停在第 1 处。上一处再 prev 绕到末尾；下一处/回车留在第 1 处。
        if (!forward) {
            step();
        }
    }];
}

- (void)stepForward:(BOOL)forward {
    [self navigateMatchForward:forward];
}

- (void)persistWindowPreferences {
    [[NSUserDefaults standardUserDefaults] setInteger:self.findBarView.mode forKey:kFindModeDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setBool:self.findBarView.caseSensitive forKey:kFindCaseDefaultsKey];
}

#pragma mark - Key monitor (F3 / ⌘G / Return / Esc)

- (void)installKeyMonitor {
    if (self.localKeyMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                 handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handleLocalKeyEvent:event];
    }];
}

- (void)uninstallKeyMonitor {
    if (self.localKeyMonitor) {
        [NSEvent removeMonitor:self.localKeyMonitor];
        self.localKeyMonitor = nil;
    }
}

- (NSEvent *)handleLocalKeyEvent:(NSEvent *)event {
    if (!self.visible || self.windowController.window != NSApp.keyWindow) {
        return event;
    }

    NSEventModifierFlags mods =
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL shift = (mods & NSEventModifierFlagShift) != 0;
    BOOL cmd = (mods & NSEventModifierFlagCommand) != 0;
    BOOL alt = (mods & NSEventModifierFlagOption) != 0;
    BOOL ctrl = (mods & NSEventModifierFlagControl) != 0;

    // Esc
    if (event.keyCode == 53 && !cmd && !alt && !ctrl) {
        [self hideFindBarClearingHighlights:YES];
        return nil;
    }

    // F3 = 99；⇧F3 上一处
    if (event.keyCode == 99 && !cmd && !alt && !ctrl) {
        [self navigateMatchForward:!shift];
        return nil;
    }

    // ⌘G 下一处 / ⌘⇧G 上一处（不依赖菜单响应链，输入框聚焦时也可用）
    if (cmd && !alt && !ctrl) {
        NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
        if ([chars isEqualToString:@"g"]) {
            [self navigateMatchForward:!shift];
            return nil;
        }
    }

    return event;
}

#pragma mark - BrowserFindBarViewDelegate

- (void)findBarViewQueryDidChange:(BrowserFindBarView *)view {
    (void)view;
    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    [self sessionForTab:tab].query = view.queryField.stringValue ?: @"";
    [self scheduleSearch];
}

- (void)findBarViewDidRequestNext:(BrowserFindBarView *)view {
    (void)view;
    [self navigateMatchForward:YES];
}

- (void)findBarViewDidRequestPrevious:(BrowserFindBarView *)view {
    (void)view;
    [self navigateMatchForward:NO];
}

- (void)findBarViewDidToggleMode:(BrowserFindBarView *)view {
    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    [self sessionForTab:tab].mode = view.mode;
    [self persistWindowPreferences];
    [self performSearchImmediately];
}

- (void)findBarViewDidToggleCaseSensitive:(BrowserFindBarView *)view {
    BrowserTab *tab = self.boundTab ?: self.windowController.tabController.selectedTab;
    [self sessionForTab:tab].caseSensitive = view.caseSensitive;
    [self persistWindowPreferences];
    [self performSearchImmediately];
}

- (void)findBarViewDidRequestClose:(BrowserFindBarView *)view {
    (void)view;
    [self hideFindBarClearingHighlights:YES];
}

@end
