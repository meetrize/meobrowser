#import "BrowserWindowController.h"
#import "BrowserAppInfo.h"
#import "SBTextField.h"
#import "BrowsingPreferences.h"
#import "BrowserMenus.h"
#import "BrowserTabController.h"
#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserTabItemView.h"
#import "BrowserLaunchpadView.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"
#import "BrowserAddressBarAutocompleteController.h"
#import "BrowserAddressBarActionGroup.h"
#import "BrowserAddressBarRowView.h"
#import "BrowserDownloadManager.h"
#import "BrowserDownloadPanel.h"
#import "BrowserFaviconService.h"

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate, BrowserLaunchpadViewDelegate, BrowserAddressBarAutocompleteControllerDelegate, BrowserDownloadManagerObserver, BrowserDownloadPanelDelegate, NSWindowDelegate, NSMenuItemValidation>
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) BrowserLaunchpadView *launchpadView;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, strong) NSButton *downloadButton;
@property (nonatomic, strong) NSView *downloadBadgeView;
@property (nonatomic, strong) SBTextField *addressField;
@property (nonatomic, strong) BrowserAddressBarActionGroup *addressBarActionGroup;
@property (nonatomic, strong) BrowserAddressBarRowView *addressBarRow;
@property (nonatomic, strong) BrowserAddressBarAutocompleteController *addressAutocompleteController;
@property (nonatomic, weak) BrowserTab *lastAddressBarTab;
@property (nonatomic, strong) WKWebViewConfiguration *webViewConfiguration;
@property (nonatomic, strong) BrowserDownloadManager *downloadManager;
@property (nonatomic, strong) BrowserDownloadPanel *downloadPanel;
@property (nonatomic, assign) BOOL downloadPanelVisible;
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
    window.title = BrowserAppDisplayName;
    window.releasedWhenClosed = NO;
    // 多标签时由标签条自适应/溢出菜单承接；窗口下限刻意较小以便随时拖窄
    window.minSize = NSMakeSize(400, 300);

    self = [super initWithWindow:window];
    if (self) {
        [self configureChromeWindow];
        _webViewConfiguration = [[WKWebViewConfiguration alloc] init];
        [self configureWebViewConfiguration:_webViewConfiguration];
        _tabController = [[BrowserTabController alloc] initWithConfiguration:_webViewConfiguration];
        _tabController.delegate = self;
        _downloadManager = [[BrowserDownloadManager alloc] init];
        [_downloadManager addObserver:self];
        [self setupUI];
        [BrowserMenus installTabMenuForTarget:self];
        [BrowserMenus installDownloadMenuForTarget:self];
        [BrowserMenus installViewMenuForTarget:self];
        [self setupInitialTabs];
    }
    return self;
}

