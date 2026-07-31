#import "BrowserWindowController.h"
#import "AppDelegate.h"
#import "BrowserAppInfo.h"
#import "SBTextField.h"
#import "BrowsingPreferences.h"
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
#import "BrowserURLInputClassifier.h"
#import "BrowserDownloadManager.h"
#import "BrowserDownloadPanel.h"
#import "BrowserDownloadProgressRingView.h"
#import "BrowserFindBarController.h"
#import "BrowserFindBarView.h"
#import "BrowserTabOverviewController.h"
#import "BrowserTabThumbnailCache.h"
#import "CallAlertBannerController.h"
#import "PhonePolicyPanelController.h"
#import "BrowserFaviconService.h"
#import "BrowserLoadingProgressView.h"
#import "LoginAssistController.h"
#import "CaptchaAssistController.h"
#import "BrowserFeedAssistController.h"
#import "BrowserSSLExceptionStore.h"
#import "BrowserCertificateWarningView.h"
#import "BrowserNavigationErrorView.h"
#import "BrowserHTTPAuthPrompt.h"
#import "CompanionChannel.h"
#import "BrowserTransientToast.h"
#import "PhoneNotificationSidebarController.h"
#import "BrowserTrailingSidebarSlot.h"
#import "AssistSidebarController.h"
#import "AssistSidebarSettings.h"
#import "LoginRecipe.h"
#import "FormMemo.h"
#import "PhoneNotificationInboxSettings.h"
#import "PhoneNotificationInboxStore.h"
#import "PhoneNotificationPresenter.h"
#import <Security/Security.h>

static void *kBrowserEstimatedProgressContext = &kBrowserEstimatedProgressContext;
static void *kBrowserFullscreenStateContext = &kBrowserFullscreenStateContext;

static NSString * const kBrowserSecurityBadgeTitle = @"连接不安全";

static NSFont *BrowserSecurityBadgeFont(void) {
    return [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
}

static CGFloat BrowserSecurityBadgeContentWidth(void) {
    NSSize size = [kBrowserSecurityBadgeTitle sizeWithAttributes:@{
        NSFontAttributeName: BrowserSecurityBadgeFont()
    }];
    return ceil(size.width);
}

static NSAttributedString *BrowserSecurityBadgeAttributedTitle(void) {
    return [[NSAttributedString alloc] initWithString:kBrowserSecurityBadgeTitle
                                           attributes:@{
        NSFontAttributeName: BrowserSecurityBadgeFont(),
        NSForegroundColorAttributeName: [NSColor systemOrangeColor],
    }];
}

@interface BrowserPendingSSLAuth : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) NSString *hostKey;
@property (nonatomic, copy) NSString *hostDisplay;
@property (nonatomic, strong, nullable) NSURLAuthenticationChallenge *challenge;
@property (nonatomic, copy, nullable) void (^completionHandler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential);
@property (nonatomic, strong, nullable) NSURL *fallbackReloadURL;
@property (nonatomic, assign) BOOL completionInvoked;
- (void)finishWithDisposition:(NSURLSessionAuthChallengeDisposition)disposition
                   credential:(nullable NSURLCredential *)credential;
@end

@implementation BrowserPendingSSLAuth
- (void)finishWithDisposition:(NSURLSessionAuthChallengeDisposition)disposition
                   credential:(NSURLCredential *)credential {
    if (self.completionInvoked) {
        return;
    }
    self.completionInvoked = YES;
    void (^handler)(NSURLSessionAuthChallengeDisposition, NSURLCredential *) = self.completionHandler;
    self.completionHandler = nil;
    self.challenge = nil;
    if (handler) {
        handler(disposition, credential);
    }
}
@end

@interface BrowserPendingNavigationError : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong, nullable) NSURL *failingURL;
@property (nonatomic, assign) BOOL canGoBack;
@end

@implementation BrowserPendingNavigationError
@end

@interface BrowserProvisionalNavigationWatchdog : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, strong, nullable) NSURL *provisionalURL;
@property (nonatomic, assign) NSInteger token;
@property (nonatomic, strong, nullable) dispatch_block_t block;
@end

@implementation BrowserProvisionalNavigationWatchdog
@end

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate, BrowserLaunchpadViewDelegate, BrowserAddressBarAutocompleteControllerDelegate, BrowserDownloadManagerObserver, BrowserDownloadPanelDelegate, BrowserCertificateWarningViewDelegate, BrowserNavigationErrorViewDelegate, PhoneNotificationSidebarControllerDelegate, AssistSidebarControllerDelegate, NSWindowDelegate, NSMenuItemValidation>
- (instancetype)initWithSessionDictionary:(nullable NSDictionary *)session loadTabs:(BOOL)loadTabs;
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) NSTitlebarAccessoryViewController *tabStripAccessory;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSStackView *contentRowStack;
@property (nonatomic, strong) PhoneNotificationSidebarController *notificationSidebarController;
@property (nonatomic, strong) AssistSidebarController *assistSidebarController;
@property (nonatomic, strong) BrowserTrailingSidebarSlot *trailingSidebarSlot;
@property (nonatomic, strong, nullable) NSView *notificationInboxBadgeView;
@property (nonatomic, strong) BrowserLaunchpadView *launchpadView;
@property (nonatomic, strong) BrowserLoadingProgressView *loadingProgressView;
@property (nonatomic, weak) WKWebView *observedProgressWebView;
@property (nonatomic, weak) WKWebView *observedFullscreenWebView;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, strong) NSButton *securityBadgeButton;
@property (nonatomic, strong) NSButton *downloadButton;
@property (nonatomic, strong) NSView *downloadBadgeView;
@property (nonatomic, strong) BrowserDownloadProgressRingView *downloadProgressRingView;
@property (nonatomic, strong) SBTextField *addressField;
@property (nonatomic, strong) BrowserAddressBarActionGroup *addressBarActionGroup;
@property (nonatomic, strong) BrowserAddressBarRowView *addressBarRow;
@property (nonatomic, strong) BrowserAddressBarAutocompleteController *addressAutocompleteController;
@property (nonatomic, weak) BrowserTab *lastAddressBarTab;
@property (nonatomic, strong) WKWebViewConfiguration *webViewConfiguration;
@property (nonatomic, strong) BrowserDownloadManager *downloadManager;
@property (nonatomic, strong) BrowserDownloadPanel *downloadPanel;
@property (nonatomic, assign) BOOL downloadPanelVisible;
@property (nonatomic, strong) LoginAssistController *loginAssistController;
@property (nonatomic, strong) CaptchaAssistController *captchaAssistController;
@property (nonatomic, strong) BrowserFeedAssistController *feedAssistController;
@property (nonatomic, strong) BrowserFindBarController *findBarController;
@property (nonatomic, strong) BrowserTabOverviewController *tabOverviewController;
@property (nonatomic, strong, nullable) NSTextField *tabOverviewBadgeLabel;
@property (nonatomic, strong, nullable) dispatch_block_t pendingPersistBlock;
@property (nonatomic, assign) NSInteger trafficLightScheduleGeneration;
@property (nonatomic, strong) BrowserCertificateWarningView *certificateWarningView;
@property (nonatomic, strong) BrowserNavigationErrorView *navigationErrorView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserPendingSSLAuth *> *pendingSSLAuthByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserPendingNavigationError *> *pendingNavigationErrorByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserProvisionalNavigationWatchdog *> *provisionalWatchdogByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, NSURL *> *pendingProvisionalURLByWebView;
@property (nonatomic, strong) NSHashTable<WKWebView *> *webViewsWithHTTPAuthPrompt;
@property (nonatomic, assign) BOOL addressFieldIsEditing;
/// 上次 refreshTabsUI 时的选中标签，用于判断是否切到新标签页后再聚焦地址栏。
@property (nonatomic, strong, nullable) NSUUID *lastSelectedTabIDForAddressFocus;
@end

@implementation BrowserWindowController

- (WKWebView *)webView {
    return self.tabController.selectedTab.webView;
}

+ (void)configureSharedWebKitDefaultsIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUInteger memoryCapacity = 16 * 1024 * 1024;
        NSUInteger diskCapacity = 64 * 1024 * 1024;
        NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:memoryCapacity
                                                          diskCapacity:diskCapacity
                                                              diskPath:@"MeoBrowserURLCache"];
        [NSURLCache setSharedURLCache:cache];
    });
}

- (instancetype)init {
    return [self initWithSessionDictionary:nil];
}

- (instancetype)initForTabAdoption {
    return [self initWithSessionDictionary:nil loadTabs:NO];
}

- (instancetype)initWithSessionDictionary:(NSDictionary *)session {
    return [self initWithSessionDictionary:session loadTabs:YES];
}

- (instancetype)initWithSessionDictionary:(NSDictionary *)session loadTabs:(BOOL)loadTabs {
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
        [[self class] configureSharedWebKitDefaultsIfNeeded];
        _webViewConfiguration = [[WKWebViewConfiguration alloc] init];
        _loginAssistController = [[LoginAssistController alloc] initWithWindowController:self];
        _captchaAssistController = [[CaptchaAssistController alloc] initWithWindowController:self];
        _feedAssistController = [[BrowserFeedAssistController alloc] initWithWindowController:self];
        _findBarController = [[BrowserFindBarController alloc] initWithWindowController:self];
        _tabOverviewController = [[BrowserTabOverviewController alloc] initWithWindowController:self];
        [self configureWebViewConfiguration:_webViewConfiguration];
        _tabController = [[BrowserTabController alloc] initWithConfiguration:_webViewConfiguration];
        _tabController.delegate = self;
        _downloadManager = [BrowserDownloadManager sharedManager];
        [_downloadManager addObserver:self];
        _pendingSSLAuthByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _pendingNavigationErrorByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _provisionalWatchdogByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _pendingProvisionalURLByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _webViewsWithHTTPAuthPrompt = [NSHashTable weakObjectsHashTable];
        [self setupUI];
        if (loadTabs) {
            [self applySessionDictionary:session];
        }
    }
    return self;
}

#pragma mark - UI Setup

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    // UA 由 BrowserUserAgent + WebView.customUserAgent 对齐本机 Safari；此处不再写死 Version。
    // 显式共享默认数据存储，标签间 cookie / localStorage 一致。
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    // WebKit 默认关闭 Element Fullscreen；YouTube / 抖音等会检测 document.fullscreenEnabled。
    if (@available(macOS 12.3, *)) {
        configuration.preferences.elementFullscreenEnabled = YES;
    }
    // http:#hash 经系统代理可能变成 path 里的 %23 → 404；在 document-start 写回 hash。
    [BrowserWebView installFragmentRestoreScriptOnContentController:configuration.userContentController];
    [self.loginAssistController configureWebViewConfiguration:configuration];
    [self.captchaAssistController configureWebViewConfiguration:configuration];
    [self.feedAssistController configureWebViewConfiguration:configuration];
    [self.findBarController configureWebViewConfiguration:configuration];
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

