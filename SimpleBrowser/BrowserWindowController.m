#import "BrowserWindowController.h"
#import "SBTextField.h"
#import "BrowsingPreferences.h"
#import "BrowserMenus.h"
#import "BrowserTabController.h"
#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"
#import "BrowserLaunchpadView.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate, BrowserLaunchpadViewDelegate, NSWindowDelegate>
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) BrowserLaunchpadView *launchpadView;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, strong) SBTextField *addressField;
@property (nonatomic, strong) WKWebViewConfiguration *webViewConfiguration;
@end

@implementation BrowserWindowController

- (WKWebView *)webView {
    return self.tabController.selectedTab.webView;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1024, 700);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SimpleBrowser";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(640, 480);

    self = [super initWithWindow:window];
    if (self) {
        [self configureChromeWindow];
        _webViewConfiguration = [[WKWebViewConfiguration alloc] init];
        _tabController = [[BrowserTabController alloc] initWithConfiguration:_webViewConfiguration];
        _tabController.delegate = self;
        [self setupUI];
        [BrowserMenus installTabMenuForTarget:self];
        [self setupInitialTabs];
    }
    return self;
}

#pragma mark - UI Setup

- (void)configureChromeWindow {
    NSWindow *window = self.window;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    if (@available(macOS 11.0, *)) {
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        window.toolbar = nil;
    }
    window.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scheduleTrafficLightPositioning)
                                                 name:NSWindowDidResizeNotification
                                               object:window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scheduleTrafficLightPositioning)
                                                 name:NSWindowDidMoveNotification
                                               object:window];
}

/// 相对标签栏垂直中心的额外下移量（pt），正值表示向标题栏底部方向移动。
static const CGFloat kTrafficLightDownwardOffset = 1.0;

- (BOOL)positionTrafficLightButtons {
    NSWindow *window = self.window;
    if (!window || !window.isVisible) {
        return NO;
    }

    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    if (!closeButton || !closeButton.superview || !self.tabStripView.superview) {
        return NO;
    }

    [window.contentView layoutSubtreeIfNeeded];
    [self.tabStripView layoutSubtreeIfNeeded];

    if (NSHeight(self.tabStripView.bounds) < BrowserTabStripHeight - 0.5 ||
        NSHeight(self.tabStripView.frame) < BrowserTabStripHeight - 0.5) {
        return NO;
    }

    NSView *container = closeButton.superview;
    NSPoint tabCenterInContainer = [self.tabStripView convertPoint:NSMakePoint(NSMidX(self.tabStripView.bounds),
                                                                              NSMidY(self.tabStripView.bounds))
                                                            toView:container];
    CGFloat targetCenterY = tabCenterInContainer.y;
    if (container.isFlipped) {
        targetCenterY += kTrafficLightDownwardOffset;
    } else {
        targetCenterY -= kTrafficLightDownwardOffset;
    }

    static const NSWindowButton kWindowButtons[] = {
        NSWindowCloseButton,
        NSWindowMiniaturizeButton,
        NSWindowZoomButton,
    };

    for (NSUInteger i = 0; i < sizeof(kWindowButtons) / sizeof(kWindowButtons[0]); i++) {
        NSButton *button = [window standardWindowButton:kWindowButtons[i]];
        if (!button) {
            continue;
        }
        NSRect frame = button.frame;
        frame.origin.y = targetCenterY - NSHeight(frame) / 2.0;
        button.frame = frame;
    }
    return YES;
}

- (void)repositionTrafficLightButtonsAfterLayout {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self positionTrafficLightButtons];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self positionTrafficLightButtons];
        });
    });
}

- (void)setDisplayedWindowTitle:(NSString *)title {
    NSString *resolved = title.length > 0 ? title : @"SimpleBrowser";
    self.window.title = resolved;
    [self repositionTrafficLightButtonsAfterLayout];
}

