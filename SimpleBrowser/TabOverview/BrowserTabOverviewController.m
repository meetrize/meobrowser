#import "BrowserTabOverviewController.h"
#import "BrowserTabOverviewView.h"
#import "BrowserTabOverviewCardView.h"
#import "BrowserTabThumbnailCache.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>

@interface BrowserTabOverviewController () <BrowserTabOverviewViewDelegate>
@property (nonatomic, strong, readwrite) BrowserTabOverviewView *overviewView;
@property (nonatomic, weak) NSView *contentContainer;
@property (nonatomic, assign, readwrite, getter=isVisible) BOOL visible;
@property (nonatomic, strong, readwrite) BrowserTabThumbnailCache *thumbnailCache;
@property (nonatomic, copy) NSString *filterQuery;
@property (nonatomic, strong, nullable) NSUUID *focusedTabID;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, strong) NSArray<BrowserTab *> *displayedTabs;
@end

@implementation BrowserTabOverviewController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _thumbnailCache = [BrowserTabThumbnailCache sharedCache];
        _overviewView = [[BrowserTabOverviewView alloc] initWithFrame:NSZeroRect];
        _overviewView.delegate = self;
        _overviewView.translatesAutoresizingMaskIntoConstraints = NO;
        _overviewView.hidden = YES;
        _filterQuery = @"";
        _displayedTabs = @[];
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
}

- (void)installInContentContainer:(NSView *)contentContainer {
    self.contentContainer = contentContainer;
    if (self.overviewView.superview != contentContainer) {
        [self.overviewView removeFromSuperview];
        [contentContainer addSubview:self.overviewView positioned:NSWindowAbove relativeTo:nil];
        [NSLayoutConstraint activateConstraints:@[
            [self.overviewView.topAnchor constraintEqualToAnchor:contentContainer.topAnchor],
            [self.overviewView.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor],
            [self.overviewView.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor],
            [self.overviewView.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor],
        ]];
    }
}

- (void)bringToFront {
    if (self.overviewView.superview) {
        [self.overviewView.superview addSubview:self.overviewView positioned:NSWindowAbove relativeTo:nil];
    } else if (self.contentContainer) {
        [self installInContentContainer:self.contentContainer];
    }
}

- (IBAction)toggleOverview:(id)sender {
    (void)sender;
    if (self.visible) {
        [self hideOverview];
    } else {
        [self showOverview];
    }
}

- (void)showOverview {
    if (self.visible) {
        [self reloadFromTabController];
        [self bringToFront];
        return;
    }

    [self bringToFront];
    self.visible = YES;
    self.overviewView.hidden = NO;
    self.filterQuery = @"";
    self.overviewView.searchField.stringValue = @"";
    self.focusedTabID = self.windowController.tabController.selectedTab.tabID;

    BOOL reduceMotion = NO;
    if (@available(macOS 10.9, *)) {
        reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    }

    [self reloadFromTabController];
    [self installKeyMonitor];
    [self captureLiveThumbnailsAsync];

    if (reduceMotion) {
        self.overviewView.alphaValue = 1.0;
        self.overviewView.layer.transform = CATransform3DIdentity;
    } else {
        self.overviewView.alphaValue = 0.0;
        self.overviewView.layer.transform = CATransform3DMakeScale(0.96, 0.96, 1.0);
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            context.allowsImplicitAnimation = YES;
            self.overviewView.animator.alphaValue = 1.0;
            self.overviewView.layer.transform = CATransform3DIdentity;
        } completionHandler:nil];
    }

    [self updateToolbarButtonAppearance];
}

- (void)hideOverview {
    if (!self.visible && self.overviewView.hidden) {
        return;
    }
    [self uninstallKeyMonitor];
    self.visible = NO;
    [self updateToolbarButtonAppearance];

    BOOL reduceMotion = NO;
    if (@available(macOS 10.9, *)) {
        reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    }

    void (^finish)(void) = ^{
        self.overviewView.hidden = YES;
        self.overviewView.alphaValue = 1.0;
        self.overviewView.layer.transform = CATransform3DIdentity;
        WKWebView *webView = self.windowController.webView;
        if (webView) {
            [self.windowController.window makeFirstResponder:webView];
        }
    };

    if (reduceMotion) {
        finish();
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.15;
            context.allowsImplicitAnimation = YES;
            self.overviewView.animator.alphaValue = 0.0;
        } completionHandler:finish];
    }
}

- (void)updateToolbarButtonAppearance {
    [self.windowController updateTabOverviewButtonAppearance];
}