- (void)windowDidResize:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    // 极窄窗口自动收起侧栏，避免网页区不可用
    if (NSWidth(self.window.frame) < 720) {
        [self.trailingSidebarSlot hideAllAnimated:YES];
        [self updateNotificationInboxButtonAppearance];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    [self cancelAllPendingSSLAuthWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge];
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    id delegate = NSApp.delegate;
    if ([delegate respondsToSelector:@selector(browserWindowControllerWillClose:)]) {
        [(AppDelegate *)delegate browserWindowControllerWillClose:self];
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
    [self cancelAllPendingSSLAuthWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge];
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    [self stopObservingLoadingProgress];
    [self stopObservingFullscreenState];
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

    self.securityBadgeButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.securityBadgeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.securityBadgeButton.bordered = NO;
    self.securityBadgeButton.bezelStyle = NSBezelStyleShadowlessSquare;
    [self.securityBadgeButton setButtonType:NSButtonTypeMomentaryChange];
    self.securityBadgeButton.attributedTitle = BrowserSecurityBadgeAttributedTitle();
    self.securityBadgeButton.imagePosition = NSNoImage;
    self.securityBadgeButton.hidden = YES;
    self.securityBadgeButton.toolTip = @"此站点证书不受信任";
    self.securityBadgeButton.target = self;
    self.securityBadgeButton.action = @selector(showInsecureConnectionDetails:);
    // 禁止按压高亮铺开背景。
    NSButtonCell *badgeCell = (NSButtonCell *)self.securityBadgeButton.cell;
    badgeCell.highlightsBy = NSNoCellMask;
    badgeCell.showsStateBy = NSNoCellMask;
    if ([badgeCell respondsToSelector:@selector(setBackgroundColor:)]) {
        badgeCell.backgroundColor = [NSColor clearColor];
    }
    [self.securityBadgeButton setContentHuggingPriority:NSLayoutPriorityRequired
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.securityBadgeButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.addressAutocompleteController = [[BrowserAddressBarAutocompleteController alloc] initWithAddressField:self.addressField];
    self.addressAutocompleteController.delegate = self;
    [self.addressAutocompleteController install];

    self.addressBarActionGroup = [[BrowserAddressBarActionGroup alloc] initWithFrame:NSZeroRect];
    self.addressBarActionGroup.minimumAddressWidth = 120;
    self.downloadButton = self.addressBarActionGroup.downloadButton;
    self.downloadButton.target = self;
    self.downloadButton.action = @selector(toggleDownloadsPanel:);
    [self installDownloadBadgeOnButton:self.downloadButton];
    [self installDownloadProgressRingOnButton:self.downloadButton];
    __weak typeof(self) weakSelf = self;
    self.addressBarActionGroup.augmentContextMenu = ^(NSString *itemID, NSMenu *menu) {
        if ([itemID isEqualToString:@"loginAssist"]) {
            [weakSelf.loginAssistController appendItemsToToolbarContextMenu:menu];
        }
    };
    if (self.addressBarActionGroup.loginAssistButton) {
        [self.loginAssistController wireLoginButton:self.addressBarActionGroup.loginAssistButton];
    }
    if (self.addressBarActionGroup.captchaAssistButton) {
        [self.captchaAssistController wireCaptchaButton:self.addressBarActionGroup.captchaAssistButton];
    }
    if (self.addressBarActionGroup.feedButton) {
        [self.feedAssistController wireFeedButton:self.addressBarActionGroup.feedButton];
    }
    [self wireFindInPageButton];
    [self wireTabOverviewButton];
    [self wireCompanionLinkButton];
    [self wireSendToPhoneButton];
    [self wirePhonePolicyButton];
    [self wireNotificationInboxButton];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(addressBarActionOrderDidChange:)
                                                 name:@"BrowserAddressBarActionOrderDidChangeNotification"
                                               object:self.addressBarActionGroup];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(companionChannelStateDidChange:)
                                                 name:CompanionChannelStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(phoneNotificationInboxDidChange:)
                                                 name:PhoneNotificationInboxDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(phoneNotificationInboxRevealItem:)
                                                 name:PhoneNotificationInboxRevealItemNotification
                                               object:nil];
    [self.addressBarActionGroup updateCompanionLinkAppearance];

    self.addressBarRow = [[BrowserAddressBarRowView alloc] initWithAddressField:self.addressField
                                                                 securityBadge:self.securityBadgeButton
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
    [self.contentContainer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.notificationSidebarController = [[PhoneNotificationSidebarController alloc] init];
    self.notificationSidebarController.delegate = self;
    self.notificationSidebarController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.notificationSidebarController.view setContentHuggingPriority:NSLayoutPriorityRequired
                                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.notificationSidebarController.view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                                      forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.assistSidebarController = [[AssistSidebarController alloc] init];
    self.assistSidebarController.delegate = self;
    self.assistSidebarController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.assistSidebarController.view setContentHuggingPriority:NSLayoutPriorityRequired
                                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.assistSidebarController.view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.trailingSidebarSlot = [[BrowserTrailingSidebarSlot alloc] init];
    self.trailingSidebarSlot.notificationSidebar = self.notificationSidebarController;
    self.trailingSidebarSlot.assistSidebar = self.assistSidebarController;

    self.contentRowStack = [NSStackView stackViewWithViews:@[
        self.contentContainer,
        self.notificationSidebarController.view,
        self.assistSidebarController.view
    ]];
    self.contentRowStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.contentRowStack.spacing = 0;
    self.contentRowStack.distribution = NSStackViewDistributionFill;
    [self.contentRowStack setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationVertical];

    self.launchpadView = [[BrowserLaunchpadView alloc] initWithFrame:NSZeroRect];
    self.launchpadView.delegate = self;
    self.launchpadView.hidden = YES;
    self.launchpadView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.launchpadView];

    self.loadingProgressView = [[BrowserLoadingProgressView alloc] initWithFrame:NSZeroRect];
    self.loadingProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.loadingProgressView];

    self.certificateWarningView = [[BrowserCertificateWarningView alloc] initWithFrame:NSZeroRect];
    self.certificateWarningView.delegate = self;
    self.certificateWarningView.hidden = YES;
    self.certificateWarningView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.certificateWarningView];

    self.navigationErrorView = [[BrowserNavigationErrorView alloc] initWithFrame:NSZeroRect];
    self.navigationErrorView.delegate = self;
    self.navigationErrorView.hidden = YES;
    self.navigationErrorView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.navigationErrorView];

    [NSLayoutConstraint activateConstraints:@[
        [self.launchpadView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.launchpadView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.launchpadView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.launchpadView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        [self.certificateWarningView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.certificateWarningView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.certificateWarningView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.certificateWarningView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        [self.navigationErrorView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.navigationErrorView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.navigationErrorView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.navigationErrorView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
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
        toolbar, self.contentRowStack
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

    [self.findBarController installInContentContainer:self.contentContainer];
    [self.tabOverviewController installInContentContainer:self.contentContainer];
    [[CallAlertBannerController sharedController] installInContentContainer:self.contentContainer
                                                         forWindowController:self];
    [self updateNotificationInboxButtonAppearance];
    [self updateTabOverviewButtonAppearance];
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

- (void)installDownloadProgressRingOnButton:(NSButton *)button {
    if (!button) {
        return;
    }
    [self.downloadProgressRingView removeFromSuperview];
    BrowserDownloadProgressRingView *ring = [[BrowserDownloadProgressRingView alloc] initWithFrame:NSZeroRect];
    ring.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:ring positioned:NSWindowBelow relativeTo:self.downloadBadgeView];
    [NSLayoutConstraint activateConstraints:@[
        [ring.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [ring.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [ring.topAnchor constraintEqualToAnchor:button.topAnchor],
        [ring.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
    ]];
    self.downloadProgressRingView = ring;
}

#pragma mark - Downloads

- (void)wireFindInPageButton {
    NSButton *button = self.addressBarActionGroup.findInPageButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(toggleFindBar:);
}

- (void)wireTabOverviewButton {
    NSButton *button = self.addressBarActionGroup.tabOverviewButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(toggleTabOverview:);
    [self installTabOverviewBadgeOnButton:button];
    [self updateTabOverviewButtonAppearance];
}

- (void)installTabOverviewBadgeOnButton:(NSButton *)button {
    if (!button) {
        return;
    }
    [self.tabOverviewBadgeLabel removeFromSuperview];
    NSTextField *badge = self.tabOverviewBadgeLabel;
    if (!badge) {
        badge = [NSTextField labelWithString:@"0"];
        badge.editable = NO;
        badge.bezeled = NO;
        badge.drawsBackground = YES;
        badge.backgroundColor = [NSColor systemRedColor];
        badge.textColor = [NSColor whiteColor];
        badge.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
        badge.alignment = NSTextAlignmentCenter;
        badge.wantsLayer = YES;
        badge.layer.cornerRadius = 7.0;
        badge.layer.masksToBounds = YES;
        badge.hidden = YES;
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        self.tabOverviewBadgeLabel = badge;
    }
    [button addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintGreaterThanOrEqualToConstant:14],
        [badge.heightAnchor constraintEqualToConstant:14],
        [badge.topAnchor constraintEqualToAnchor:button.topAnchor constant:1],
        [badge.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-1],
    ]];
}

- (void)updateTabOverviewButtonAppearance {
    NSButton *button = self.addressBarActionGroup.tabOverviewButton;
    BOOL visible = self.tabOverviewController.isVisible;
    if (button) {
        if (@available(macOS 10.14, *)) {
            button.contentTintColor = visible ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
        }
        if (@available(macOS 11.0, *)) {
            NSString *symbol = visible ? @"square.grid.2x2.fill" : @"square.grid.2x2";
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:15
                                                                weight:NSFontWeightSemibold
                                                                 scale:NSImageSymbolScaleMedium];
            NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"标签概览"];
            button.image = [image imageWithSymbolConfiguration:config];
        }
    }
    NSUInteger count = self.tabController.tabs.count;
    if (self.tabOverviewBadgeLabel) {
        if (count >= 2) {
            self.tabOverviewBadgeLabel.stringValue = count > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)count];
            self.tabOverviewBadgeLabel.hidden = NO;
        } else {
            self.tabOverviewBadgeLabel.hidden = YES;
        }
    }
}

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
    if (self.downloadButton && self.downloadProgressRingView.superview != self.downloadButton) {
        [self installDownloadProgressRingOnButton:self.downloadButton];
    }
    self.downloadButton.target = self;
    self.downloadButton.action = @selector(toggleDownloadsPanel:);
    [self updateDownloadButtonAppearance];
    if (self.addressBarActionGroup.loginAssistButton) {
        [self.loginAssistController wireLoginButton:self.addressBarActionGroup.loginAssistButton];
    }
    if (self.addressBarActionGroup.captchaAssistButton) {
        [self.captchaAssistController wireCaptchaButton:self.addressBarActionGroup.captchaAssistButton];
    }
    if (self.addressBarActionGroup.feedButton) {
        [self.feedAssistController wireFeedButton:self.addressBarActionGroup.feedButton];
    }
    [self wireFindInPageButton];
    [self wireTabOverviewButton];
    [self wireCompanionLinkButton];
    [self wireSendToPhoneButton];
    [self wirePhonePolicyButton];
    [self wireNotificationInboxButton];
    [self.addressBarActionGroup updateCompanionLinkAppearance];
    [self updateNotificationInboxButtonAppearance];
}

