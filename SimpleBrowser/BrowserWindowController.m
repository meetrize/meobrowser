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
#import "BrowserLoadingProgressView.h"

static void *kBrowserEstimatedProgressContext = &kBrowserEstimatedProgressContext;

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate, BrowserLaunchpadViewDelegate, BrowserAddressBarAutocompleteControllerDelegate, BrowserDownloadManagerObserver, BrowserDownloadPanelDelegate, NSWindowDelegate, NSMenuItemValidation>
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) NSTitlebarAccessoryViewController *tabStripAccessory;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) BrowserLaunchpadView *launchpadView;
@property (nonatomic, strong) BrowserLoadingProgressView *loadingProgressView;
@property (nonatomic, weak) WKWebView *observedProgressWebView;
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
@property (nonatomic, strong, nullable) dispatch_block_t pendingPersistBlock;
@property (nonatomic, assign) NSInteger trafficLightScheduleGeneration;
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
    // 显式共享默认数据存储，标签间 cookie / localStorage 一致。
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // 限制 URL 缓存上限，避免 App 进程内无限增长。
    NSUInteger memoryCapacity = 16 * 1024 * 1024;
    NSUInteger diskCapacity = 64 * 1024 * 1024;
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:memoryCapacity
                                                      diskCapacity:diskCapacity
                                                          diskPath:@"MeoBrowserURLCache"];
    [NSURLCache setSharedURLCache:cache];
}

- (void)configureChromeWindow {
    NSWindow *window = self.window;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.backgroundColor = BrowserTabStripFillColor();
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

/// 压扁系统标题栏装饰区高度，避免 accessory 标签条上方再露出一截标题栏。
- (void)collapseSystemTitlebarDecoration {
    NSWindow *window = self.window;
    NSView *themeFrame = window.contentView.superview;
    if (!themeFrame) {
        return;
    }
    SEL setter = NSSelectorFromString(@"setCustomTitlebarHeight:");
    if (![themeFrame respondsToSelector:setter]) {
        return;
    }
    void (*setFn)(id, SEL, double) = (void (*)(id, SEL, double))[themeFrame methodForSelector:setter];
    if (setFn) {
        // 0：交通灯叠在标签条上；标签条本身由 titlebar accessory 提供
        setFn(themeFrame, setter, 0.0);
    }
}

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
    // 用 generation 取消 resize/move 风暴中堆积的重试与延迟定位。
    NSInteger generation = ++self.trafficLightScheduleGeneration;
    [self collapseSystemTitlebarDecoration];
    [self tryPositionTrafficLightsStartingAtAttempt:0 generation:generation];

    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayMs in @[@50, @200]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs.doubleValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.trafficLightScheduleGeneration != generation) {
                return;
            }
            [strongSelf collapseSystemTitlebarDecoration];
            [strongSelf positionTrafficLightButtons];
        });
    }
}