- (NSArray<BrowserTab *> *)filteredTabs {
    NSArray<BrowserTab *> *tabs = self.windowController.tabController.tabs;
    NSString *query = [self.filterQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        return tabs;
    }
    NSMutableArray<BrowserTab *> *out = [NSMutableArray array];
    NSString *folded = query.lowercaseString;
    for (BrowserTab *tab in tabs) {
        NSString *title = tab.displayTitle.lowercaseString ?: @"";
        NSString *url = tab.currentOrRestorableURL.absoluteString.lowercaseString ?: @"";
        if ([title containsString:folded] || [url containsString:folded]) {
            [out addObject:tab];
        }
    }
    return out;
}

- (void)reloadFromTabController {
    if (!self.visible) {
        return;
    }
    BrowserTabController *tc = self.windowController.tabController;
    [self.overviewView setTabCount:tc.tabs.count];
    self.displayedTabs = [self filteredTabs];
    BOOL empty = self.displayedTabs.count == 0;
    [self.overviewView setEmptyVisible:empty];

    NSUUID *selectedID = tc.selectedTab.tabID;
    if (self.focusedTabID == nil || ![self tabWithID:self.focusedTabID]) {
        self.focusedTabID = selectedID ?: self.displayedTabs.firstObject.tabID;
    }

    NSMutableArray<BrowserTabOverviewCardView *> *cards = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (BrowserTab *tab in self.displayedTabs) {
        BrowserTabOverviewCardView *card = [[BrowserTabOverviewCardView alloc] initWithFrame:NSZeroRect];
        card.tabID = tab.tabID;
        card.pinned = tab.isPinned;
        card.hibernated = tab.isHibernated;
        card.newTabPage = tab.isNewTabPage;
        card.cardSelected = [tab.tabID isEqual:selectedID];
        card.cardFocused = [tab.tabID isEqual:self.focusedTabID];

        NSImage *thumb = [self.thumbnailCache imageForTabID:tab.tabID];
        [card configureWithTitle:tab.displayTitle
                       faviconURL:tab.currentOrRestorableURL
                    thumbnailImage:thumb];

        NSUUID *tabID = tab.tabID;
        card.onSelect = ^{
            [weakSelf selectAndDismissTabID:tabID];
        };
        card.onClose = ^{
            [weakSelf closeTabID:tabID];
        };
        card.contextMenuProvider = ^NSMenu * {
            return [weakSelf contextMenuForTabID:tabID];
        };
        [cards addObject:card];
    }
    [self.overviewView setCardViews:cards];
    [self scrollFocusedCardIntoViewIfNeeded];
}

- (nullable BrowserTab *)tabWithID:(NSUUID *)tabID {
    if (!tabID) {
        return nil;
    }
    for (BrowserTab *tab in self.windowController.tabController.tabs) {
        if ([tab.tabID isEqual:tabID]) {
            return tab;
        }
    }
    return nil;
}

- (void)selectAndDismissTabID:(NSUUID *)tabID {
    BrowserTab *tab = [self tabWithID:tabID];
    if (!tab) {
        return;
    }
    [self.windowController.tabController selectTab:tab];
    [self hideOverview];
}

- (void)closeTabID:(NSUUID *)tabID {
    BrowserTab *tab = [self tabWithID:tabID];
    if (!tab) {
        return;
    }
    NSUInteger before = self.windowController.tabController.tabs.count;
    [self.thumbnailCache removeImageForTabID:tabID];
    [self.windowController.tabController closeTab:tab];
    NSUInteger after = self.windowController.tabController.tabs.count;
    if (after <= 1 || after >= before) {
        // 关到下限或未变：若只剩 1 个则关闭概览
        if (after <= 1) {
            [self hideOverview];
            return;
        }
    }
    if ([self.focusedTabID isEqual:tabID]) {
        self.focusedTabID = self.windowController.tabController.selectedTab.tabID;
    }
    [self reloadFromTabController];
}

- (void)captureLiveThumbnailsAsync {
    for (BrowserTab *tab in self.windowController.tabController.tabs) {
        if (tab.isNewTabPage || tab.webView == nil) {
            continue;
        }
        // 仅已有 WebView 的存活页；不 wake 休眠标签。
        NSUUID *tabID = tab.tabID;
        WKWebView *webView = tab.webView;
        __weak typeof(self) weakSelf = self;
        [self.thumbnailCache captureFromWebView:webView forTabID:tabID completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.visible || !image) {
                return;
            }
            for (BrowserTabOverviewCardView *card in strongSelf.overviewView.cardViews) {
                if ([card.tabID isEqual:tabID]) {
                    [card setThumbnailImage:image];
                    break;
                }
            }
        }];
    }
}