#pragma mark - UI Setup

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    // WKWebView 默认 UA 不含 Safari 标识，部分站点（如百度）会识别为内嵌 WebView 并反复跳转验证页。
    configuration.applicationNameForUserAgent = @"Version/18.0 Safari/605.1.15";
}

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
    NSString *resolved = title.length > 0 ? title : BrowserAppDisplayName;
    if ([self.window.title isEqualToString:resolved]) {
        return;
    }
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
    [self.addressAutocompleteController uninstall];
    [self.downloadManager removeObserver:self];
    self.downloadPanel.panelDelegate = nil;
    [self.downloadPanel orderOut:nil];
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
    self.addressField.selectsAllOnMouseFocus = YES;
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

    self.addressAutocompleteController = [[BrowserAddressBarAutocompleteController alloc] initWithAddressField:self.addressField];
    self.addressAutocompleteController.delegate = self;
    [self.addressAutocompleteController install];

        self.addressBarActionGroup = [[BrowserAddressBarActionGroup alloc] initWithFrame:NSZeroRect];
    self.addressBarActionGroup.minimumAddressWidth = 120;
    self.downloadButton = self.addressBarActionGroup.downloadButton;
    self.downloadButton.target = self;
    self.downloadButton.action = @selector(toggleDownloadsPanel:);
    [self installDownloadBadgeOnButton:self.downloadButton];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(addressBarActionOrderDidChange:)
                                                 name:@"BrowserAddressBarActionOrderDidChangeNotification"
                                               object:self.addressBarActionGroup];

    self.addressBarRow = [[BrowserAddressBarRowView alloc] initWithAddressField:self.addressField
                                                                  actionGroup:self.addressBarActionGroup];

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[
        navButtons, self.addressBarRow
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
    self.contentContainer.wantsLayer = YES;
    self.contentContainer.clipsToBounds = YES;
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

- (void)installDownloadBadgeOnButton:(NSButton *)button {
    NSView *badge = [[NSView alloc] initWithFrame:NSZeroRect];
    badge.wantsLayer = YES;
    badge.layer.backgroundColor = [NSColor systemRedColor].CGColor;
    badge.layer.cornerRadius = 3.5;
    badge.hidden = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:7],
        [badge.heightAnchor constraintEqualToConstant:7],
        [badge.topAnchor constraintEqualToAnchor:button.topAnchor constant:3],
        [badge.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-3],
    ]];
    self.downloadBadgeView = badge;
}

#pragma mark - Downloads

- (void)addressBarActionOrderDidChange:(NSNotification *)notification {
    (void)notification;
    // 重排后 downloadButton 可能仍是同一实例；角标在该按钮上。刷新引用与外观即可。
    self.downloadButton = self.addressBarActionGroup.downloadButton;
    if (self.downloadButton && self.downloadBadgeView.superview != self.downloadButton) {
        [self.downloadBadgeView removeFromSuperview];
        [self.downloadButton addSubview:self.downloadBadgeView];
        [NSLayoutConstraint activateConstraints:@[
            [self.downloadBadgeView.widthAnchor constraintEqualToConstant:7],
            [self.downloadBadgeView.heightAnchor constraintEqualToConstant:7],
            [self.downloadBadgeView.topAnchor constraintEqualToAnchor:self.downloadButton.topAnchor constant:3],
            [self.downloadBadgeView.trailingAnchor constraintEqualToAnchor:self.downloadButton.trailingAnchor constant:-3],
        ]];
    }
    self.downloadButton.target = self;
    self.downloadButton.action = @selector(toggleDownloadsPanel:);
    [self updateDownloadButtonAppearance];
}

- (void)toggleDownloadsPanel:(id)sender {
    (void)sender;
    if (self.downloadPanelVisible && self.downloadPanel.isVisible) {
        [self.downloadPanel dismissPanel];
        return;
    }
    [self showDownloadsPanel];
}

- (void)showDownloadsPanel {
    if (!self.downloadPanel) {
        self.downloadPanel = [[BrowserDownloadPanel alloc] init];
        self.downloadPanel.panelDelegate = self;
        self.downloadPanel.manager = self.downloadManager;
    }
    [self.downloadManager markAllCompletedAsRead];
    [self updateDownloadButtonAppearance];

    NSRect buttonRect = [self.downloadButton convertRect:self.downloadButton.bounds toView:nil];
    NSRect screenRect = [self.window convertRectToScreen:buttonRect];
    self.downloadPanel.dismissExclusionRectOnScreen = NSInsetRect(screenRect, -4, -4);
    [self.downloadPanel presentAnchoredToRect:screenRect];
    self.downloadPanelVisible = YES;
}

- (void)downloadPanelDidRequestClose:(BrowserDownloadPanel *)panel {
    (void)panel;
    self.downloadPanelVisible = NO;
}

- (void)downloadManagerDidChange:(BrowserDownloadManager *)manager {
    (void)manager;
    [self updateDownloadButtonAppearance];
    if (self.downloadPanelVisible && self.downloadPanel.isVisible) {
        [self.downloadPanel reloadFromManager];
    }
}