- (void)wireCompanionLinkButton {
    NSButton *button = self.addressBarActionGroup.companionLinkButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(showCompanionLinkSettings:);
}

- (void)wireSendToPhoneButton {
    NSButton *button = self.addressBarActionGroup.sendToPhoneButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(sendCurrentTabToPhone:);
}

- (void)wirePhonePolicyButton {
    NSButton *button = self.addressBarActionGroup.phonePolicyButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(showPhonePolicyPanel:);
}

- (void)wireNotificationInboxButton {
    NSButton *button = self.addressBarActionGroup.notificationInboxButton;
    if (!button) {
        return;
    }
    button.target = self;
    button.action = @selector(toggleNotificationInboxSidebar:);
    [self installNotificationInboxBadgeOnButton:button];
}

- (void)installNotificationInboxBadgeOnButton:(NSButton *)button {
    if (!button) {
        return;
    }
    if (self.notificationInboxBadgeView.superview == button) {
        return;
    }
    [self.notificationInboxBadgeView removeFromSuperview];
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
    self.notificationInboxBadgeView = badge;
}

- (void)toggleNotificationInboxSidebar:(id)sender {
    (void)sender;
    BOOL open = !self.notificationSidebarController.visible;
    [self.trailingSidebarSlot setNotificationVisible:open animated:YES];
    [self updateNotificationInboxButtonAppearance];
}

- (void)updateNotificationInboxButtonAppearance {
    NSButton *button = self.addressBarActionGroup.notificationInboxButton;
    if (!button) {
        return;
    }
    if (self.notificationInboxBadgeView.superview != button) {
        [self installNotificationInboxBadgeOnButton:button];
    }
    BOOL open = self.notificationSidebarController.visible;
    NSUInteger unread = [[PhoneNotificationInboxStore sharedStore] unreadCount];
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = open ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }
    self.notificationInboxBadgeView.hidden = (unread == 0);
    if (unread > 0) {
        button.toolTip = [NSString stringWithFormat:@"手机通知 · %lu 条未读", (unsigned long)MIN(unread, 99)];
    } else {
        button.toolTip = open ? @"手机通知（已打开）" : @"手机通知";
    }
}

- (void)phoneNotificationInboxDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateNotificationInboxButtonAppearance];
}

- (void)phoneNotificationInboxRevealItem:(NSNotification *)notification {
    // 仅 key 窗口处理，避免多窗同时弹开
    if (self.window != NSApp.keyWindow && NSApp.keyWindow != nil) {
        // 若当前没有 key 浏览器窗，第一个响应的也可处理；key 是本窗时继续
        BrowserWindowController *keyBrowser = nil;
        for (NSWindow *window in NSApp.windows) {
            if (window.isKeyWindow && [window.windowController isKindOfClass:[BrowserWindowController class]]) {
                keyBrowser = (BrowserWindowController *)window.windowController;
                break;
            }
        }
        if (keyBrowser && keyBrowser != self) {
            return;
        }
    }
    NSString *itemID = notification.userInfo[PhoneNotificationInboxRevealItemIDKey];
    [self.window makeKeyAndOrderFront:nil];
    [self.notificationSidebarController revealItemID:itemID];
    [self updateNotificationInboxButtonAppearance];
}

- (void)notificationSidebarDidRequestClose:(PhoneNotificationSidebarController *)controller {
    (void)controller;
    [self.trailingSidebarSlot setNotificationVisible:NO animated:YES];
    [self updateNotificationInboxButtonAppearance];
}

- (void)notificationSidebarDidRequestCompanionSettings:(PhoneNotificationSidebarController *)controller {
    (void)controller;
    [self showCompanionLinkSettings:nil];
}

- (void)notificationSidebar:(PhoneNotificationSidebarController *)controller didChangeWidth:(CGFloat)width {
    (void)controller;
    [PhoneNotificationInboxSettings sharedSettings].sidebarWidth = width;
}

#pragma mark - Assist sidebar

- (void)toggleAssistSidebar:(id)sender {
    (void)sender;
    BOOL open = !self.assistSidebarController.visible;
    [self setAssistSidebarVisible:open revealingRecipeID:nil memoID:nil];
}

- (void)setAssistSidebarVisible:(BOOL)visible
             revealingRecipeID:(NSString *)recipeID
                        memoID:(NSString *)memoID {
    if (visible) {
        if (self.notificationSidebarController.visible) {
            [self.trailingSidebarSlot setNotificationVisible:NO animated:YES];
            [self updateNotificationInboxButtonAppearance];
        }
        if (recipeID.length > 0) {
            [self.trailingSidebarSlot setAssistVisible:YES animated:YES];
            [self.assistSidebarController revealRecipeID:recipeID];
        } else if (memoID.length > 0) {
            [self.trailingSidebarSlot setAssistVisible:YES animated:YES];
            [self.assistSidebarController revealMemoID:memoID];
        } else if (!self.assistSidebarController.visible) {
            [self.trailingSidebarSlot setAssistVisible:YES animated:YES];
        } else {
            [self.assistSidebarController reloadList];
        }
    } else {
        [self.trailingSidebarSlot setAssistVisible:NO animated:YES];
    }
}

- (void)showAssistSidebar:(id)sender {
    [self setAssistSidebarVisible:YES revealingRecipeID:nil memoID:nil];
}

- (void)assistSidebarDidRequestClose:(AssistSidebarController *)controller {
    (void)controller;
    [self.trailingSidebarSlot setAssistVisible:NO animated:YES];
}

- (void)assistSidebar:(AssistSidebarController *)controller didChangeWidth:(CGFloat)width {
    (void)controller;
    [AssistSidebarSettings sharedSettings].sidebarWidth = width;
}

- (NSURL *)assistSidebarCurrentURL:(AssistSidebarController *)controller {
    (void)controller;
    return self.webView.URL;
}

- (WKWebView *)assistSidebarWebViewForPicking:(AssistSidebarController *)controller {
    (void)controller;
    return self.webView;
}

- (void)assistSidebar:(AssistSidebarController *)controller runRecipe:(LoginRecipe *)recipe fillOnly:(BOOL)fillOnly {
    (void)controller;
    [self.loginAssistController runRecipe:recipe fillOnly:fillOnly];
}

- (void)assistSidebar:(AssistSidebarController *)controller runMemo:(FormMemo *)memo {
    (void)controller;
    [self.loginAssistController runMemo:memo];
}

- (void)assistSidebarDidRequestAdvancedSettings:(AssistSidebarController *)controller preferMemos:(BOOL)preferMemos {
    (void)controller;
    if (preferMemos) {
        [self.loginAssistController presentSettingsEditingMemoID:nil];
    } else {
        [self.loginAssistController presentSettingsEditingRecipeID:nil];
    }
}

- (void)showPhonePolicyPanel:(id)sender {
    (void)sender;
    [[PhonePolicyPanelController sharedController] showPanel];
}

- (void)showCompanionLinkSettings:(id)sender {
    (void)sender;
    [self.loginAssistController presentCompanionSettings];
}

- (void)companionChannelStateDidChange:(NSNotification *)notification {
    (void)notification;
    [self.addressBarActionGroup updateCompanionLinkAppearance];
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
    [self.downloadPanel presentAnchoredToRect:screenRect ofWindow:self.window];
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

    // 下载中用纯箭头 + 外圈进度环；空闲保留 circle 图标。
    NSString *symbol = busy ? @"arrow.down" : @"arrow.down.circle";
    NSImage *image = [self toolbarSymbolImageNamed:symbol];
    if (image) {
        self.downloadButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        self.downloadButton.contentTintColor = busy ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }

    self.downloadBadgeView.hidden = (unread == 0) || busy;

    BrowserDownloadProgressRingView *ring = self.downloadProgressRingView;
    ring.active = busy;
    if (busy) {
        BOOL determinate = self.downloadManager.aggregateProgressIsDeterminate;
        ring.indeterminate = !determinate;
        ring.progress = determinate ? self.downloadManager.aggregateProgress : 0;
    }

    if (active > 0) {
        if (self.downloadManager.aggregateProgressIsDeterminate) {
            NSInteger pct = (NSInteger)llround(self.downloadManager.aggregateProgress * 100.0);
            self.downloadButton.toolTip = [NSString stringWithFormat:@"下载中（%lu 项 · %ld%%）", (unsigned long)active, (long)pct];
        } else {
            self.downloadButton.toolTip = [NSString stringWithFormat:@"下载中（%lu 项）", (unsigned long)active];
        }
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
    NSArray<NSDictionary *> *windows = [BrowsingPreferences savedWindowSessions];
    if (windows.count > 0) {
        [self applySessionDictionary:windows.firstObject];
    } else {
        [self.tabController addNewTab];
    }
}

- (void)applySessionDictionary:(NSDictionary *)session {
    NSArray *tabs = session[BrowserWindowSessionTabsKey];
    if (![tabs isKindOfClass:[NSArray class]] || tabs.count == 0) {
        [self.tabController addNewTab];
        return;
    }

    NSInteger selectedIndex = 0;
    NSNumber *selectedValue = session[BrowserWindowSessionSelectedIndexKey];
    if ([selectedValue isKindOfClass:[NSNumber class]]) {
        selectedIndex = selectedValue.integerValue;
    }
    NSUInteger pinnedCount = 0;
    NSNumber *pinnedValue = session[BrowserWindowSessionPinnedCountKey];
    if ([pinnedValue isKindOfClass:[NSNumber class]]) {
        pinnedCount = pinnedValue.unsignedIntegerValue;
    }
    [self.tabController restoreTabsFromEntries:tabs
                                 selectedIndex:selectedIndex
                                   pinnedCount:pinnedCount];
}

- (NSDictionary *)sessionDictionary {
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

    if (entries.count == 0) {
        return @{
            BrowserWindowSessionTabsKey: @[BrowserTabSessionNewTabMarker],
            BrowserWindowSessionSelectedIndexKey: @0,
            BrowserWindowSessionPinnedCountKey: @0,
        };
    }

    NSInteger selectedIndex = [self.tabController indexOfSelectedTab];
    if (selectedIndex == NSNotFound) {
        selectedIndex = 0;
    }

    NSMutableDictionary *session = [[NSMutableDictionary alloc] init];
    session[BrowserWindowSessionTabsKey] = [entries copy];
    session[BrowserWindowSessionSelectedIndexKey] = @(selectedIndex);
    session[BrowserWindowSessionPinnedCountKey] = @(self.tabController.pinnedTabCount);
    if (self.window) {
        session[BrowserWindowSessionFrameKey] = NSStringFromRect(self.window.frame);
    }
    return [session copy];
}

#pragma mark - Tab Management

- (void)detachWebViewIfNeeded:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    [self cancelPendingSSLAuthForWebView:webView];
    // 切走标签时若仍在 HTML5 全屏，先退出，避免全屏窗口孤儿化。
    if (@available(macOS 13.0, *)) {
        if (webView.fullscreenState != WKFullscreenStateNotInFullscreen) {
            [webView closeAllMediaPresentationsWithCompletionHandler:^{}];
        }
    }
    if (webView == self.observedFullscreenWebView) {
        [self stopObservingFullscreenState];
    }
    if (webView.superview == self.contentContainer) {
        [webView removeFromSuperview];
    }
}