- (void)captureThumbnailForLeavingTabIfNeeded {
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    if (!tab || tab.isNewTabPage || tab.webView == nil) {
        return;
    }
    // 仅当 WebView 仍挂在内容区时截图更可靠。
    if (tab.webView.superview == nil) {
        return;
    }
    [self.thumbnailCache captureFromWebView:tab.webView forTabID:tab.tabID completion:nil];
}

- (void)updateThumbnailForSelectedTabIfVisible {
    if (!self.visible) {
        return;
    }
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    if (!tab || tab.isNewTabPage || tab.webView == nil) {
        return;
    }
    NSUUID *tabID = tab.tabID;
    __weak typeof(self) weakSelf = self;
    [self.thumbnailCache captureFromWebView:tab.webView forTabID:tabID completion:^(NSImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) {
            return;
        }
        for (BrowserTabOverviewCardView *card in strongSelf.overviewView.cardViews) {
            if ([card.tabID isEqual:tabID]) {
                [card setThumbnailImage:image];
                break;
            }
        }
    }];
}

#pragma mark - Keyboard

- (void)installKeyMonitor {
    if (self.localKeyMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                 handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.visible) {
            return event;
        }
        if ([strongSelf handleKeyEvent:event]) {
            return nil;
        }
        return event;
    }];
}

- (void)uninstallKeyMonitor {
    if (self.localKeyMonitor) {
        [NSEvent removeMonitor:self.localKeyMonitor];
        self.localKeyMonitor = nil;
    }
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    // 搜索框编辑中：Esc 退出；其它可打印字符留给输入。
    NSResponder *first = self.windowController.window.firstResponder;
    BOOL inSearch = [first isKindOfClass:[NSTextView class]]
        && [(NSTextView *)first delegate] == (id)self.overviewView.searchField;

    unsigned short keyCode = event.keyCode;
    NSEventModifierFlags mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    if (keyCode == 53) { // Esc
        [self hideOverview];
        return YES;
    }

    if (inSearch) {
        return NO;
    }

    // ⌘W 关闭焦点卡
    if ((mods & NSEventModifierFlagCommand) && !(mods & NSEventModifierFlagShift)
        && [event.charactersIgnoringModifiers isEqualToString:@"w"]) {
        if (self.focusedTabID) {
            [self closeTabID:self.focusedTabID];
        }
        return YES;
    }

    if (keyCode == 51 || keyCode == 117) { // Delete / Forward Delete
        if (self.focusedTabID) {
            [self closeTabID:self.focusedTabID];
        }
        return YES;
    }

    if (keyCode == 36 || keyCode == 76) { // Return / Enter
        if (self.focusedTabID) {
            [self selectAndDismissTabID:self.focusedTabID];
        }
        return YES;
    }

    // Arrow keys: left 123, right 124, down 125, up 126
    if (keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126) {
        [self moveFocusWithKeyCode:keyCode];
        return YES;
    }

    // Printable → focus search and insert
    NSString *chars = event.charactersIgnoringModifiers;
    if (chars.length == 1 && (mods == 0 || mods == NSEventModifierFlagShift)) {
        unichar c = [chars characterAtIndex:0];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]
            || [[NSCharacterSet punctuationCharacterSet] characterIsMember:c]
            || [[NSCharacterSet symbolCharacterSet] characterIsMember:c]
            || c == ' ') {
            [self.overviewView focusSearchField];
            self.overviewView.searchField.stringValue = chars;
            [self tabOverviewView:self.overviewView searchQueryDidChange:chars];
            return YES;
        }
    }
    return NO;
}

- (void)moveFocusWithKeyCode:(unsigned short)keyCode {
    NSArray<BrowserTab *> *tabs = self.displayedTabs;
    if (tabs.count == 0) {
        return;
    }
    NSInteger index = NSNotFound;
    for (NSUInteger i = 0; i < tabs.count; i++) {
        if ([tabs[i].tabID isEqual:self.focusedTabID]) {
            index = (NSInteger)i;
            break;
        }
    }
    if (index == NSNotFound) {
        index = 0;
    }

    CGFloat width = NSWidth(self.overviewView.bounds);
    NSUInteger columns = 2;
    if (width >= 1600) {
        columns = 5;
    } else if (width >= 1100) {
        columns = 4;
    } else if (width >= 720) {
        columns = 3;
    }

    NSInteger next = index;
    if (keyCode == 123) { // left
        next = MAX(0, index - 1);
    } else if (keyCode == 124) { // right
        next = MIN((NSInteger)tabs.count - 1, index + 1);
    } else if (keyCode == 126) { // up
        next = MAX(0, index - (NSInteger)columns);
    } else if (keyCode == 125) { // down
        next = MIN((NSInteger)tabs.count - 1, index + (NSInteger)columns);
    }
    self.focusedTabID = tabs[(NSUInteger)next].tabID;
    [self applyFocusChrome];
    [self scrollFocusedCardIntoViewIfNeeded];
}