- (void)scheduleTrafficLightPositioning {
    [self tryPositionTrafficLightsStartingAtAttempt:0];

    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayMs in @[@50, @150, @350]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs.doubleValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf positionTrafficLightButtons];
        });
    }
}

- (void)tryPositionTrafficLightsStartingAtAttempt:(NSInteger)attempt {
    if ([self positionTrafficLightButtons]) {
        return;
    }
    if (attempt >= 40) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf tryPositionTrafficLightsStartingAtAttempt:attempt + 1];
    });
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (notification.object == self.window) {
        [self scheduleTrafficLightPositioning];
    }
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self scheduleTrafficLightPositioning];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self scheduleTrafficLightPositioning];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    self.tabStripView = [[BrowserTabStripView alloc] initWithFrame:NSZeroRect];
    self.tabStripView.delegate = self;
    [self.tabStripView setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationVertical];
    [self.tabStripView setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                               forOrientation:NSLayoutConstraintOrientationVertical];

    self.backButton = [self toolbarIconButtonWithSymbol:@"chevron.left"
                                                toolTip:@"后退"
                                                 action:@selector(goBack:)];
    self.forwardButton = [self toolbarIconButtonWithSymbol:@"chevron.right"
                                                   toolTip:@"前进"
                                                    action:@selector(goForward:)];
    self.reloadButton = [self toolbarIconButtonWithSymbol:@"arrow.clockwise"
                                                  toolTip:@"刷新"
                                                   action:@selector(reloadPage:)];
    self.reloadButton.keyEquivalent = @"r";
    self.reloadButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    NSStackView *navButtons = [NSStackView stackViewWithViews:@[
        self.backButton, self.forwardButton, self.reloadButton
    ]];
    navButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    navButtons.spacing = 2;
    navButtons.translatesAutoresizingMaskIntoConstraints = NO;

    self.addressField = [SBTextField standardField];
    self.addressField.placeholderString = @"输入网址";
    self.addressField.delegate = self;
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addressField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.bookmarkButton = [self makeBookmarkButton];
    [self.addressField addSubview:self.bookmarkButton];
    self.addressField.trailingContentInset = 22;
    [NSLayoutConstraint activateConstraints:@[
        [self.bookmarkButton.trailingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:-6],
        [self.bookmarkButton.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
    ]];

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[
        navButtons, self.addressField
    ]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 10;
    toolbar.edgeInsets = NSEdgeInsetsMake(6, 8, 8, 8);
    toolbar.distribution = NSStackViewDistributionFill;
    [toolbar setContentHuggingPriority:NSLayoutPriorityRequired
                        forOrientation:NSLayoutConstraintOrientationVertical];
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;

    self.contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [self.contentContainer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationVertical];

    self.launchpadView = [[BrowserLaunchpadView alloc] initWithFrame:NSZeroRect];
    self.launchpadView.delegate = self;
    self.launchpadView.hidden = YES;
    self.launchpadView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.launchpadView];

    [NSLayoutConstraint activateConstraints:@[
        [self.launchpadView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.launchpadView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.launchpadView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.launchpadView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];

    NSStackView *rootStack = [NSStackView stackViewWithViews:@[
        self.tabStripView, toolbar, self.contentContainer
    ]];
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 0;
    rootStack.distribution = NSStackViewDistributionFill;

    NSView *contentView = self.window.contentView;
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.tabStripView.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],
        [rootStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [rootStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [rootStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [rootStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];
}

- (NSImage *)toolbarSymbolImageNamed:(NSString *)symbolName {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:15
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (NSButton *)toolbarIconButtonWithSymbol:(NSString *)symbolName
                                  toolTip:(NSString *)toolTip
                                   action:(SEL)action {
    NSImage *image = [self toolbarSymbolImageNamed:symbolName];
    NSButton *button = image ? [NSButton buttonWithImage:image target:self action:action]
                             : [NSButton buttonWithTitle:@"?" target:self action:action];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = toolTip;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:28],
        [button.heightAnchor constraintEqualToConstant:28],
    ]];
    return button;
}

- (NSButton *)makeBookmarkButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.target = self;
    button.action = @selector(toggleBookmark:);
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"添加到起始页快捷方式";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:16],
        [button.heightAnchor constraintEqualToConstant:16],
    ]];
    NSImage *image = [self bookmarkSymbolImageNamed:@"star" filled:NO];
    if (image) {
        button.image = image;
    }
    return button;
}