- (void)tryPositionTrafficLightsStartingAtAttempt:(NSInteger)attempt generation:(NSInteger)generation {
    if (self.trafficLightScheduleGeneration != generation) {
        return;
    }
    if ([self positionTrafficLightButtons]) {
        return;
    }
    if (attempt >= 20) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.trafficLightScheduleGeneration != generation) {
            return;
        }
        [strongSelf tryPositionTrafficLightsStartingAtAttempt:attempt + 1 generation:generation];
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
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    [self stopObservingLoadingProgress];
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

    self.loadingProgressView = [[BrowserLoadingProgressView alloc] initWithFrame:NSZeroRect];
    self.loadingProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.loadingProgressView];

    [NSLayoutConstraint activateConstraints:@[
        [self.launchpadView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.launchpadView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.launchpadView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.launchpadView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        [self.loadingProgressView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.loadingProgressView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.loadingProgressView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.loadingProgressView.heightAnchor constraintEqualToConstant:BrowserLoadingProgressHeight],
    ]];

    // 标签条挂到标题栏 accessory：系统在该区域把事件交给标签，而非拖窗。
    NSView *accessoryRoot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, BrowserTabStripHeight)];
    accessoryRoot.wantsLayer = YES;
    accessoryRoot.layer.backgroundColor = BrowserTabStripFillColor().CGColor;
    self.tabStripView.translatesAutoresizingMaskIntoConstraints = NO;
    [accessoryRoot addSubview:self.tabStripView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabStripView.topAnchor constraintEqualToAnchor:accessoryRoot.topAnchor],
        [self.tabStripView.leadingAnchor constraintEqualToAnchor:accessoryRoot.leadingAnchor],
        [self.tabStripView.trailingAnchor constraintEqualToAnchor:accessoryRoot.trailingAnchor],
        [self.tabStripView.bottomAnchor constraintEqualToAnchor:accessoryRoot.bottomAnchor],
        [accessoryRoot.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],
    ]];

    self.tabStripAccessory = [[NSTitlebarAccessoryViewController alloc] init];
    self.tabStripAccessory.view = accessoryRoot;
    // 必须在 add 之前设置
    self.tabStripAccessory.layoutAttribute = NSLayoutAttributeBottom;
    [self.window addTitlebarAccessoryViewController:self.tabStripAccessory];
    [self collapseSystemTitlebarDecoration];

    NSStackView *rootStack = [NSStackView stackViewWithViews:@[
        toolbar, self.contentContainer
    ]];
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 0;
    rootStack.distribution = NSStackViewDistributionFill;

    NSView *contentView = self.window.contentView;
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:rootStack];

    // 对齐 contentLayoutGuide：内容紧贴 accessory 下方，避免重复留白
    NSLayoutGuide *contentGuide = (NSLayoutGuide *)self.window.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [rootStack.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
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
    NSURL *url = [tab currentOrRestorableURL];
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
    NSURL *url = [tab currentOrRestorableURL];
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
        NSUInteger pinnedCount = [BrowsingPreferences savedPinnedTabCount];
        [self.tabController restoreTabsFromEntries:entries
                                     selectedIndex:index
                                       pinnedCount:pinnedCount];
    } else {
        [self.tabController addNewTab];
    }
}

#pragma mark - Tab Management

- (void)detachWebViewIfNeeded:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    if (webView.superview == self.contentContainer) {
        [webView removeFromSuperview];
    }
}

- (void)attachWebViewForTab:(BrowserTab *)tab {
    WKWebView *webView = tab.webView;
    if (webView == nil) {
        return;
    }
    if ([webView isKindOfClass:[BrowserWebView class]]) {
        __weak typeof(self) weakSelf = self;
        BrowserWebView *browserWebView = (BrowserWebView *)webView;
        __weak BrowserWebView *weakBrowserWebView = browserWebView;
        browserWebView.openURLHandler = ^(NSURL *url) {
            [weakSelf.tabController addTabWithURL:url];
        };
        browserWebView.downloadURLHandler = ^(NSURL *url) {
            typeof(self) strongSelf = weakSelf;
            BrowserWebView *strongWebView = weakBrowserWebView;
            if (!strongSelf || !strongWebView) {
                return;
            }
            [strongSelf.downloadManager startDownloadWithURL:url fromWebView:strongWebView];
            if (!strongSelf.downloadPanelVisible) {
                [strongSelf showDownloadsPanel];
            }
        };
    }

    if (webView.superview == self.contentContainer) {
        webView.hidden = tab.isNewTabPage;
        return;
    }

    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.hidden = tab.isNewTabPage;
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

    // 仅挂载当前标签的 WebView；其余离屏但仍可常驻（休眠由 TabController 销毁）。
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab == selectedTab) {
            continue;
        }
        [self detachWebViewIfNeeded:tab.webView];
    }

    if (selectedTab != nil && !selectedTab.isNewTabPage) {
        [selectedTab wakeFromHibernationIfNeeded];
        [self attachWebViewForTab:selectedTab];
        if (selectedTab.webView != nil) {
            selectedTab.webView.hidden = NO;
        }
    } else if (selectedTab != nil) {
        [self detachWebViewIfNeeded:selectedTab.webView];
    }

    BOOL showLaunchpad = selectedTab.isNewTabPage;
    self.launchpadView.hidden = !showLaunchpad;
    if (showLaunchpad) {
        [self.launchpadView reloadShortcuts];
    }

    [self.contentContainer addSubview:self.loadingProgressView positioned:NSWindowAbove relativeTo:nil];
    [self observeLoadingProgressForSelectedTab];

    // sync：顺序/数量不变时保留标签视图，避免 mouseDown 选中后重建导致拖拽失效
    [self updateTabStripDisplay];
    [self repositionTrafficLightButtonsAfterLayout];
    [self updateNavigationState];
}

#pragma mark - Loading Progress