/// 用 autoresizing 铺满 contentContainer。
/// Element Fullscreen 时 WebKit 会移走 WKWebView 并剥掉 Auto Layout 约束；
/// 若 translatesAutoresizingMaskIntoConstraints=NO 且无约束，视图尺寸为 0 → 黑/白屏（抖音等用 div 全屏时尤甚）。
- (void)pinWebViewLayoutInSuperview:(WKWebView *)webView {
    if (webView == nil || webView.superview == nil) {
        return;
    }
    NSView *superview = webView.superview;
    if (superview == self.contentContainer) {
        NSMutableArray<NSLayoutConstraint *> *owned = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in self.contentContainer.constraints) {
            if (constraint.firstItem == webView || constraint.secondItem == webView) {
                [owned addObject:constraint];
            }
        }
        if (owned.count > 0) {
            [NSLayoutConstraint deactivateConstraints:owned];
        }
    }
    webView.translatesAutoresizingMaskIntoConstraints = YES;
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    webView.frame = superview.bounds;
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
        browserWebView.openURLInNewWindowHandler = ^(NSURL *url) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            id delegate = NSApp.delegate;
            if ([delegate respondsToSelector:@selector(openURLInNewBrowserWindow:)] && url) {
                [(AppDelegate *)delegate openURLInNewBrowserWindow:url];
            } else {
                [strongSelf.tabController addTabWithURL:url];
            }
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

    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.hidden = tab.isNewTabPage;

    __weak typeof(self) weakSelf = self;
    tab.titleDidChangeHandler = ^(BrowserTab *changedTab) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf updateTabStripDisplay];
        if (changedTab.webView == strongSelf.webView) {
            [strongSelf setDisplayedWindowTitle:changedTab.displayTitle];
        }
        [strongSelf schedulePersistTabSession];
    };
    // 挂上时立刻拉一次，避免错过 Initial KVO 之前的 title。
    [tab pullDocumentTitleFromWebView];

    if (webView.superview != self.contentContainer) {
        [self.contentContainer addSubview:webView];
    }
    [self pinWebViewLayoutInSuperview:webView];
    [self observeFullscreenStateForSelectedTab];
}