- (NSImage *)bookmarkSymbolImageNamed:(NSString *)symbolName filled:(BOOL)filled {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:11
                                                            weight:(filled ? NSFontWeightSemibold : NSFontWeightRegular)
                                                             scale:NSImageSymbolScaleSmall];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:@"收藏"];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (void)setBookmarkButtonFilled:(BOOL)filled enabled:(BOOL)enabled {
    self.bookmarkButton.enabled = enabled;
    NSString *symbolName = filled ? @"star.fill" : @"star";
    NSImage *image = [self bookmarkSymbolImageNamed:symbolName filled:filled];
    if (image) {
        self.bookmarkButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        if (!enabled) {
            self.bookmarkButton.contentTintColor = [NSColor tertiaryLabelColor];
        } else if (filled) {
            self.bookmarkButton.contentTintColor = [NSColor systemYellowColor];
        } else {
            self.bookmarkButton.contentTintColor = [NSColor secondaryLabelColor];
        }
    }
    self.bookmarkButton.toolTip = filled ? @"从起始页快捷方式中移除" : @"添加到起始页快捷方式";
}

- (void)updateBookmarkButtonState {
    BrowserTab *tab = self.tabController.selectedTab;
    NSURL *url = self.webView.URL;
    BOOL canBookmark = tab && !tab.isNewTabPage && [BrowsingPreferences isPersistableURL:url];
    if (!canBookmark) {
        [self setBookmarkButtonFilled:NO enabled:NO];
        return;
    }

    NSString *normalized = [BrowserShortcutStore normalizedURLStringFromInput:url.absoluteString];
    BOOL bookmarked = normalized ? [BrowserShortcutStore isURLStringBookmarked:normalized] : NO;
    [self setBookmarkButtonFilled:bookmarked enabled:YES];
}

- (void)toggleBookmark:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    NSURL *url = self.webView.URL;
    if (!tab || tab.isNewTabPage || ![BrowsingPreferences isPersistableURL:url]) {
        return;
    }

    NSString *urlString = [BrowserShortcutStore normalizedURLStringFromInput:url.absoluteString];
    if (!urlString) {
        return;
    }

    NSMutableArray<BrowserShortcutItem *> *shortcuts = [[BrowserShortcutStore loadShortcuts] mutableCopy];
    BrowserShortcutItem *existing = [BrowserShortcutStore shortcutItemMatchingURLString:urlString
                                                                             inShortcuts:shortcuts];
    if (existing) {
        [BrowserShortcutStore removeShortcutWithID:existing.itemID fromShortcuts:shortcuts];
    } else {
        NSString *title = self.webView.title.length > 0 ? self.webView.title : (url.host ?: urlString);
        [BrowserShortcutStore addShortcutWithTitle:title
                                       urlString:urlString
                                   iconURLString:@""
                                     toShortcuts:shortcuts];
    }

    if (!self.launchpadView.hidden) {
        [self.launchpadView reloadShortcuts];
    }
    [self updateBookmarkButtonState];
}

- (void)setupInitialTabs {
    NSArray<NSString *> *entries = [BrowsingPreferences savedTabEntries];
    if (entries.count > 0) {
        NSInteger index = [BrowsingPreferences savedSelectedTabIndex];
        [self.tabController restoreTabsFromEntries:entries selectedIndex:index];
    } else {
        [self.tabController addNewTab];
    }
}