- (void)stopObservingLoadingProgress {
    WKWebView *webView = self.observedProgressWebView;
    if (!webView) {
        return;
    }
    @try {
        [webView removeObserver:self
                     forKeyPath:@"estimatedProgress"
                        context:kBrowserEstimatedProgressContext];
    } @catch (__unused NSException *exception) {
    }
    self.observedProgressWebView = nil;
}

- (void)observeLoadingProgressForSelectedTab {
    WKWebView *webView = self.webView;
    BrowserTab *tab = self.tabController.selectedTab;
    // 下方多处共用；webView 可能为 nil（NTP / 休眠占位）。
    if (webView == self.observedProgressWebView) {
        [self syncLoadingProgressUI];
        return;
    }

    [self stopObservingLoadingProgress];

    if (!webView || tab.isNewTabPage) {
        [self.loadingProgressView resetHidden];
        return;
    }

    self.observedProgressWebView = webView;
    [webView addObserver:self
              forKeyPath:@"estimatedProgress"
                 options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                 context:kBrowserEstimatedProgressContext];
}

- (void)syncLoadingProgressUI {
    BrowserTab *tab = self.tabController.selectedTab;
    WKWebView *webView = tab.webView;
    if (!tab || tab.isNewTabPage || !webView) {
        [self.loadingProgressView resetHidden];
        return;
    }

    if (webView.isLoading || tab.isLoading) {
        [self.loadingProgressView setProgress:webView.estimatedProgress animated:NO];
        return;
    }

    if (webView.estimatedProgress > 0.0 && webView.estimatedProgress < 1.0) {
        [self.loadingProgressView setProgress:webView.estimatedProgress animated:NO];
        return;
    }

    [self.loadingProgressView resetHidden];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context != kBrowserEstimatedProgressContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (![keyPath isEqualToString:@"estimatedProgress"] || ![object isKindOfClass:[WKWebView class]]) {
        return;
    }

    WKWebView *webView = (WKWebView *)object;
    if (webView != self.webView) {
        return;
    }

    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        [self.loadingProgressView resetHidden];
        return;
    }

    double progress = webView.estimatedProgress;
    if (webView.isLoading || tab.isLoading || (progress > 0.0 && progress < 1.0)) {
        [self.loadingProgressView setProgress:progress animated:YES];
    } else if (progress >= 1.0) {
        [self.loadingProgressView completeIfVisible];
    } else {
        [self.loadingProgressView resetHidden];
    }
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
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    [self persistTabSessionNow];
}

- (void)schedulePersistTabSession {
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingPersistBlock = nil;
        [strongSelf persistTabSessionNow];
    });
    self.pendingPersistBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)persistTabSessionNow {
    NSMutableArray<NSString *> *entries = [[NSMutableArray alloc] init];
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab.isNewTabPage) {
            [entries addObject:BrowserTabSessionNewTabMarker];
            continue;
        }
        NSURL *url = [tab currentOrRestorableURL];
        if ([BrowsingPreferences isPersistableURL:url]) {
            [entries addObject:url.absoluteString];
        } else {
            [entries addObject:BrowserTabSessionNewTabMarker];
        }
    }

    NSInteger selectedIndex = [self.tabController indexOfSelectedTab];
    if (selectedIndex == NSNotFound) {
        selectedIndex = 0;
    }
    [BrowsingPreferences saveTabEntries:entries
                          selectedIndex:selectedIndex
                            pinnedCount:self.tabController.pinnedTabCount];
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
    [self schedulePersistTabSession];
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

- (void)tabStripView:(id)stripView didCloseOtherTabsExceptTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController closeOtherTabsExcept:tab];
    }
}

- (void)tabStripView:(id)stripView didCloseTabsToTheRightOfTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController closeTabsToTheRightOf:tab];
    }
}

- (void)tabStripViewDidRequestRestoreRecentlyClosedTab:(id)stripView {
    (void)stripView;
    [self.tabController restoreRecentlyClosedTab];
}

- (BOOL)tabStripViewCanRestoreRecentlyClosedTab:(id)stripView {
    (void)stripView;
    return self.tabController.canRestoreRecentlyClosedTab;
}

- (BOOL)tabStripView:(id)stripView canCloseOtherTabsExceptTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    return tab != nil && self.tabController.tabs.count > 1;
}

- (BOOL)tabStripView:(id)stripView canCloseTabsToTheRightOfTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (!tab) {
        return NO;
    }
    NSUInteger index = [self.tabController.tabs indexOfObject:tab];
    return index != NSNotFound && index + 1 < self.tabController.tabs.count;
}