- (void)refreshTabsUI {
    BrowserTab *selectedTab = self.tabController.selectedTab;

    // 仅挂载当前标签的 WebView；其余离屏但仍可常驻（休眠由 TabController 销毁）。
    // 即将 detach 的存活页先写入缩略图缓存（异步，不阻塞切页）。
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab == selectedTab) {
            continue;
        }
        WKWebView *wv = tab.webView;
        if (wv != nil && wv.superview == self.contentContainer && !tab.isNewTabPage) {
            [self.tabOverviewController.thumbnailCache captureFromWebView:wv
                                                                 forTabID:tab.tabID
                                                               completion:nil];
        }
        [self detachWebViewIfNeeded:wv];
    }

    if (selectedTab != nil && !selectedTab.isNewTabPage) {
        // 先创建 WebView → 挂 navigationDelegate → 再 load。
        // 若先 load，document-start 写回 #hash 时无 delegate，代理下会把 # 编成 %23 → 404。
        [selectedTab wakeFromHibernationIfNeeded];
        [self attachWebViewForTab:selectedTab];
        [selectedTab loadPendingRestorableURLIfNeeded];
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
    [self.contentContainer addSubview:self.certificateWarningView positioned:NSWindowAbove relativeTo:nil];
    [self.contentContainer addSubview:self.navigationErrorView positioned:NSWindowAbove relativeTo:nil];
    if (self.findBarController.isVisible) {
        [self.contentContainer addSubview:self.findBarController.findBarView positioned:NSWindowAbove relativeTo:nil];
    }
    if (self.tabOverviewController.isVisible) {
        [self.tabOverviewController bringToFront];
        [self.tabOverviewController reloadFromTabController];
    }
    [self.findBarController syncWithSelectedTab];
    [self observeLoadingProgressForSelectedTab];

    // 切换标签时结束地址栏编辑，避免不安全徽章的 leading inset 留在 field editor 里带到新标签。
    [self endAddressBarEditingIfNeeded];

    // sync：顺序/数量不变时保留标签视图，避免 mouseDown 选中后重建导致拖拽失效
    [self updateTabStripDisplay];
    [self repositionTrafficLightButtonsAfterLayout];
    [self updateNavigationState];
    [self syncCertificateWarningVisibilityForSelectedTab];
    [self syncNavigationErrorVisibilityForSelectedTab];
    [self updateTabOverviewButtonAppearance];

    NSUUID *selectedID = selectedTab.tabID;
    BOOL selectionChanged = selectedID != nil
        && ![selectedID isEqual:self.lastSelectedTabIDForAddressFocus];
    self.lastSelectedTabIDForAddressFocus = selectedID;
    if (selectionChanged && selectedTab.isNewTabPage) {
        [self focusAddressBarForNewTabPage];
    }
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

- (void)stopObservingFullscreenState {
    WKWebView *webView = self.observedFullscreenWebView;
    if (!webView) {
        return;
    }
    if (@available(macOS 13.0, *)) {
        @try {
            [webView removeObserver:self
                         forKeyPath:@"fullscreenState"
                            context:kBrowserFullscreenStateContext];
        } @catch (__unused NSException *exception) {
        }
    }
    self.observedFullscreenWebView = nil;
}

- (void)observeFullscreenStateForSelectedTab {
    if (@available(macOS 13.0, *)) {
        WKWebView *webView = self.webView;
        BrowserTab *tab = self.tabController.selectedTab;
        if (webView == self.observedFullscreenWebView) {
            return;
        }
        [self stopObservingFullscreenState];
        if (!webView || tab.isNewTabPage) {
            return;
        }
        self.observedFullscreenWebView = webView;
        [webView addObserver:self
                  forKeyPath:@"fullscreenState"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                     context:kBrowserFullscreenStateContext];
    }
}

- (void)handleWebViewFullscreenStateChange:(WKWebView *)webView {
    if (@available(macOS 13.0, *)) {
        // 全屏过程中 WebKit 会把 WKWebView 挪到自有窗口并清约束；立即用 autoresizing 铺满，避免 0 尺寸空白。
        switch (webView.fullscreenState) {
            case WKFullscreenStateEnteringFullscreen:
            case WKFullscreenStateInFullscreen:
            case WKFullscreenStateExitingFullscreen:
                [self pinWebViewLayoutInSuperview:webView];
                break;
            case WKFullscreenStateNotInFullscreen:
                if (webView.superview == self.contentContainer) {
                    [self pinWebViewLayoutInSuperview:webView];
                } else if (webView.superview == nil &&
                           self.tabController.selectedTab.webView == webView &&
                           !self.tabController.selectedTab.isNewTabPage) {
                    [self.contentContainer addSubview:webView];
                    [self pinWebViewLayoutInSuperview:webView];
                }
                break;
        }
    }
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
        // stop() 后 isLoading 已为 NO，但 tab 仍可能标记加载中。
        if (tab.isLoading && !webView.isLoading) {
            [self syncFromWebView:webView];
            return;
        }
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
    if (context == kBrowserFullscreenStateContext) {
        if ([keyPath isEqualToString:@"fullscreenState"] && [object isKindOfClass:[WKWebView class]]) {
            [self handleWebViewFullscreenStateChange:(WKWebView *)object];
        }
        return;
    }
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
    // hash 恢复后 stop() 可能不走 didFinish；进度到 1 或已非 loading 时收尾 UI。
    if (tab.isLoading && (!webView.isLoading || progress >= 1.0)) {
        [self syncFromWebView:webView];
        return;
    }
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
    id delegate = NSApp.delegate;
    if ([delegate respondsToSelector:@selector(persistAllBrowserWindowSessions)]) {
        [(AppDelegate *)delegate persistAllBrowserWindowSessions];
        return;
    }
    [BrowsingPreferences saveWindowSessions:@[[self sessionDictionary]]];
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

- (void)tabStripViewDidRequestShowTabOverview:(id)stripView {
    (void)stripView;
    [self showTabOverview];
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

- (void)tabStripView:(id)stripView
didRequestMoveTabIDToNewWindow:(NSUUID *)tabID
         screenPoint:(NSPoint)screenPoint {
    (void)stripView;
    [self moveTabIDToNewWindow:tabID screenPoint:screenPoint];
}

- (void)tabStripView:(id)stripView
didRequestTransferTabID:(NSUUID *)tabID
           toWindow:(BrowserWindowController *)destination
            atIndex:(NSUInteger)index {
    (void)stripView;
    [self transferTabID:tabID toWindow:destination atIndex:index];
}

- (void)transferTabID:(NSUUID *)tabID
             toWindow:(BrowserWindowController *)destination
              atIndex:(NSUInteger)index {
    if (!destination || destination == self) {
        return;
    }
    BrowserTab *tab = [self tabForID:tabID];
    if (!tab) {
        return;
    }

    if (tab == self.tabController.selectedTab) {
        [self stopObservingLoadingProgress];
    }
    tab.titleDidChangeHandler = nil;
    [self detachWebViewIfNeeded:tab.webView];

    BOOL wasLastTab = (self.tabController.tabs.count <= 1);
    BrowserTab *moved = [self.tabController extractTabKeepingAlive:tab];
    if (!moved) {
        return;
    }

    [destination adoptTab:moved atIndex:index];
    [destination.window makeKeyAndOrderFront:nil];

    if (wasLastTab || self.tabController.tabs.count == 0) {
        [self.window close];
    } else {
        [self refreshTabsUI];
        [self schedulePersistTabSession];
    }
}

- (void)moveTabIDToNewWindow:(NSUUID *)tabID screenPoint:(NSPoint)screenPoint {
    BrowserTab *tab = [self tabForID:tabID];
    if (!tab) {
        return;
    }

    NSSize defaultSize = self.window ? self.window.frame.size : NSMakeSize(1024, 700);
    if (defaultSize.width < 400) {
        defaultSize.width = 1024;
    }
    if (defaultSize.height < 300) {
        defaultSize.height = 700;
    }

    NSRect newFrame = NSMakeRect(screenPoint.x - 60.0,
                                 screenPoint.y - defaultSize.height + 24.0,
                                 defaultSize.width,
                                 defaultSize.height);
    NSScreen *screen = [NSScreen mainScreen];
    for (NSScreen *candidate in [NSScreen screens]) {
        if (NSPointInRect(screenPoint, candidate.frame)) {
            screen = candidate;
            break;
        }
    }
    NSRect visible = screen.visibleFrame;
    if (NSMaxX(newFrame) > NSMaxX(visible)) {
        newFrame.origin.x = NSMaxX(visible) - NSWidth(newFrame);
    }
    if (NSMinX(newFrame) < NSMinX(visible)) {
        newFrame.origin.x = NSMinX(visible);
    }
    if (NSMinY(newFrame) < NSMinY(visible)) {
        newFrame.origin.y = NSMinY(visible);
    }
    if (NSMaxY(newFrame) > NSMaxY(visible)) {
        newFrame.origin.y = NSMaxY(visible) - NSHeight(newFrame);
    }

    id delegate = NSApp.delegate;
    if (![delegate respondsToSelector:@selector(createBrowserWindowAdoptingTab:frame:)]) {
        return;
    }

    if (tab == self.tabController.selectedTab) {
        [self stopObservingLoadingProgress];
    }
    tab.titleDidChangeHandler = nil;
    [self detachWebViewIfNeeded:tab.webView];

    BOOL wasLastTab = (self.tabController.tabs.count <= 1);
    BrowserTab *moved = [self.tabController extractTabKeepingAlive:tab];
    if (!moved) {
        return;
    }

    // 整页迁移 BrowserTab（含存活 WKWebView），不按 URL 重新加载。
    BrowserWindowController *newController =
        [(AppDelegate *)delegate createBrowserWindowAdoptingTab:moved frame:newFrame];
    [newController.window makeKeyAndOrderFront:nil];

    if (wasLastTab || self.tabController.tabs.count == 0) {
        [self.window close];
    } else {
        [self refreshTabsUI];
        [self schedulePersistTabSession];
    }
}

- (void)adoptTab:(BrowserTab *)tab {
    [self adoptTab:tab atIndex:NSUIntegerMax];
}

- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index {
    if (!tab) {
        return;
    }
    if (index == NSUIntegerMax) {
        [self.tabController adoptTab:tab];
    } else {
        [self.tabController adoptTab:tab atIndex:index];
    }
    [self refreshTabsUI];
    [self schedulePersistTabSession];
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

- (void)openCurrentPageInNewBrowserWindow:(id)sender {
    (void)sender;
    id delegate = NSApp.delegate;
    if (![delegate respondsToSelector:@selector(openURLInNewBrowserWindow:)]) {
        return;
    }
    BrowserTab *tab = self.tabController.selectedTab;
    NSURL *url = nil;
    if (tab && !tab.isNewTabPage) {
        url = [tab currentOrRestorableURL];
    }
    if ([BrowsingPreferences isPersistableURL:url]) {
        [(AppDelegate *)delegate openURLInNewBrowserWindow:url];
    } else {
        [(AppDelegate *)delegate newBrowserWindow:nil];
    }
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

- (nullable NSURL *)currentSendableURL {
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        return nil;
    }
    NSURL *url = [tab currentOrRestorableURL];
    if (![BrowsingPreferences isPersistableURL:url]) {
        return nil;
    }
    return url;
}

- (void)sendCurrentTabToPhone:(id)sender {
    (void)sender;
    NSURL *url = [self currentSendableURL];
    if (!url) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法发送到手机";
        alert.informativeText = @"当前标签页没有可发送的网页地址。";
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    BrowserTab *tab = self.tabController.selectedTab;
    BOOL ok = [[CompanionChannel sharedChannel] sendOpenURLToPhone:url title:tab.title];
    if (!ok) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"未连接手机";
        alert.informativeText = @"请先在「互联与配对」中配对，并确保手机与 Mac 在同一局域网且已连接。";
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    [BrowserTransientToast showMessage:@"已发送到手机" inWindow:self.window duration:2.0];
}

#pragma mark - Navigation Actions

- (void)goBack:(id)sender {
    (void)sender;
    [self cancelPendingSSLAuthForWebView:self.webView];
    [self clearNavigationErrorForWebView:self.webView];
    [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    [self cancelPendingSSLAuthForWebView:self.webView];
    [self clearNavigationErrorForWebView:self.webView];
    [self.webView goForward];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab.isHibernated) {
        [self refreshTabsUI];
        return;
    }
    [self cancelPendingSSLAuthForWebView:self.webView];
    BrowserPendingNavigationError *pending =
        [self.pendingNavigationErrorByWebView objectForKey:self.webView];
    NSURL *reloadURL = pending.failingURL;
    [self clearNavigationErrorForWebView:self.webView];
    if (reloadURL) {
        [self.webView loadRequest:[NSURLRequest requestWithURL:reloadURL]];
    } else {
        [self.webView reload];
    }
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
    if (action == @selector(showFindBar:) ||
        action == @selector(toggleFindBar:) ||
        action == @selector(findNext:) ||
        action == @selector(findPrevious:) ||
        action == @selector(useSelectionForFind:)) {
        return [self.findBarController canFindInCurrentPage];
    }
    if (action == @selector(restoreRecentlyClosedBrowserTab:)) {
        return self.tabController.canRestoreRecentlyClosedTab;
    }
    if (action == @selector(sendCurrentTabToPhone:)) {
        return [CompanionChannel sharedChannel].state == CompanionChannelStateConnected
            && [self currentSendableURL] != nil;
    }
    if (action == @selector(oneClickLogin:)) {
        return self.loginAssistController.loginButton.enabled;
    }
    if (action == @selector(fillSiteMemo:)) {
        return YES;
    }
    if (action == @selector(toggleAssistSidebar:) || action == @selector(showAssistSidebar:)) {
        return YES;
    }
    if (action == @selector(toggleCaptchaAssistPanel:)) {
        return YES;
    }
    if (action == @selector(toggleNotificationInboxSidebar:)) {
        return YES;
    }
    if (action == @selector(toggleTabOverview:) || action == @selector(showTabOverview)) {
        return YES;
    }
    return YES;
}

- (void)showFindBar:(id)sender {
    [self.findBarController showFindBar:sender];
}

- (void)toggleFindBar:(id)sender {
    [self.findBarController toggleFindBar:sender];
}

- (void)toggleTabOverview:(id)sender {
    (void)sender;
    if (self.tabOverviewController.isVisible) {
        [self hideTabOverview];
    } else {
        [self showTabOverview];
    }
}

- (void)showTabOverview {
    [self.findBarController hideFindBarClearingHighlights:YES];
    [self.tabOverviewController showOverview];
    [self updateTabOverviewButtonAppearance];
}

- (void)hideTabOverview {
    [self.tabOverviewController hideOverview];
    [self updateTabOverviewButtonAppearance];
}

- (BOOL)isTabOverviewVisible {
    return self.tabOverviewController.isVisible;
}

- (void)findNext:(id)sender {
    [self.findBarController findNext:sender];
}

- (void)findPrevious:(id)sender {
    [self.findBarController findPrevious:sender];
}

- (void)useSelectionForFind:(id)sender {
    [self.findBarController useSelectionForFind:sender];
}

- (void)oneClickLogin:(id)sender {
    [self.loginAssistController oneClickLogin:sender];
}

- (void)fillSiteMemo:(id)sender {
    [self.loginAssistController fillSiteMemo:sender];
}

- (void)showLoginAssistSettings:(id)sender {
    (void)sender;
    if (self.notificationSidebarController.visible) {
        [self.trailingSidebarSlot setNotificationVisible:NO animated:YES];
        [self updateNotificationInboxButtonAppearance];
    }
    [self.assistSidebarController revealRecipeID:nil];
}

- (void)showFormMemoSettings:(id)sender {
    (void)sender;
    if (self.notificationSidebarController.visible) {
        [self.trailingSidebarSlot setNotificationVisible:NO animated:YES];
        [self updateNotificationInboxButtonAppearance];
    }
    [self.assistSidebarController revealMemoID:nil];
}

- (void)reloadAssistSidebarIfVisible {
    if (self.assistSidebarController.visible) {
        [self.assistSidebarController reloadList];
    }
}

- (void)toggleCaptchaAssistPanel:(id)sender {
    [self.captchaAssistController toggleCaptchaAssistPanel:sender];
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
        [self cancelPendingSSLAuthForWebView:tab.webView];
        [self clearNavigationErrorForWebView:tab.webView];
        [tab loadURL:url];
        [self refreshTabsUI];
    }
}

- (nullable NSURL *)normalizedURLFromString:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSURL *navigable = [BrowserURLInputClassifier navigableURLFromInput:trimmed];
    if (navigable) {
        return navigable;
    }
    return [BrowsingPreferences searchURLForQuery:trimmed];
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
        [self updateSecurityBadgeVisibility];
        [self.loginAssistController updateForURL:nil];
        [self reloadAssistSidebarIfVisible];
        [self.captchaAssistController updateForURL:nil];
        [self.feedAssistController updateForURL:nil];
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
    [self updateConnectionSecurityStateForTab:tab webView:webView];
    [self updateSecurityBadgeVisibility];
    [self.loginAssistController updateForURL:webView.URL];
    [self reloadAssistSidebarIfVisible];
    [self.captchaAssistController updateForURL:webView.URL];
    [self.feedAssistController updateForURL:webView.URL];
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"确定"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        self.addressFieldIsEditing = YES;
        [self updateSecurityBadgeVisibility];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        self.addressFieldIsEditing = NO;
        [self updateSecurityBadgeVisibility];
    }
}

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

#pragma mark - Certificate / SSL

- (BOOL)isCertificateRelatedError:(NSError *)error {
    if (!error) {
        return NO;
    }
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateUntrusted:
            case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid:
            case NSURLErrorClientCertificateRejected:
            case NSURLErrorClientCertificateRequired:
                return YES;
            default:
                break;
        }
    }
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:[NSError class]] && [self isCertificateRelatedError:underlying]) {
        return YES;
    }
    NSString *description = error.localizedDescription.lowercaseString;
    if ([description containsString:@"certificate"] || [description containsString:@"ssl"] ||
        [description containsString:@"tls"] || [description containsString:@"证书"]) {
        return YES;
    }
    return NO;
}

- (BOOL)serverTrustIsTrusted:(SecTrustRef)trust {
    if (!trust) {
        return NO;
    }
    return SecTrustEvaluateWithError(trust, NULL);
}

- (void)cancelPendingSSLAuthForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserPendingSSLAuth *pending = [self.pendingSSLAuthByWebView objectForKey:webView];
    if (!pending) {
        return;
    }
    [self.pendingSSLAuthByWebView removeObjectForKey:webView];
    [pending finishWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge credential:nil];
    if (webView == self.webView) {
        [self hideCertificateWarningOverlay];
    }
}

- (void)cancelAllPendingSSLAuthWithDisposition:(NSURLSessionAuthChallengeDisposition)disposition {
    NSArray<BrowserPendingSSLAuth *> *pendings = self.pendingSSLAuthByWebView.objectEnumerator.allObjects;
    [self.pendingSSLAuthByWebView removeAllObjects];
    for (BrowserPendingSSLAuth *pending in pendings) {
        [pending finishWithDisposition:disposition credential:nil];
    }
    [self hideCertificateWarningOverlay];
}

- (void)showCertificateWarningForPending:(BrowserPendingSSLAuth *)pending {
    if (!pending || pending.webView != self.webView) {
        return;
    }
    [self.certificateWarningView configureWithHost:pending.hostDisplay];
    self.certificateWarningView.hidden = NO;
    [self.contentContainer addSubview:self.certificateWarningView positioned:NSWindowAbove relativeTo:nil];
    [self.loadingProgressView resetHidden];
}