#pragma mark - Tab Management

- (void)attachWebViewForTab:(BrowserTab *)tab {
    WKWebView *webView = tab.webView;
    if (webView.superview == self.contentContainer) {
        return;
    }

    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    [self.contentContainer addSubview:webView];

    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
}

- (void)refreshTabsUI {
    BrowserTab *selectedTab = self.tabController.selectedTab;
    for (BrowserTab *tab in self.tabController.tabs) {
        [self attachWebViewForTab:tab];
        BOOL isSelected = (tab == selectedTab);
        if (tab.isNewTabPage) {
            tab.webView.hidden = YES;
        } else {
            tab.webView.hidden = !isSelected;
        }
    }

    BOOL showLaunchpad = selectedTab.isNewTabPage;
    self.launchpadView.hidden = !showLaunchpad;
    if (showLaunchpad) {
        [self.launchpadView reloadShortcuts];
    }

    [self reloadTabStrip];
    [self updateNavigationState];
}

- (void)reloadTabStrip {
    [self.tabStripView reloadWithTabs:self.tabController.tabs
                        selectedTabID:self.tabController.selectedTab.tabID];
    [self repositionTrafficLightButtonsAfterLayout];
}

- (void)persistTabSession {
    NSMutableArray<NSString *> *entries = [[NSMutableArray alloc] init];
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab.isNewTabPage) {
            [entries addObject:BrowserTabSessionNewTabMarker];
        } else if ([BrowsingPreferences isPersistableURL:tab.webView.URL]) {
            [entries addObject:tab.webView.URL.absoluteString];
        } else {
            [entries addObject:BrowserTabSessionNewTabMarker];
        }
    }

    NSInteger selectedIndex = [self.tabController indexOfSelectedTab];
    if (selectedIndex == NSNotFound) {
        selectedIndex = 0;
    }
    [BrowsingPreferences saveTabEntries:entries selectedIndex:selectedIndex];
}

- (nullable BrowserTab *)tabForID:(NSUUID *)tabID {
    for (BrowserTab *tab in self.tabController.tabs) {
        if ([tab.tabID isEqual:tabID]) {
            return tab;
        }
    }
    return nil;
}

#pragma mark - BrowserTabControllerDelegate

- (void)tabControllerDidChange:(id)controller {
    (void)controller;
    [self refreshTabsUI];
    [self persistTabSession];
}

- (void)tabControllerRequestsCloseWindow:(id)controller {
    (void)controller;
    [self.window close];
}

#pragma mark - BrowserTabStripViewDelegate

- (void)tabStripView:(id)stripView didSelectTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController selectTab:tab];
    }
}

- (void)tabStripView:(id)stripView didCloseTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController closeTab:tab];
    }
}

- (void)tabStripViewDidRequestNewTab:(id)stripView {
    (void)stripView;
    [self.tabController addNewTab];
}

- (void)tabStripViewDidDoubleClickTitleBar:(BrowserTabStripView *)stripView {
    (void)stripView;
    [self.window performZoom:nil];
}

#pragma mark - BrowserLaunchpadViewDelegate

- (void)launchpadView:(BrowserLaunchpadView *)view openURL:(NSURL *)url {
    (void)view;
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab) {
        [tab loadURL:url];
        [self refreshTabsUI];
    }
}

- (void)launchpadView:(BrowserLaunchpadView *)view openURLInNewTab:(NSURL *)url {
    (void)view;
    [self.tabController addTabWithURL:url];
}

#pragma mark - Tab Menu Actions

- (void)newBrowserTab:(id)sender {
    (void)sender;
    [self.tabController addNewTab];
}

- (void)closeBrowserTab:(id)sender {
    (void)sender;
    [self.tabController closeSelectedTab];
}

- (void)selectNextBrowserTab:(id)sender {
    (void)sender;
    [self.tabController selectNextTab];
}