- (void)updateDownloadButtonAppearance {
    NSUInteger active = self.downloadManager.activeCount;
    NSUInteger unread = self.downloadManager.unreadCompletedCount;
    BOOL busy = active > 0;

    NSString *symbol = busy ? @"arrow.down.circle.fill" : @"arrow.down.circle";
    NSImage *image = [self toolbarSymbolImageNamed:symbol];
    if (image) {
        self.downloadButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        self.downloadButton.contentTintColor = busy ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }

    self.downloadBadgeView.hidden = (unread == 0);

    if (active > 0) {
        NSInteger pct = (NSInteger)llround(self.downloadManager.aggregateProgress * 100.0);
        self.downloadButton.toolTip = [NSString stringWithFormat:@"下载中（%lu 项 · %ld%%）", (unsigned long)active, (long)pct];
    } else if (unread > 0) {
        self.downloadButton.toolTip = [NSString stringWithFormat:@"下载（%lu 个新完成）", (unsigned long)unread];
    } else {
        self.downloadButton.toolTip = @"下载";
    }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    if (!self.downloadManager.hasActiveDownloads) {
        return YES;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"还有下载正在进行";
    alert.informativeText = [NSString stringWithFormat:@"仍有 %lu 个下载未完成。关闭窗口不会取消已写入磁盘的文件，但进行中的下载会被中断。",
                             (unsigned long)self.downloadManager.activeCount];
    [alert addButtonWithTitle:@"仍然关闭"];
    [alert addButtonWithTitle:@"取消"];
    NSModalResponse response = [alert runModal];
    return response == NSAlertFirstButtonReturn;
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
        // 星标加入后立即返回；图标后台瀑布拉取并回写（不阻塞 ★ 状态）。
        NSString *pageURLForFavicon = urlString;
        __weak typeof(self) weakSelf = self;
        [[BrowserFaviconService sharedService] fetchAndCacheForPageURLString:pageURLForFavicon
                                                             preferredIconURL:nil
                                                                       reason:BrowserFaviconFetchReasonSilent
                                                                   completion:^(NSURL *iconURL, NSImage *image, NSError *error) {
            (void)image;
            (void)error;
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil || iconURL.absoluteString.length == 0) {
                return;
            }
            BOOL updated = [BrowserShortcutStore updateIconURLString:iconURL.absoluteString
                                                  matchingURLString:pageURLForFavicon];
            if (!updated) {
                return;
            }
            if (!strongSelf.launchpadView.hidden) {
                [strongSelf.launchpadView reloadShortcuts];
            }
            [strongSelf.addressAutocompleteController refreshMatchesIfNeeded];
        }];
    }

    if (!self.launchpadView.hidden) {
        [self.launchpadView reloadShortcuts];
    }
    [self.addressAutocompleteController refreshMatchesIfNeeded];
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
    if ([webView isKindOfClass:[BrowserWebView class]]) {
        __weak typeof(self) weakSelf = self;
        ((BrowserWebView *)webView).openURLHandler = ^(NSURL *url) {
            [weakSelf.tabController addTabWithURL:url];
        };
    }

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

- (void)updateTabStripDisplay {
    [self.tabStripView syncWithTabs:self.tabController.tabs
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

- (void)tabStripViewDidDoubleClickTitleBar:(BrowserTabStripView *)stripView {
    (void)stripView;
    [self.window performZoom:nil];
}

#pragma mark - BrowserAddressBarAutocompleteControllerDelegate

- (void)autocompleteController:(BrowserAddressBarAutocompleteController *)controller openURL:(NSURL *)url {
    (void)controller;
    [self launchpadView:self.launchpadView openURL:url];
}

- (void)autocompleteController:(BrowserAddressBarAutocompleteController *)controller openURLInNewTab:(NSURL *)url {
    (void)controller;
    [self launchpadView:self.launchpadView openURLInNewTab:url];
}

- (NSWindow *)windowForAutocompleteController:(BrowserAddressBarAutocompleteController *)controller {
    (void)controller;
    return self.window;
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

- (void)openURLsFromExternalSource:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }

    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];

    BOOL openedAny = NO;
    for (NSURL *url in urls) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL isWebURL = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
        BOOL isFile = url.isFileURL;
        if (!isWebURL && !isFile) {
            continue;
        }
        [self.tabController addTabWithURL:url];
        openedAny = YES;
    }

    if (openedAny) {
        [self refreshTabsUI];
    }
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