- (void)hideCertificateWarningOverlay {
    self.certificateWarningView.hidden = YES;
}

- (void)syncCertificateWarningVisibilityForSelectedTab {
    WKWebView *webView = self.webView;
    if (!webView) {
        [self hideCertificateWarningOverlay];
        return;
    }
    BrowserPendingSSLAuth *pending = [self.pendingSSLAuthByWebView objectForKey:webView];
    if (pending && !pending.completionInvoked) {
        [self showCertificateWarningForPending:pending];
    } else {
        [self hideCertificateWarningOverlay];
    }
}

- (void)clearNavigationErrorForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    [self.pendingNavigationErrorByWebView removeObjectForKey:webView];
    if (webView == self.webView) {
        [self hideNavigationErrorOverlay];
    }
}

- (void)showNavigationErrorForPending:(BrowserPendingNavigationError *)pending {
    if (!pending || pending.webView != self.webView) {
        return;
    }
    [self.navigationErrorView configureWithTitle:pending.title
                                         message:pending.message
                                      showGoBack:pending.canGoBack];
    self.navigationErrorView.hidden = NO;
    [self.contentContainer addSubview:self.navigationErrorView positioned:NSWindowAbove relativeTo:nil];
    [self.loadingProgressView resetHidden];
}

- (void)hideNavigationErrorOverlay {
    self.navigationErrorView.hidden = YES;
}

- (void)syncNavigationErrorVisibilityForSelectedTab {
    WKWebView *webView = self.webView;
    if (!webView) {
        [self hideNavigationErrorOverlay];
        return;
    }
    // 证书警告优先；两者不同时显示。
    BrowserPendingSSLAuth *sslPending = [self.pendingSSLAuthByWebView objectForKey:webView];
    if (sslPending && !sslPending.completionInvoked) {
        [self hideNavigationErrorOverlay];
        return;
    }
    BrowserPendingNavigationError *pending = [self.pendingNavigationErrorByWebView objectForKey:webView];
    if (pending) {
        [self showNavigationErrorForPending:pending];
    } else {
        [self hideNavigationErrorOverlay];
    }
}

- (void)presentNavigationErrorForWebView:(WKWebView *)webView
                                   title:(NSString *)title
                                 message:(NSString *)message
                              failingURL:(NSURL *)failingURL {
    if (!webView) {
        return;
    }
    BrowserPendingNavigationError *pending = [[BrowserPendingNavigationError alloc] init];
    pending.webView = webView;
    pending.title = title.length > 0 ? title : @"无法加载页面";
    pending.message = message.length > 0 ? message : @"发生未知错误。";
    pending.failingURL = failingURL;
    pending.canGoBack = webView.canGoBack;
    [self.pendingNavigationErrorByWebView setObject:pending forKey:webView];

    if (webView == self.webView) {
        [self showNavigationErrorForPending:pending];
        if (failingURL.absoluteString.length > 0 && !self.addressFieldIsEditing) {
            self.addressField.stringValue = failingURL.absoluteString;
            BrowserTab *tab = [self.tabController tabForWebView:webView];
            tab.addressBarDraft = nil;
        }
    }
}

- (void)cancelProvisionalNavigationWatchdogForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserProvisionalNavigationWatchdog *watchdog =
        [self.provisionalWatchdogByWebView objectForKey:webView];
    if (!watchdog) {
        return;
    }
    if (watchdog.block) {
        dispatch_block_cancel(watchdog.block);
        watchdog.block = nil;
    }
    [self.provisionalWatchdogByWebView removeObjectForKey:webView];
}

- (void)scheduleProvisionalNavigationWatchdogForWebView:(WKWebView *)webView
                                          provisionalURL:(NSURL *)provisionalURL {
    if (!webView) {
        return;
    }
    [self cancelProvisionalNavigationWatchdogForWebView:webView];

    BrowserProvisionalNavigationWatchdog *watchdog = [[BrowserProvisionalNavigationWatchdog alloc] init];
    watchdog.webView = webView;
    watchdog.provisionalURL = provisionalURL;
    static NSInteger sToken = 0;
    watchdog.token = ++sToken;
    [self.provisionalWatchdogByWebView setObject:watchdog forKey:webView];

    NSInteger token = watchdog.token;
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView) {
            return;
        }
        BrowserProvisionalNavigationWatchdog *current =
            [strongSelf.provisionalWatchdogByWebView objectForKey:strongWebView];
        if (!current || current.token != token) {
            return;
        }
        [strongSelf fireProvisionalNavigationWatchdog:current];
    });
    watchdog.block = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(BrowserMainFrameNavigationTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)fireProvisionalNavigationWatchdog:(BrowserProvisionalNavigationWatchdog *)watchdog {
    WKWebView *webView = watchdog.webView;
    if (!webView) {
        return;
    }
    NSURL *failingURL = watchdog.provisionalURL ?: webView.URL;
    [self cancelProvisionalNavigationWatchdogForWebView:webView];

    // stopLoading 会触发 Cancelled 失败回调（被忽略）；此处直接展示超时错误页。
    [webView stopLoading];

    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = NO;
    [self updateTabStripDisplay];
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
    }
    [self presentNavigationErrorForWebView:webView
                                     title:@"无法加载页面"
                                   message:[self userFacingMessageForNavigationErrorCode:NSURLErrorTimedOut
                                                                   fallbackDescription:nil]
                                failingURL:failingURL];
    if (webView == self.webView) {
        [self updateNavigationState];
    }
}

- (NSString *)userFacingMessageForNavigationError:(NSError *)error {
    if (![error.domain isEqualToString:NSURLErrorDomain]) {
        return error.localizedDescription.length > 0 ? error.localizedDescription : @"发生未知错误。";
    }
    return [self userFacingMessageForNavigationErrorCode:error.code
                                   fallbackDescription:error.localizedDescription];
}

- (NSString *)userFacingMessageForNavigationErrorCode:(NSInteger)code
                                fallbackDescription:(NSString *)fallback {
    switch (code) {
        case NSURLErrorTimedOut:
            return @"连接超时，无法打开该网页。目标站点可能不可达，或当前网络需要代理。";
        case NSURLErrorCannotConnectToHost:
            return @"无法连接到服务器。目标站点可能不可达，或当前网络需要代理。";
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed:
            return @"找不到服务器。请检查网址是否正确。";
        case NSURLErrorNotConnectedToInternet:
            return @"未连接到互联网。请检查网络设置。";
        case NSURLErrorNetworkConnectionLost:
            return @"网络连接已中断。";
        case NSURLErrorSecureConnectionFailed:
            return @"安全连接失败。服务器可能不可达，或证书/协议不兼容。";
        default:
            break;
    }
    return fallback.length > 0 ? fallback : @"发生未知错误。";
}

- (void)presentCertificateWarningForWebView:(WKWebView *)webView
                                    hostKey:(NSString *)hostKey
                                hostDisplay:(NSString *)hostDisplay
                                  challenge:(NSURLAuthenticationChallenge *)challenge
                          completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
                          fallbackReloadURL:(NSURL *)fallbackReloadURL {
    [self cancelPendingSSLAuthForWebView:webView];

    BrowserPendingSSLAuth *pending = [[BrowserPendingSSLAuth alloc] init];
    pending.webView = webView;
    pending.hostKey = hostKey;
    pending.hostDisplay = hostDisplay.length > 0 ? hostDisplay : hostKey;
    pending.challenge = challenge;
    pending.completionHandler = completionHandler;
    pending.fallbackReloadURL = fallbackReloadURL;
    [self.pendingSSLAuthByWebView setObject:pending forKey:webView];

    if (webView == self.webView) {
        [self showCertificateWarningForPending:pending];
        self.addressField.stringValue = fallbackReloadURL.absoluteString.length > 0
            ? fallbackReloadURL.absoluteString
            : [NSString stringWithFormat:@"https://%@", hostDisplay];
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        tab.addressBarDraft = nil;
        [self updateSecurityBadgeVisibility];
    }
}

- (void)updateConnectionSecurityStateForTab:(BrowserTab *)tab webView:(WKWebView *)webView {
    if (!tab || tab.isNewTabPage || !webView) {
        if (tab) {
            tab.connectionSecurityState = BrowserConnectionSecurityStateUnknown;
        }
        return;
    }
    NSURL *url = webView.URL;
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) {
        tab.connectionSecurityState = BrowserConnectionSecurityStateUnknown;
        return;
    }
    if ([[BrowserSSLExceptionStore sharedStore] allowsURL:url]) {
        tab.connectionSecurityState = BrowserConnectionSecurityStateInsecureException;
    } else {
        tab.connectionSecurityState = BrowserConnectionSecurityStateTrusted;
    }
}

- (void)endAddressBarEditingIfNeeded {
    NSWindow *window = self.window;
    id firstResponder = window.firstResponder;
    NSText *editor = self.addressField.currentEditor;
    BOOL addressIsFocused = (firstResponder == self.addressField)
        || (editor != nil && firstResponder == editor);
    if (addressIsFocused) {
        [window makeFirstResponder:nil];
    }
    self.addressFieldIsEditing = NO;
}

/// 切换到新标签页（含新建）时聚焦地址栏。
/// 延后到下一轮 runloop，避免标签栏点击链路结束后仍占住第一响应者。
- (void)focusAddressBarForNewTabPage {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BrowserTab *tab = strongSelf.tabController.selectedTab;
        if (!tab.isNewTabPage) {
            return;
        }
        [strongSelf.window makeFirstResponder:strongSelf.addressField];
    });
}

- (void)updateSecurityBadgeVisibility {
    BrowserTab *tab = self.tabController.selectedTab;
    BOOL show = tab != nil
        && !tab.isNewTabPage
        && tab.connectionSecurityState == BrowserConnectionSecurityStateInsecureException
        && self.certificateWarningView.hidden;
    [self.addressBarRow setSecurityBadgeVisible:show
                                 preferredWidth:BrowserSecurityBadgeContentWidth()];
}

- (void)showInsecureConnectionDetails:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    WKWebView *webView = self.webView;
    NSURL *url = webView.URL;
    NSString *hostKey = [BrowserSSLExceptionStore hostKeyForURL:url];
    NSString *host = url.host.length > 0 ? url.host : @"此站点";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"连接不安全";
    alert.informativeText =
        [NSString stringWithFormat:
         @"「%@」使用了无效或不受信任的证书。流量仍可能被加密，但无法验证你访问的是否为真正的服务器。",
         host];
    [alert addButtonWithTitle:@"知道了"];
    if (hostKey.length > 0) {
        [alert addButtonWithTitle:@"停止信任此主机"];
    }
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertSecondButtonReturn || hostKey.length == 0) {
            return;
        }
        [[BrowserSSLExceptionStore sharedStore] revokeHostKey:hostKey];
        if (tab) {
            tab.connectionSecurityState = BrowserConnectionSecurityStateUnknown;
        }
        [self updateSecurityBadgeVisibility];
        if (url) {
            [webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }];
}