- (void)selectPreviousBrowserTab:(id)sender {
    (void)sender;
    [self.tabController selectPreviousTab];
}

#pragma mark - Navigation Actions

- (void)goBack:(id)sender {
    (void)sender;
    [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    [self.webView goForward];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    [self.webView reload];
}

- (void)loadAddressBarURL {
    NSString *input = self.addressField.stringValue;
    NSURL *url = [self normalizedURLFromString:input];
    if (!url) {
        [self showErrorWithTitle:@"无效的地址" message:@"请输入有效的网址，例如 example.com 或 https://example.com"];
        return;
    }

    BrowserTab *tab = self.tabController.selectedTab;
    if (tab) {
        [tab loadURL:url];
        [self refreshTabsUI];
    }
}

- (nullable NSURL *)normalizedURLFromString:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    BOOL looksLikeURL = [trimmed containsString:@"."] &&
                        ![trimmed containsString:@" "] &&
                        ([trimmed hasPrefix:@"http://"] ||
                         [trimmed hasPrefix:@"https://"] ||
                         [trimmed rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]
                                                    options:0
                                                      range:NSMakeRange(0, trimmed.length)].location == NSNotFound);

    if (!looksLikeURL) {
        NSString *encoded = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        if (!encoded) {
            return nil;
        }
        return [NSURL URLWithString:[NSString stringWithFormat:@"https://duckduckgo.com/?q=%@", encoded]];
    }

    NSString *urlString = trimmed;
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        urlString = [@"https://" stringByAppendingString:urlString];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || !url.host) {
        return nil;
    }
    return url;
}

- (void)updateNavigationState {
    WKWebView *webView = self.webView;
    if (!webView) {
        return;
    }

    BrowserTab *tab = self.tabController.selectedTab;
    self.backButton.enabled = tab.isNewTabPage ? NO : webView.canGoBack;
    self.forwardButton.enabled = tab.isNewTabPage ? NO : webView.canGoForward;
    self.reloadButton.enabled = !tab.isNewTabPage;

    NSString *title = tab.displayTitle;
    [self setDisplayedWindowTitle:title];

    if (tab.isNewTabPage) {
        self.addressField.stringValue = @"";
    } else if (webView.URL) {
        self.addressField.stringValue = webView.URL.absoluteString;
    }
    [self updateBookmarkButtonState];
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"确定"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl *)control
      textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control == self.addressField && commandSelector == @selector(insertNewline:)) {
        [self loadAddressBarURL];
        return YES;
    }
    return NO;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = YES;
    [self reloadTabStrip];

    if (webView == self.webView) {
        [self setDisplayedWindowTitle:@"加载中…"];
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self syncFromWebView:webView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self syncFromWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self handleNavigationError:error forWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self handleNavigationError:error forWebView:webView];
}

- (void)syncFromWebView:(WKWebView *)webView {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab) {
        return;
    }

    tab.isLoading = NO;

    if (!tab.isNewTabPage && webView.title.length > 0) {
        tab.title = webView.title;
    }

    if (webView == self.webView) {
        [self updateNavigationState];
    }

    [self reloadTabStrip];
    [self persistTabSession];
}

- (void)handleNavigationError:(NSError *)error forWebView:(WKWebView *)webView {
    if (error.code == NSURLErrorCancelled) {
        return;
    }

    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = NO;
    [self reloadTabStrip];

    if (webView != self.webView) {
        return;
    }
    [self showErrorWithTitle:@"无法加载页面" message:error.localizedDescription];
    [self updateNavigationState];
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)webView;
    (void)configuration;
    (void)windowFeatures;

    if (!navigationAction.targetFrame || !navigationAction.targetFrame.isMainFrame) {
        NSURL *url = navigationAction.request.URL;
        if (url) {
            [self.tabController addTabWithURL:url];
        } else {
            [self.tabController addNewTab];
        }
    }
    return nil;
}

@end