- (void)tabStripViewDidRequestNewTab:(id)stripView {
    (void)stripView;
    [self.tabController addNewTab];
}

- (void)tabStripView:(id)stripView didMoveTabID:(NSUUID *)tabID toIndex:(NSUInteger)toIndex {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController moveTab:tab toIndex:toIndex];
    }
}

- (void)tabStripView:(id)stripView didSetPinned:(BOOL)pinned forTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    if (tab) {
        [self.tabController setTab:tab pinned:pinned];
    }
}

- (BOOL)tabStripView:(id)stripView isTabPinnedForTabID:(NSUUID *)tabID {
    (void)stripView;
    BrowserTab *tab = [self tabForID:tabID];
    return tab.isPinned;
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

- (void)restoreRecentlyClosedBrowserTab:(id)sender {
    (void)sender;
    [self.tabController restoreRecentlyClosedTab];
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
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab.isHibernated) {
        [tab wakeFromHibernationIfNeeded];
        [self refreshTabsUI];
        return;
    }
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
    if (action == @selector(restoreRecentlyClosedBrowserTab:)) {
        return self.tabController.canRestoreRecentlyClosedTab;
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
    NSURL *url = [tab currentOrRestorableURL];
    return url.absoluteString ?: @"";
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
    BrowserTab *tab = self.tabController.selectedTab;
    WKWebView *webView = self.webView;

    if (!tab || tab.isNewTabPage || webView == nil) {
        self.backButton.enabled = NO;
        self.forwardButton.enabled = NO;
        self.reloadButton.enabled = tab != nil && (tab.isHibernated || !tab.isNewTabPage);
        [self setDisplayedWindowTitle:tab.displayTitle ?: BrowserAppDisplayName];
        [self persistAddressBarDraftFromField];
        if (tab) {
            [self applyAddressBarStringForTab:tab];
        } else {
            self.addressField.stringValue = @"";
            self.lastAddressBarTab = nil;
        }
        [self updateBookmarkButtonState];
        return;
    }

    self.backButton.enabled = webView.canGoBack;
    self.forwardButton.enabled = webView.canGoForward;
    self.reloadButton.enabled = YES;

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
    if (webView == self.webView) {
        [self.loadingProgressView beginLoading];
    }
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
        [self.loadingProgressView completeIfVisible];
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
    [self schedulePersistTabSession];
}

- (void)handleNavigationError:(NSError *)error forWebView:(WKWebView *)webView {
    // 用户取消、或策略改为下载（WKNavigationResponsePolicyDownload）时，
    // WebKit 仍会回调失败，文案常为 "Frame load interrupted"；不应弹错误框。
    if ([self shouldIgnoreNavigationError:error]) {
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        tab.isLoading = NO;
        if (webView == self.webView) {
            if (webView.isLoading) {
                [self.loadingProgressView setProgress:webView.estimatedProgress animated:YES];
            } else {
                [self.loadingProgressView resetHidden];
            }
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
    [self.loadingProgressView resetHidden];
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
    (void)configuration;
    (void)windowFeatures;

    // 右键「下载图片/媒体」：WebKit 默认项无效，经 Open*InNewWindow 拿 URL 后改走下载。
    if ([webView isKindOfClass:[BrowserWebView class]]) {
        BrowserWebView *browserWebView = (BrowserWebView *)webView;
        NSURL *downloadURL = [browserWebView consumePendingContextMenuDownloadURL:navigationAction.request.URL];
        if (downloadURL) {
            if (browserWebView.downloadURLHandler) {
                browserWebView.downloadURLHandler(downloadURL);
            }
            return nil;
        }
    }

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

- (void)webView:(WKWebView *)webView
runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {
    (void)webView;
    (void)frame;

    // macOS 上若不实现本方法，网页 <input type="file"> 点击无响应。
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    if (@available(macOS 10.13.4, *)) {
        panel.canChooseDirectories = parameters.allowsDirectories;
    } else {
        panel.canChooseDirectories = NO;
    }

    NSWindow *hostWindow = self.window;
    void (^finish)(NSModalResponse) = ^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            completionHandler(panel.URLs);
        } else {
            completionHandler(nil);
        }
    };

    if (hostWindow != nil) {
        [panel beginSheetModalForWindow:hostWindow completionHandler:finish];
    } else {
        finish([panel runModal]);
    }
}

@end