- (void)certificateWarningViewDidChooseGoBack:(BrowserCertificateWarningView *)view {
    (void)view;
    WKWebView *webView = self.webView;
    BrowserPendingSSLAuth *pending = webView ? [self.pendingSSLAuthByWebView objectForKey:webView] : nil;
    if (pending) {
        [self.pendingSSLAuthByWebView removeObjectForKey:webView];
        [pending finishWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge credential:nil];
    }
    [self hideCertificateWarningOverlay];
    if (webView.canGoBack) {
        [webView goBack];
    }
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = NO;
    [self updateNavigationState];
    [self updateTabStripDisplay];
}

- (void)certificateWarningViewDidChooseProceed:(BrowserCertificateWarningView *)view {
    (void)view;
    WKWebView *webView = self.webView;
    BrowserPendingSSLAuth *pending = webView ? [self.pendingSSLAuthByWebView objectForKey:webView] : nil;
    if (!pending) {
        [self hideCertificateWarningOverlay];
        return;
    }

    [[BrowserSSLExceptionStore sharedStore] allowHostKey:pending.hostKey];
    [self.pendingSSLAuthByWebView removeObjectForKey:webView];
    [self hideCertificateWarningOverlay];

    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.connectionSecurityState = BrowserConnectionSecurityStateInsecureException;

    if (pending.challenge.protectionSpace.serverTrust) {
        NSURLCredential *credential =
            [NSURLCredential credentialForTrust:pending.challenge.protectionSpace.serverTrust];
        [pending finishWithDisposition:NSURLSessionAuthChallengeUseCredential credential:credential];
        [self updateSecurityBadgeVisibility];
        return;
    }

    // 失败路径兜底：无挂起 challenge 时重新加载。
    NSURL *reloadURL = pending.fallbackReloadURL;
    [pending finishWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge credential:nil];
    if (reloadURL) {
        [webView loadRequest:[NSURLRequest requestWithURL:reloadURL]];
    }
    [self updateSecurityBadgeVisibility];
}

- (void)navigationErrorViewDidChooseReload:(BrowserNavigationErrorView *)view {
    (void)view;
    WKWebView *webView = self.webView;
    BrowserPendingNavigationError *pending =
        webView ? [self.pendingNavigationErrorByWebView objectForKey:webView] : nil;
    NSURL *reloadURL = pending.failingURL;
    [self clearNavigationErrorForWebView:webView];
    if (reloadURL) {
        [webView loadRequest:[NSURLRequest requestWithURL:reloadURL]];
    } else {
        [webView reload];
    }
}

- (void)navigationErrorViewDidChooseGoBack:(BrowserNavigationErrorView *)view {
    (void)view;
    WKWebView *webView = self.webView;
    [self clearNavigationErrorForWebView:webView];
    if (webView.canGoBack) {
        [webView goBack];
    }
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    tab.isLoading = NO;
    [self updateNavigationState];
    [self updateTabStripDisplay];
}

#pragma mark - WKNavigationDelegate

- (BOOL)isHTTPAuthMethod:(NSString *)authMethod {
    return [authMethod isEqualToString:NSURLAuthenticationMethodDefault]
        || [authMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic]
        || [authMethod isEqualToString:NSURLAuthenticationMethodHTTPDigest];
}

- (void)presentHTTPAuthPromptForWebView:(WKWebView *)webView
                              challenge:(NSURLAuthenticationChallenge *)challenge
                      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    NSWindow *window = self.window;
    if (!window || !webView) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    // 同一 WebView 已有登录框时，取消重复挑战，避免叠多个 sheet。
    if ([self.webViewsWithHTTPAuthPrompt containsObject:webView]) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (challenge.previousFailureCount == 0) {
        NSURLCredential *stored =
            [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        if (stored.user.length > 0 && stored.hasPassword) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, stored);
            return;
        }
    }

    [self.webViewsWithHTTPAuthPrompt addObject:webView];
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    [BrowserHTTPAuthPrompt presentForChallenge:challenge
                                      inWindow:window
                             completionHandler:^(BrowserHTTPAuthPromptResult * _Nullable result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (strongSelf && strongWebView) {
            [strongSelf.webViewsWithHTTPAuthPrompt removeObject:strongWebView];
        }
        if (!result) {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
            return;
        }

        NSURLCredentialPersistence persistence = result.rememberPassword
            ? NSURLCredentialPersistencePermanent
            : NSURLCredentialPersistenceForSession;
        NSURLCredential *credential = [NSURLCredential credentialWithUser:result.username ?: @""
                                                                 password:result.password ?: @""
                                                              persistence:persistence];
        NSURLCredentialStorage *storage = [NSURLCredentialStorage sharedCredentialStorage];
        if (result.rememberPassword) {
            [storage setDefaultCredential:credential forProtectionSpace:space];
        } else {
            NSURLCredential *existing = [storage defaultCredentialForProtectionSpace:space];
            if (existing) {
                [storage removeCredential:existing forProtectionSpace:space];
            }
        }
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    }];
}