#pragma mark - Page Zoom

static const CGFloat kBrowserPageZoomStep = 1.1;
static const CGFloat kBrowserPageZoomMin = 0.5;
static const CGFloat kBrowserPageZoomMax = 3.0;

- (BOOL)canZoomCurrentPage {
    BrowserTab *tab = self.tabController.selectedTab;
    return tab != nil && !tab.isNewTabPage && self.webView != nil;
}

- (void)zoomIn:(id)sender {
    (void)sender;
    if (![self canZoomCurrentPage]) {
        return;
    }
    CGFloat next = self.webView.pageZoom * kBrowserPageZoomStep;
    self.webView.pageZoom = MIN(next, kBrowserPageZoomMax);
}

- (void)zoomOut:(id)sender {
    (void)sender;
    if (![self canZoomCurrentPage]) {
        return;
    }
    CGFloat next = self.webView.pageZoom / kBrowserPageZoomStep;
    self.webView.pageZoom = MAX(next, kBrowserPageZoomMin);
}

- (void)actualSize:(id)sender {
    (void)sender;
    if (![self canZoomCurrentPage]) {
        return;
    }
    self.webView.pageZoom = 1.0;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(zoomIn:) ||
        action == @selector(zoomOut:) ||
        action == @selector(actualSize:)) {
        return [self canZoomCurrentPage];
    }
    return YES;
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
        return [BrowsingPreferences searchURLForQuery:trimmed];
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

- (NSString *)canonicalAddressBarStringForTab:(BrowserTab *)tab {
    if (!tab || tab.isNewTabPage) {
        return @"";
    }
    return tab.webView.URL.absoluteString ?: @"";
}

- (void)persistAddressBarDraftFromField {
    BrowserTab *tab = self.lastAddressBarTab;
    if (!tab) {
        return;
    }
    NSString *current = self.addressField.stringValue ?: @"";
    NSString *canonical = [self canonicalAddressBarStringForTab:tab];
    if ([current isEqualToString:canonical]) {
        tab.addressBarDraft = nil;
    } else {
        tab.addressBarDraft = current;
    }
}