- (void)applyFocusChrome {
    NSUUID *selectedID = self.windowController.tabController.selectedTab.tabID;
    for (BrowserTabOverviewCardView *card in self.overviewView.cardViews) {
        card.cardSelected = [card.tabID isEqual:selectedID];
        card.cardFocused = [card.tabID isEqual:self.focusedTabID];
    }
}

- (void)scrollFocusedCardIntoViewIfNeeded {
    for (BrowserTabOverviewCardView *card in self.overviewView.cardViews) {
        if ([card.tabID isEqual:self.focusedTabID]) {
            [card scrollRectToVisible:card.bounds];
            break;
        }
    }
}

#pragma mark - Context menu

- (NSMenu *)contextMenuForTabID:(NSUUID *)tabID {
    BrowserTab *tab = [self tabWithID:tabID];
    if (!tab) {
        return nil;
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"标签页"];
    menu.autoenablesItems = NO;

    NSMenuItem *closeItem = [menu addItemWithTitle:@"关闭标签页"
                                            action:@selector(contextClose:)
                                     keyEquivalent:@""];
    closeItem.target = self;
    closeItem.representedObject = tabID;

    NSMenuItem *closeOthers = [menu addItemWithTitle:@"关闭其他标签页"
                                              action:@selector(contextCloseOthers:)
                                       keyEquivalent:@""];
    closeOthers.target = self;
    closeOthers.representedObject = tabID;
    closeOthers.enabled = self.windowController.tabController.tabs.count > 1;

    NSMenuItem *closeRight = [menu addItemWithTitle:@"关闭右侧标签页"
                                             action:@selector(contextCloseRight:)
                                      keyEquivalent:@""];
    closeRight.target = self;
    closeRight.representedObject = tabID;
    NSInteger idx = [self.windowController.tabController.tabs indexOfObject:tab];
    closeRight.enabled = idx != NSNotFound && (NSUInteger)idx + 1 < self.windowController.tabController.tabs.count;

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *pinTitle = tab.isPinned ? @"取消固定" : @"固定标签页";
    NSMenuItem *pinItem = [menu addItemWithTitle:pinTitle
                                          action:@selector(contextTogglePin:)
                                   keyEquivalent:@""];
    pinItem.target = self;
    pinItem.representedObject = tabID;

    NSURL *url = tab.currentOrRestorableURL;
    if (url.absoluteString.length > 0) {
        NSMenuItem *copy = [menu addItemWithTitle:@"复制链接"
                                           action:@selector(contextCopyLink:)
                                    keyEquivalent:@""];
        copy.target = self;
        copy.representedObject = tabID;
    }
    return menu;
}

- (void)contextClose:(NSMenuItem *)sender {
    [self closeTabID:sender.representedObject];
}

- (void)contextCloseOthers:(NSMenuItem *)sender {
    BrowserTab *tab = [self tabWithID:sender.representedObject];
    if (!tab) {
        return;
    }
    [self.windowController.tabController closeOtherTabsExcept:tab];
    [self reloadFromTabController];
}

- (void)contextCloseRight:(NSMenuItem *)sender {
    BrowserTab *tab = [self tabWithID:sender.representedObject];
    if (!tab) {
        return;
    }
    [self.windowController.tabController closeTabsToTheRightOf:tab];
    [self reloadFromTabController];
}

- (void)contextTogglePin:(NSMenuItem *)sender {
    BrowserTab *tab = [self tabWithID:sender.representedObject];
    if (!tab) {
        return;
    }
    [self.windowController.tabController setTab:tab pinned:!tab.isPinned];
    [self reloadFromTabController];
}

- (void)contextCopyLink:(NSMenuItem *)sender {
    BrowserTab *tab = [self tabWithID:sender.representedObject];
    NSString *url = tab.currentOrRestorableURL.absoluteString;
    if (url.length == 0) {
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:url forType:NSPasteboardTypeString];
}

#pragma mark - BrowserTabOverviewViewDelegate

- (void)tabOverviewViewDidRequestClose:(id)sender {
    (void)sender;
    [self hideOverview];
}

- (void)tabOverviewViewDidRequestNewTab:(id)sender {
    (void)sender;
    [self.windowController.tabController addNewTab];
    self.focusedTabID = self.windowController.tabController.selectedTab.tabID;
    [self reloadFromTabController];
}

- (void)tabOverviewView:(id)sender searchQueryDidChange:(NSString *)query {
    (void)sender;
    self.filterQuery = query ?: @"";
    [self reloadFromTabController];
}

- (void)tabOverviewViewDidClickBackground:(id)sender {
    (void)sender;
    [self hideOverview];
}

@end