- (void)webView:(WKWebView *)webView
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    NSString *authMethod = challenge.protectionSpace.authenticationMethod;

    if ([self isHTTPAuthMethod:authMethod]) {
        [self presentHTTPAuthPromptForWebView:webView
                                    challenge:challenge
                            completionHandler:completionHandler];
        return;
    }

    if (![authMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    NSString *host = challenge.protectionSpace.host ?: @"";
    NSInteger port = challenge.protectionSpace.port;
    NSString *hostKey = [BrowserSSLExceptionStore hostKeyForHost:host port:port];

    if ([[BrowserSSLExceptionStore sharedStore] allowsHostKey:hostKey] && trust) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        return;
    }

    if ([self serverTrustIsTrusted:trust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    NSURL *fallbackURL = nil;
    if (host.length > 0) {
        NSString *urlString = (port > 0 && port != 443)
            ? [NSString stringWithFormat:@"https://%@:%ld/", host, (long)port]
            : [NSString stringWithFormat:@"https://%@/", host];
        fallbackURL = [NSURL URLWithString:urlString];
    }

    [self presentCertificateWarningForWebView:webView
                                      hostKey:hostKey
                                  hostDisplay:host
                                    challenge:challenge
                            completionHandler:completionHandler
                            fallbackReloadURL:fallbackURL];
}

/// 同文档 #锚点：页面已 replaceState，但取消导航不会走 didCommit，须手写地址栏（含 #）。
- (void)applySameDocumentFragmentNavigation:(NSURL *)requestURL inWebView:(WKWebView *)webView {
    NSURL *publicURL = [BrowserWebView publicURLFromInternalURL:requestURL] ?: requestURL;
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (tab && [BrowsingPreferences isPersistableURL:publicURL]) {
        tab.restorableURL = publicURL;
        tab.addressBarDraft = nil;
    }
    // 先按目标 URL 立刻刷新，避免等 JS 回调期间地址栏仍无 #。
    if (tab && webView == self.webView && !self.addressFieldIsEditing) {
        self.addressField.stringValue = publicURL.absoluteString ?: @"";
        self.lastAddressBarTab = tab;
    }

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    [BrowserWebView applySameDocumentFragment:requestURL.fragment
                                    inWebView:webView
                                   completion:^(NSString *href) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView) {
            return;
        }
        BrowserTab *current = [strongSelf.tabController tabForWebView:strongWebView];
        if (!current) {
            return;
        }
        NSURL *hrefURL = nil;
        if (href.length > 0) {
            hrefURL = [BrowserWebView publicURLFromInternalURL:[NSURL URLWithString:href]];
        }
        if (!hrefURL) {
            hrefURL = publicURL;
        }
        if ([BrowsingPreferences isPersistableURL:hrefURL]) {
            current.restorableURL = hrefURL;
        }
        current.addressBarDraft = nil;
        if (strongWebView == strongSelf.webView && !strongSelf.addressFieldIsEditing) {
            strongSelf.addressField.stringValue = hrefURL.absoluteString ?: @"";
            strongSelf.lastAddressBarTab = current;
        }
        [strongSelf schedulePersistTabSession];
    }];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    // ⌘+点击链接：在新标签页中打开，取消当前页导航（避免与 createWebView 重复开页）
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated
        && (navigationAction.modifierFlags & NSEventModifierFlagCommand) != 0) {
        NSURL *url = navigationAction.request.URL;
        if (url) {
            [self.tabController addTabWithURL:url];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    // http: + fragment：经系统代理时 WebKit 可能把 # 编成 %23 打进路径 → 站点 404。
    // 同文档仅改 hash：取消联网导航，改用 replaceState；跨文档则剥离后加载。
    NSURL *requestURL = [BrowserWebView URLByNormalizingEmbeddedFragment:navigationAction.request.URL];
    BOOL isMainFrame = navigationAction.targetFrame.isMainFrame
        || (navigationAction.targetFrame == nil && navigationAction.sourceFrame == nil);
    BOOL sameDocument = [BrowserWebView URL:requestURL isSameDocumentAsURL:webView.URL];
    if (isMainFrame
        && [BrowserWebView shouldStripFragmentForNetworkLoadOfURL:requestURL]
        && [webView isKindOfClass:[BrowserWebView class]]) {
        if (sameDocument) {
            decisionHandler(WKNavigationActionPolicyCancel);
            // 取消后不会走 didCommit；须主动把地址栏写成带 # 的 URL。
            [self applySameDocumentFragmentNavigation:requestURL inWebView:webView];
            return;
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        NSMutableURLRequest *retry = [navigationAction.request mutableCopy];
        retry.URL = requestURL;
        retry.timeoutInterval = BrowserMainFrameNavigationTimeout;
        [webView loadRequest:retry];
        return;
    }

    // 同文档 hash 变更不会走 provisional 回调；若仍 notePending 会扰乱 isLoading / didFinish。
    // targetFrame 在 loadRequest / 部分主框架导航时可能为 nil，须与上方 isMainFrame 判定一致，
    // 否则地址栏打开的页面不会进入主框架跟踪，标签标题一直停在 host。
    if (isMainFrame && !sameDocument) {
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        [tab notePendingMainFrameNavigation];
        if (requestURL) {
            [self.pendingProvisionalURLByWebView setObject:requestURL forKey:webView];
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([self.feedAssistController handleNavigationResponseIfFeed:navigationResponse
                                                          webView:webView
                                                  decisionHandler:decisionHandler]) {
        return;
    }
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

    [self clearNavigationErrorForWebView:webView];
    [self.feedAssistController noteNavigationStartedInWebView:webView];
    tab.isLoading = YES;
    if (webView == self.webView) {
        [self.loadingProgressView beginLoading];
    }
    NSURL *provisionalURL = [self.pendingProvisionalURLByWebView objectForKey:webView];
    [self.pendingProvisionalURLByWebView removeObjectForKey:webView];
    if (!provisionalURL) {
        provisionalURL = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    }
    [self scheduleProvisionalNavigationWatchdogForWebView:webView provisionalURL:provisionalURL];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab isMainFrameNavigation:navigation]) {
        return;
    }
    [self cancelProvisionalNavigationWatchdogForWebView:webView];
    [self.findBarController noteNavigationCommittedInWebView:webView];

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    // 先按 publicURL（含从 __meo_hf 还原的 #）写入 restorable，避免后续 sync 丢锚点。
    if (tab.addressBarDraft == nil) {
        NSURL *publicURL = [BrowserWebView publicURLFromInternalURL:webView.URL];
        if ([BrowsingPreferences isPersistableURL:publicURL]) {
            tab.restorableURL = publicURL;
        }
    }
    [BrowserWebView cleanupHashRestoreQueryInWebView:webView completion:^(NSString *href) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView) {
            return;
        }
        BrowserTab *current = [strongSelf.tabController tabForWebView:strongWebView];
        if (!current || current.addressBarDraft != nil) {
            return;
        }
        NSURL *hrefURL = nil;
        if (href.length > 0) {
            hrefURL = [BrowserWebView publicURLFromInternalURL:[NSURL URLWithString:href]];
        }
        if (!hrefURL) {
            hrefURL = [BrowserWebView publicURLFromInternalURL:strongWebView.URL];
        }
        if ([BrowsingPreferences isPersistableURL:hrefURL]) {
            current.restorableURL = hrefURL;
        }
        if (strongWebView == strongSelf.webView && !strongSelf.addressFieldIsEditing) {
            [strongSelf applyAddressBarStringForTab:current];
        }
    }];

    // URL 在 commit 时已可用；尽早刷新星标，避免等 didFinish。
    if (webView == self.webView) {
        if (tab.addressBarDraft == nil) {
            [self applyAddressBarStringForTab:tab];
        }
        self.backButton.enabled = tab.isNewTabPage ? NO : webView.canGoBack;
        self.forwardButton.enabled = tab.isNewTabPage ? NO : webView.canGoForward;
        self.reloadButton.enabled = !tab.isNewTabPage;
        [self updateBookmarkButtonState];
        [self updateConnectionSecurityStateForTab:tab webView:webView];
        [self updateSecurityBadgeVisibility];
    }

    // commit 时 title 可能已有；先刷一次标签，后续 sync / 延迟再补全。
    if (!tab.isNewTabPage && webView.title.length > 0 && ![tab.title isEqualToString:webView.title]) {
        tab.title = webView.title;
        [self updateTabStripDisplay];
        if (webView == self.webView) {
            [self setDisplayedWindowTitle:tab.displayTitle];
        }
    }

    // hash 恢复脚本里的 window.stop() 可能让 isLoading 变 NO 却不回调 didFinish；
    // 轮询几次，避免标签/进度条一直转圈。
    for (NSInteger i = 1; i <= 8; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 200 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            WKWebView *strongWebView = weakWebView;
            if (!strongSelf || !strongWebView) {
                return;
            }
            BrowserTab *current = [strongSelf.tabController tabForWebView:strongWebView];
            if (!current || !current.isLoading) {
                return;
            }
            if (!strongWebView.isLoading || strongWebView.estimatedProgress >= 1.0) {
                if ([current isMainFrameNavigation:navigation]) {
                    [current endMainFrameNavigation:navigation];
                }
                [strongSelf syncFromWebView:strongWebView];
            }
        });
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab isMainFrameNavigation:navigation]) {
        return;
    }
    [self cancelProvisionalNavigationWatchdogForWebView:webView];
    [tab endMainFrameNavigation:navigation];
    [self syncFromWebView:webView];
    [self.feedAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
    if (webView == self.webView) {
        [self.loginAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
        [self.captchaAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
        [self.findBarController noteNavigationFinishedInWebView:webView];
        [self.tabOverviewController updateThumbnailForSelectedTabIfVisible];
    }
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self cancelProvisionalNavigationWatchdogForWebView:webView];
    [self handleNavigationError:error forWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self cancelProvisionalNavigationWatchdogForWebView:webView];
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
        [self updateConnectionSecurityStateForTab:tab webView:webView];
        [self updateSecurityBadgeVisibility];
    }

    NSInteger generation = tab.titleUpdateGeneration;
    __weak typeof(self) weakSelf = self;
    // 立刻拉取 document.title；SPA 可能晚到，再延迟补几次。
    [tab pullDocumentTitleFromWebView];
    [self applyTitleFromWebView:webView generation:generation];
    for (NSNumber *delayMs in @[ @200, @600, @1500, @3000 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs.doubleValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            BrowserTab *current = [strongSelf.tabController tabForWebView:webView];
            if (!current || current.titleUpdateGeneration != generation) {
                return;
            }
            [current pullDocumentTitleFromWebView];
            [strongSelf applyTitleFromWebView:webView generation:generation];
        });
    }
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

    // 已有挂起的证书挑战 / 正在展示警告页：不再展示通用错误页。
    BrowserPendingSSLAuth *pending = [self.pendingSSLAuthByWebView objectForKey:webView];
    if (pending && !pending.completionInvoked) {
        if (webView == self.webView) {
            [self.loadingProgressView resetHidden];
            [self updateNavigationState];
        }
        return;
    }

    if ([self isCertificateRelatedError:error]) {
        NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
        if (![failingURL isKindOfClass:[NSURL class]]) {
            failingURL = webView.URL;
        }
        NSString *host = failingURL.host.length > 0 ? failingURL.host : @"未知主机";
        NSInteger port = failingURL.port != nil ? failingURL.port.integerValue : 443;
        NSString *hostKey = [BrowserSSLExceptionStore hostKeyForHost:host port:port];

        if (webView == self.webView) {
            [self.loadingProgressView resetHidden];
        }
        [self clearNavigationErrorForWebView:webView];
        [self presentCertificateWarningForWebView:webView
                                          hostKey:hostKey
                                      hostDisplay:host
                                        challenge:nil
                                completionHandler:nil
                                fallbackReloadURL:failingURL];
        if (webView == self.webView) {
            [self updateNavigationState];
        }
        return;
    }

    NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
    if (![failingURL isKindOfClass:[NSURL class]]) {
        failingURL = webView.URL;
    }
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
    }
    [self presentNavigationErrorForWebView:webView
                                     title:@"无法加载页面"
                                   message:[self userFacingMessageForNavigationError:error]
                                failingURL:failingURL];
    if (webView == self.webView) {
        [self updateNavigationState];
    }
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
        NSURL *newWindowURL = [browserWebView consumePendingContextMenuOpenInNewWindowURL:navigationAction.request.URL];
        if (newWindowURL) {
            if (browserWebView.openURLInNewWindowHandler) {
                browserWebView.openURLInNewWindowHandler(newWindowURL);
            } else {
                [self.tabController addTabWithURL:newWindowURL];
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

// 若不实现下列面板回调，网页调用 alert/confirm/prompt 或 beforeunload 时会卡住，页面无法继续交互。

- (void)presentJavaScriptPanel:(NSAlert *)alert
             completionHandler:(void (^)(NSModalResponse returnCode))completionHandler {
    NSWindow *hostWindow = self.window;
    if (hostWindow != nil) {
        [alert beginSheetModalForWindow:hostWindow completionHandler:completionHandler];
    } else {
        completionHandler([alert runModal]);
    }
}

- (void)webView:(WKWebView *)webView
runJavaScriptAlertPanelWithMessage:(NSString *)message
      initiatedByFrame:(WKFrameInfo *)frame
       completionHandler:(void (^)(void))completionHandler {
    (void)webView;
    (void)frame;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message.length > 0 ? message : @" ";
    [alert addButtonWithTitle:@"好"];
    [self presentJavaScriptPanel:alert completionHandler:^(NSModalResponse returnCode) {
        (void)returnCode;
        completionHandler();
    }];
}

- (void)webView:(WKWebView *)webView
runJavaScriptConfirmPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
         completionHandler:(void (^)(BOOL result))completionHandler {
    (void)webView;
    (void)frame;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message.length > 0 ? message : @" ";
    [alert addButtonWithTitle:@"好"];
    [alert addButtonWithTitle:@"取消"];
    [self presentJavaScriptPanel:alert completionHandler:^(NSModalResponse returnCode) {
        completionHandler(returnCode == NSAlertFirstButtonReturn);
    }];
}

- (void)webView:(WKWebView *)webView
runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                          defaultText:(NSString *)defaultText
                     initiatedByFrame:(WKFrameInfo *)frame
                      completionHandler:(void (^)(NSString * _Nullable result))completionHandler {
    (void)webView;
    (void)frame;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = prompt.length > 0 ? prompt : @" ";
    SBTextField *input = [SBTextField standardField];
    input.frame = NSMakeRect(0, 0, 280, 24);
    input.stringValue = defaultText ?: @"";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"好"];
    [alert addButtonWithTitle:@"取消"];
    [alert layout];

    NSWindow *hostWindow = self.window;
    if (hostWindow != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [hostWindow makeFirstResponder:input];
        });
    }

    [self presentJavaScriptPanel:alert completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            completionHandler(input.stringValue ?: @"");
        } else {
            completionHandler(nil);
        }
    }];
}

- (void)webView:(WKWebView *)webView
runBeforeUnloadConfirmPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL result))completionHandler {
    (void)webView;
    (void)frame;

    // 非公开 WKUIDelegate SPI：部分 WebKit 版本在 beforeunload 时会调用；未实现则可能直接离开或静默取消。
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"离开此网站？";
    // 现代浏览器会忽略页面自定义 beforeunload 文案；有文案时作补充说明。
    if (message.length > 0) {
        alert.informativeText = message;
    } else {
        alert.informativeText = @"你所做的更改可能不会被保存。";
    }
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"离开"];
    [alert addButtonWithTitle:@"取消"];
    [self presentJavaScriptPanel:alert completionHandler:^(NSModalResponse returnCode) {
        completionHandler(returnCode == NSAlertFirstButtonReturn);
    }];
}

- (void)webViewDidClose:(WKWebView *)webView {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (tab != nil) {
        [self.tabController closeTab:tab];
    }
}

- (void)webView:(WKWebView *)webView
requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
                     initiatedByFrame:(WKFrameInfo *)frame
                                 type:(WKMediaCaptureType)type
                      decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler API_AVAILABLE(macos(12.0)) {
    (void)webView;
    (void)frame;

    NSString *host = origin.host.length > 0 ? origin.host : @"此网站";
    NSString *deviceText;
    switch (type) {
        case WKMediaCaptureTypeCamera:
            deviceText = @"摄像头";
            break;
        case WKMediaCaptureTypeMicrophone:
            deviceText = @"麦克风";
            break;
        case WKMediaCaptureTypeCameraAndMicrophone:
            deviceText = @"摄像头和麦克风";
            break;
        default:
            deviceText = @"媒体设备";
            break;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"允许“%@”使用%@？", host, deviceText];
    alert.informativeText = @"网站请求访问设备以进行音视频通话或录制。";
    [alert addButtonWithTitle:@"允许"];
    [alert addButtonWithTitle:@"拒绝"];
    [self presentJavaScriptPanel:alert completionHandler:^(NSModalResponse returnCode) {
        decisionHandler(returnCode == NSAlertFirstButtonReturn
                            ? WKPermissionDecisionGrant
                            : WKPermissionDecisionDeny);
    }];
}

@end