- (void)applyAddressBarStringForTab:(BrowserTab *)tab {
    if (tab.addressBarDraft != nil) {
        self.addressField.stringValue = tab.addressBarDraft;
    } else {
        self.addressField.stringValue = [self canonicalAddressBarStringForTab:tab];
    }
    self.lastAddressBarTab = tab;
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

    [self persistAddressBarDraftFromField];
    [self applyAddressBarStringForTab:tab];
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
    if (control == self.addressField) {
        if ([self.addressAutocompleteController handleCommandBySelector:commandSelector textView:textView]) {
            return YES;
        }
        if (commandSelector == @selector(insertNewline:)) {
            [self loadAddressBarURL];
            return YES;
        }
    }
    return NO;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.targetFrame.isMainFrame) {
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        [tab notePendingMainFrameNavigation];
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    if (@available(macOS 11.3, *)) {
        if ([BrowserDownloadManager shouldDownloadNavigationResponse:navigationResponse]) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView
navigationAction:(WKNavigationAction *)navigationAction
didBecomeDownload:(WKDownload *)download {
    (void)webView;
    (void)navigationAction;
    if (@available(macOS 11.3, *)) {
        [self.downloadManager takeOwnershipOfDownload:download];
        if (!self.downloadPanelVisible) {
            [self showDownloadsPanel];
        }
    }
}

- (void)webView:(WKWebView *)webView
navigationResponse:(WKNavigationResponse *)navigationResponse
didBecomeDownload:(WKDownload *)download {
    (void)webView;
    (void)navigationResponse;
    if (@available(macOS 11.3, *)) {
        [self.downloadManager takeOwnershipOfDownload:download];
        if (!self.downloadPanelVisible) {
            [self showDownloadsPanel];
        }
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab beginMainFrameNavigation:navigation]) {
        return;
    }

    tab.isLoading = YES;
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab isMainFrameNavigation:navigation]) {
        return;
    }
    // URL 在 commit 时已可用；尽早刷新星标，避免等 didFinish。
    if (webView == self.webView) {
        if (tab.addressBarDraft == nil) {
            [self applyAddressBarStringForTab:tab];
        }
        self.backButton.enabled = tab.isNewTabPage ? NO : webView.canGoBack;
        self.forwardButton.enabled = tab.isNewTabPage ? NO : webView.canGoForward;
        self.reloadButton.enabled = !tab.isNewTabPage;
        [self updateBookmarkButtonState];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab isMainFrameNavigation:navigation]) {
        return;
    }
    [tab endMainFrameNavigation:navigation];
    [self syncFromWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self handleNavigationError:error forWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self handleNavigationError:error forWebView:webView];
}

- (void)syncFromWebView:(WKWebView *)webView {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab) {
        return;
    }

    tab.isLoading = NO;
    tab.addressBarDraft = nil;

    if (webView == self.webView) {
        [self applyAddressBarStringForTab:tab];
        self.backButton.enabled = tab.isNewTabPage ? NO : webView.canGoBack;
        self.forwardButton.enabled = tab.isNewTabPage ? NO : webView.canGoForward;
        self.reloadButton.enabled = !tab.isNewTabPage;
        [self updateBookmarkButtonState];
    }

    NSInteger generation = tab.titleUpdateGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf applyTitleFromWebView:webView generation:generation];
    });
}

- (void)applyTitleFromWebView:(WKWebView *)webView generation:(NSInteger)generation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab || tab.titleUpdateGeneration != generation) {
        return;
    }

    BOOL titleChanged = NO;
    if (!tab.isNewTabPage && webView.title.length > 0) {
        NSString *newTitle = webView.title;
        if (![tab.title isEqualToString:newTitle]) {
            tab.title = newTitle;
            titleChanged = YES;
        }
    }

    if (webView == self.webView) {
        [self setDisplayedWindowTitle:tab.displayTitle];
    }

    if (titleChanged) {
        [self updateTabStripDisplay];
    }
    [self persistTabSession];
}

- (void)handleNavigationError:(NSError *)error forWebView:(WKWebView *)webView {
    // 用户取消、或策略改为下载（WKNavigationResponsePolicyDownload）时，
    // WebKit 仍会回调失败，文案常为 "Frame load interrupted"；不应弹错误框。
    if ([self shouldIgnoreNavigationError:error]) {
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        tab.isLoading = NO;
        if (webView == self.webView) {
            [self updateNavigationState];
        }
        [self updateTabStripDisplay];
        return;
    }

    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = NO;
    [self updateTabStripDisplay];

    if (webView != self.webView) {
        return;
    }
    [self showErrorWithTitle:@"无法加载页面" message:error.localizedDescription];
    [self updateNavigationState];
}

- (BOOL)shouldIgnoreNavigationError:(NSError *)error {
    if (!error) {
        return YES;
    }
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        return YES;
    }
    // WebKitErrorFrameLoadInterruptedByPolicyChange == 102
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) {
        return YES;
    }
    NSString *description = error.localizedDescription.lowercaseString;
    if ([description containsString:@"frame load interrupted"]) {
        return YES;
    }
    return NO;
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
