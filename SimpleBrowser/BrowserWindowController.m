#import "BrowserWindowController.h"
#import "SBTextField.h"
#import "BrowsingPreferences.h"
#import "BrowserMenus.h"
#import "BrowserTabController.h"
#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate>
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
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
}

- (void)setupUI {
    self.tabStripView = [[BrowserTabStripView alloc] initWithFrame:NSZeroRect];
    self.tabStripView.delegate = self;
    [self.tabStripView setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationVertical];
    [self.tabStripView setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                               forOrientation:NSLayoutConstraintOrientationVertical];

    self.backButton = [self toolbarButtonWithTitle:@"◀" action:@selector(goBack:)];
    self.forwardButton = [self toolbarButtonWithTitle:@"▶" action:@selector(goForward:)];
    self.reloadButton = [self toolbarButtonWithTitle:@"↻" action:@selector(reloadPage:)];
    self.reloadButton.keyEquivalent = @"r";
    self.reloadButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    self.addressField = [SBTextField standardField];
    self.addressField.placeholderString = @"输入网址";
    self.addressField.delegate = self;
    [self.addressField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[
        self.backButton, self.forwardButton, self.reloadButton, self.addressField
    ]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    toolbar.edgeInsets = NSEdgeInsetsMake(6, 8, 8, 8);
    toolbar.distribution = NSStackViewDistributionFill;
    [toolbar setContentHuggingPriority:NSLayoutPriorityRequired
                        forOrientation:NSLayoutConstraintOrientationVertical];
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;

    self.contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [self.contentContainer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationVertical];

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
        [self.tabStripView.heightAnchor constraintEqualToConstant:40],
        [rootStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [rootStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [rootStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [rootStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];
}

- (NSButton *)toolbarButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
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
        tab.webView.hidden = (tab != selectedTab);
    }

    [self reloadTabStrip];
    [self updateNavigationState];
}

- (void)reloadTabStrip {
    [self.tabStripView reloadWithTabs:self.tabController.tabs
                        selectedTabID:self.tabController.selectedTab.tabID];
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

    self.backButton.enabled = webView.canGoBack;
    self.forwardButton.enabled = webView.canGoForward;

    BrowserTab *tab = self.tabController.selectedTab;
    NSString *title = tab.displayTitle;
    self.window.title = title.length > 0 ? title : @"SimpleBrowser";

    if (tab.isNewTabPage) {
        self.addressField.stringValue = @"";
    } else if (webView.URL) {
        self.addressField.stringValue = webView.URL.absoluteString;
    }
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
        self.window.title = @"加载中…";
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

    if (webView.title.length > 0) {
        tab.title = webView.title;
        tab.isNewTabPage = NO;
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
