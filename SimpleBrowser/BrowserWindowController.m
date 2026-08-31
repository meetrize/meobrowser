#import "BrowserWindowController.h"
#import "BrowserSettingsWindowController.h"
#import "AppDelegate.h"
#import "BrowserAppInfo.h"
#import "SBTextField.h"
#import "BrowsingPreferences.h"
#import "BrowserKeyboardPreferences.h"
#import "BrowserLocalFileSupport.h"
#import "BrowserTabController.h"
#import "BrowserTabStripView.h"
#import "BrowserTabStripChromeActionsView.h"
#import "BrowserChromeActionItem.h"
#import "BrowserChromeActionLayoutStore.h"
#import "BrowserChromeActionMenuRowView.h"
#import "BrowserStatusItemController.h"
#import "BrowserTransparentModeController.h"
#import "BrowserTransparentModePreferences.h"
#import "BrowserTransparentChromeAutoHideController.h"
#import "BrowserAfkModeController.h"
#import "BrowserAutoScrollController.h"
#import "BrowserAutoScrollPreferences.h"
#import "BrowserWindowLayoutPresetStore.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserTabItemView.h"
#import "BrowserBackgroundMediaController.h"
#import "BrowserLaunchpadView.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"
#import "BrowserAddressBarAutocompleteController.h"
#import "BrowserAddressBarRowView.h"
#import "BrowserURLInputClassifier.h"
#import "BrowserPageTranslationController.h"
#import "BrowserDownloadManager.h"
#import "BrowserDownloadPanel.h"
#import "BrowserSettingsWindowController.h"
#import "BrowserDownloadProgressRingView.h"
#import "BrowserHistoryStore.h"
#import "BrowserHistorySidebarController.h"
#import "PagePackSidebarController.h"
#import "PagePackInjector.h"
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
#import "BrowserFeedReader.h"
#import "BrowserSSLExceptionStore.h"
#import "BrowserCertificateWarningView.h"
#import "BrowserNavigationErrorView.h"
#import "BrowserHTTPAuthPrompt.h"
#import "BrowserNavigationSession.h"
#import "BrowserNavigationWatchdog.h"
#import "BrowserNavigationTimeouts.h"
#import "BrowserReachabilityProbe.h"
#import "BrowserTabLoadIsolator.h"
#import "BrowserNavigationDiagnostics.h"
#import "CompanionChannel.h"
#import "CompanionLinkUI.h"
#import "BrowserTransientToast.h"
#import "PhoneNotificationSidebarController.h"
#import "BrowserTrailingSidebarSlot.h"
#import "AssistSidebarController.h"
#import "AssistSidebarSettings.h"
#import "LoginRecipe.h"
#import "FormMemo.h"
#import "PhoneNotificationInboxSettings.h"
#import "PhoneNotificationInboxStore.h"
#import "BrowserWebInspector.h"
#import "BrowserDeveloperPreferences.h"
#import "BrowserPageSource.h"
#import "PhoneNotificationPresenter.h"
#import "BrowserUserAgent.h"
#import "BrowserGeolocationBridge.h"
#import <Security/Security.h>
#import <dlfcn.h>

static void *kBrowserEstimatedProgressContext = &kBrowserEstimatedProgressContext;
static void *kBrowserFullscreenStateContext = &kBrowserFullscreenStateContext;

/// WebKit 跨站导航 process-swap 可能导致 popup 的 window.opener 变 null（Google OAuth 常见）。
/// 私有 API：自定义浏览器可用；不可用时静默跳过。
static void MeoDisableProcessSwapOnNavigationIfAvailable(WKPreferences *preferences) {
    if (preferences == nil) {
        return;
    }
    typedef void (*MeoSetProcessSwapFn)(WKPreferences *, bool);
    static MeoSetProcessSwapFn setProcessSwap = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        setProcessSwap = (MeoSetProcessSwapFn)dlsym(RTLD_DEFAULT, "WKPreferencesSetProcessSwapOnNavigationEnabled");
    });
    if (setProcessSwap) {
        setProcessSwap(preferences, false);
    }
}

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
/// 负缓存命中：重新加载按钮显示「仍要访问」，并清除负缓存后重试。
@property (nonatomic, assign) BOOL fromNegativeCache;
@end

@implementation BrowserPendingNavigationError
@end

@interface BrowserWindowController () <BrowserTabControllerDelegate, BrowserTabStripViewDelegate, BrowserLaunchpadViewDelegate, BrowserAddressBarAutocompleteControllerDelegate, BrowserDownloadManagerObserver, BrowserDownloadPanelDelegate, BrowserHistorySidebarControllerDelegate, BrowserCertificateWarningViewDelegate, BrowserNavigationErrorViewDelegate, PhoneNotificationSidebarControllerDelegate, AssistSidebarControllerDelegate, PagePackSidebarControllerDelegate, NSWindowDelegate, NSMenuItemValidation>
- (instancetype)initWithSessionDictionary:(nullable NSDictionary *)session loadTabs:(BOOL)loadTabs;
@property (nonatomic, strong) BrowserTabController *tabController;
@property (nonatomic, strong) BrowserTabStripView *tabStripView;
@property (nonatomic, strong) BrowserTabStripChromeActionsView *chromeActionsView;
@property (nonatomic, strong) BrowserTransparentModeController *transparentModeController;
@property (nonatomic, strong) BrowserTransparentChromeAutoHideController *transparentChromeAutoHideController;
@property (nonatomic, strong) BrowserAfkModeController *afkModeController;
@property (nonatomic, strong) BrowserAutoScrollController *autoScrollController;
@property (nonatomic, assign) BOOL smallLayoutTransparentSnapshotValid;
@property (nonatomic, assign) BOOL smallLayoutTransparentSnapshot;
@property (nonatomic, assign) BOOL applyingLayoutPreset;
@property (nonatomic, strong) NSTitlebarAccessoryViewController *tabStripAccessory;
@property (nonatomic, strong) NSView *tabStripAccessoryRoot;
@property (nonatomic, strong) NSLayoutConstraint *tabStripAccessoryHeightConstraint;
@property (nonatomic, strong) NSStackView *rootStack;
@property (nonatomic, strong) NSLayoutConstraint *rootStackTopToContentGuideConstraint;
@property (nonatomic, strong) NSLayoutConstraint *rootStackTopToContentViewConstraint;
@property (nonatomic, strong) NSLayoutConstraint *transparentChromeToolbarHeightConstraint;
@property (nonatomic, assign) CGFloat transparentChromeToolbarFullHeight;
@property (nonatomic, assign) BOOL transparentChromeStableLayoutActive;
@property (nonatomic, assign) BOOL transparentChromeStableLayoutPending;
@property (nonatomic, assign) BOOL transparentModeChromeSetupPending;
@property (nonatomic, strong) NSStackView *toolbar;
@property (nonatomic, strong) NSStackView *navButtons;
@property (nonatomic, assign) BOOL addressBarPeekActive;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSStackView *contentRowStack;
@property (nonatomic, strong) PhoneNotificationSidebarController *notificationSidebarController;
@property (nonatomic, strong) AssistSidebarController *assistSidebarController;
@property (nonatomic, strong) BrowserHistorySidebarController *historySidebarController;
@property (nonatomic, strong) PagePackSidebarController *pagePackSidebarController;
@property (nonatomic, strong) BrowserTrailingSidebarSlot *trailingSidebarSlot;
@property (nonatomic, strong, nullable) NSView *notificationInboxBadgeView;
@property (nonatomic, strong) BrowserLaunchpadView *launchpadView;
@property (nonatomic, strong) BrowserLoadingProgressView *loadingProgressView;
@property (nonatomic, weak) WKWebView *observedProgressWebView;
@property (nonatomic, weak) WKWebView *observedFullscreenWebView;
/// Element Fullscreen 期间周期性修补 WKWebView 布局（WebKit 可能异步剥约束导致 0 尺寸黑屏）。
@property (nonatomic, strong, nullable) NSTimer *fullscreenLayoutRepairTimer;
@property (nonatomic, assign) NSInteger fullscreenLayoutRepairGeneration;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong, nullable) id reloadKeyMonitor;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, strong) NSButton *translateButton;
@property (nonatomic, strong) BrowserPageTranslationController *pageTranslationController;
@property (nonatomic, strong) NSButton *securityBadgeButton;
@property (nonatomic, strong) NSButton *downloadButton;
@property (nonatomic, strong) NSView *downloadBadgeView;
@property (nonatomic, strong) BrowserDownloadProgressRingView *downloadProgressRingView;
@property (nonatomic, strong) SBTextField *addressField;
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
@property (nonatomic, strong, nullable) dispatch_block_t pendingPersistBlock;
@property (nonatomic, assign) NSInteger trafficLightScheduleGeneration;
@property (nonatomic, strong) BrowserCertificateWarningView *certificateWarningView;
@property (nonatomic, strong) BrowserNavigationErrorView *navigationErrorView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserPendingSSLAuth *> *pendingSSLAuthByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserPendingNavigationError *> *pendingNavigationErrorByWebView;
@property (nonatomic, strong) BrowserNavigationWatchdog *navigationWatchdog;
@property (nonatomic, strong) NSMapTable<WKWebView *, NSURL *> *pendingProvisionalURLByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserReachabilityProbeHandle *> *reachabilityProbeByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, NSNumber *> *hardRecoverTokenByWebView;
@property (nonatomic, assign) NSInteger hardRecoverTokenCounter;
@property (nonatomic, strong) NSHashTable<WKWebView *> *webViewsWithHTTPAuthPrompt;
@property (nonatomic, assign) BOOL addressFieldIsEditing;
/// 上次 refreshTabsUI 时的选中标签，用于判断是否切到新标签页后再聚焦地址栏。
@property (nonatomic, strong, nullable) NSUUID *lastSelectedTabIDForAddressFocus;
/// refreshTabsUI 代际：延后 chrome 刷新时校验仍指向同一选中标签。
@property (nonatomic, assign) NSInteger refreshTabsUIGeneration;
/// estimatedProgress UI 合并。
@property (nonatomic, assign) NSTimeInterval lastProgressUIUpdateTime;
@property (nonatomic, assign) double lastProgressUIValue;
@property (nonatomic, strong, nullable) dispatch_block_t pendingProgressUIBlock;
/// 自定义应用协议（如 OAuth 回调 minimax-hub-cn://）应交系统打开，而非在 WebView 内加载。
+ (BOOL)shouldHandOffURLToExternalApplication:(nullable NSURL *)url;
- (BOOL)openURLInExternalApplicationIfNeeded:(nullable NSURL *)url;
- (void)openURLInExternalApplication:(NSURL *)url;
- (void)beginBlobDownloadFromURL:(nullable NSURL *)url inWebView:(nullable WKWebView *)webView;
- (void)beginBlobDownloadFromURL:(nullable NSURL *)url
              suggestedFilename:(nullable NSString *)suggestedFilename
                       inWebView:(nullable WKWebView *)webView;
- (void)openAcceptedURLsInBrowser:(NSArray<NSURL *> *)urls;
@end

/// 接收本地 HTML 文件拖放的内容区容器。
@interface BrowserFileDropContentView : NSView
@property (nonatomic, weak) BrowserWindowController *browserController;
@end

@implementation BrowserFileDropContentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    }
    return self;
}

- (NSArray<NSURL *> *)previewableFileURLsFromDraggingInfo:(id<NSDraggingInfo>)sender {
    NSMutableArray<NSURL *> *result = [NSMutableArray array];
    NSArray<NSPasteboardItem *> *items = sender.draggingPasteboard.pasteboardItems ?: @[];
    for (NSPasteboardItem *item in items) {
        NSString *urlString = [item stringForType:NSPasteboardTypeFileURL];
        if (urlString.length == 0) {
            continue;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url.isFileURL) {
            NSString *path = urlString.stringByRemovingPercentEncoding ?: urlString;
            url = [NSURL fileURLWithPath:path];
        }
        if ([BrowserLocalFileSupport isPreviewableFileURL:url]) {
            [result addObject:url];
        }
    }
    return [result copy];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self previewableFileURLsFromDraggingInfo:sender].count > 0 ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return [self previewableFileURLsFromDraggingInfo:sender].count > 0;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [self previewableFileURLsFromDraggingInfo:sender];
    if (urls.count == 0 || !self.browserController) {
        return NO;
    }
    [self.browserController openAcceptedURLsInBrowser:urls];
    return YES;
}

@end

@implementation BrowserWindowController

+ (BOOL)shouldHandOffURLToExternalApplication:(NSURL *)url {
    if (!url) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (scheme.length == 0) {
        return NO;
    }
    static NSSet<NSString *> *browserHandledSchemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        browserHandledSchemes = [NSSet setWithObjects:
                                 @"http",
                                 @"https",
                                 @"about",
                                 @"blob",
                                 @"data",
                                 @"file",
                                 @"javascript",
                                 BrowserFeedURLScheme,
                                 nil];
    });
    return ![browserHandledSchemes containsObject:scheme];
}

- (BOOL)openURLInExternalApplicationIfNeeded:(NSURL *)url {
    if (![BrowserWindowController shouldHandOffURLToExternalApplication:url]) {
        return NO;
    }
    [self openURLInExternalApplication:url];
    return YES;
}

- (void)openURLInExternalApplication:(NSURL *)url {
    if (!url) {
        return;
    }
    if (@available(macOS 12.0, *)) {
        NSURL *handlerApp = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];
        if (!handlerApp) {
            [BrowserTransientToast showMessage:@"未找到可打开此链接的应用"
                                      inWindow:self.window
                                      duration:2.4];
            return;
        }
    }
    BOOL opened = [[NSWorkspace sharedWorkspace] openURL:url];
    if (!opened) {
        [BrowserTransientToast showMessage:@"无法打开应用协议链接"
                                  inWindow:self.window
                                  duration:2.4];
    }
}

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
        _transparentModeController = [[BrowserTransparentModeController alloc] init];
        _transparentModeController.windowController = self;
        _transparentChromeAutoHideController = [[BrowserTransparentChromeAutoHideController alloc] init];
        _transparentChromeAutoHideController.windowController = self;
        __weak typeof(self) weakSelfForAutoHide = self;
        _transparentChromeAutoHideController.chromeRevealDidChangeHandler = ^{
            __strong typeof(weakSelfForAutoHide) strongSelf = weakSelfForAutoHide;
            [strongSelf applyChromeVisibilityForCurrentMode];
        };
        _afkModeController = [[BrowserAfkModeController alloc] init];
        _afkModeController.windowController = self;
        _autoScrollController = [[BrowserAutoScrollController alloc] init];
        _autoScrollController.windowController = self;
        __weak typeof(self) weakSelfForScroll = self;
        _autoScrollController.didDisableHandler = ^{
            __strong typeof(weakSelfForScroll) strongSelf = weakSelfForScroll;
            [strongSelf.chromeActionsView setOn:NO forItemID:BrowserChromeActionAutoScrollID];
        };
        _windowLayoutMode = BrowserWindowLayoutModeFree;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transparentModePreferencesDidChange:)
                                                     name:BrowserTransparentModePreferencesDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(chromeActionLayoutDidChange:)
                                                     name:BrowserChromeActionLayoutDidChangeNotification
                                                   object:nil];
        _pageTranslationController = [[BrowserPageTranslationController alloc] init];
        __weak typeof(self) weakSelf = self;
        _pageTranslationController.uiStateDidChangeHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf updateTranslateButtonState];
        };
        [self configureWebViewConfiguration:_webViewConfiguration];
        _tabController = [[BrowserTabController alloc] initWithConfiguration:_webViewConfiguration];
        _tabController.delegate = self;
        _downloadManager = [BrowserDownloadManager sharedManager];
        [_downloadManager addObserver:self];
        _pendingSSLAuthByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _pendingNavigationErrorByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _navigationWatchdog = [[BrowserNavigationWatchdog alloc] init];
        _pendingProvisionalURLByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _reachabilityProbeByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _hardRecoverTokenByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _webViewsWithHTTPAuthPrompt = [NSHashTable weakObjectsHashTable];
        [self setupUI];
        [self installReloadKeyMonitor];
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
    // 避免 WebKit 再追加 App 名，与 customUserAgent 叠出非 Safari 痕迹。
    configuration.applicationNameForUserAgent = @"";
    // WebKit 默认关闭 Element Fullscreen；YouTube / 抖音等会检测 document.fullscreenEnabled。
    if (@available(macOS 12.3, *)) {
        configuration.preferences.elementFullscreenEnabled = YES;
    }
    MeoDisableProcessSwapOnNavigationIfAvailable(configuration.preferences);
    // http:#hash 经系统代理可能变成 path 里的 %23 → 404；在 document-start 写回 hash。
    [BrowserWebView installFragmentRestoreScriptOnContentController:configuration.userContentController];
    [BrowserDownloadManager installMediaCaptureScriptOnConfiguration:configuration];
    [BrowserGeolocationBridge installOnConfiguration:configuration];
    [self.loginAssistController configureWebViewConfiguration:configuration];
    [self.captchaAssistController configureWebViewConfiguration:configuration];
    [self.feedAssistController configureWebViewConfiguration:configuration];
    [self.findBarController configureWebViewConfiguration:configuration];
    [BrowserTransparentModeController installPageStyleUserScriptOnConfiguration:configuration];
}

- (void)applyWebInspectionPreferenceToLiveWebViews {
    for (BrowserTab *tab in self.tabController.tabs) {
        [BrowserWebInspector applyInspectableToWebView:tab.webView];
    }
}

+ (void)applyWebInspectionPreferenceAcrossWindows {
    for (NSWindow *window in NSApp.windows) {
        id controller = window.windowController;
        if ([controller isKindOfClass:[BrowserWindowController class]]) {
            [(BrowserWindowController *)controller applyWebInspectionPreferenceToLiveWebViews];
        }
    }
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

    if (self.transparentChromeStableLayoutActive) {
        [self.tabStripAccessoryRoot layoutSubtreeIfNeeded];
    } else {
        [window.contentView layoutSubtreeIfNeeded];
    }
    [self.tabStripView layoutSubtreeIfNeeded];

    CGFloat expectedHeight = self.tabStripView.effectiveStripHeight;
    if (NSHeight(self.tabStripView.bounds) < expectedHeight - 0.5 ||
        NSHeight(self.tabStripView.frame) < expectedHeight - 0.5) {
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

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    [self applyAlwaysOnTopWindowLevel];
    [self syncChromeActionButtonStates];
    [self scheduleTrafficLightPositioning];
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    if (self.transparentModeEnabled) {
        [self setTransparentModeEnabled:NO];
    }
    if (self.afkModeEnabled) {
        [self setAfkModeEnabled:NO];
    }
    [self syncChromeActionButtonStates];
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
    [self schedulePersistLayoutPresetIfNeeded];
}

- (void)windowDidMove:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    [self schedulePersistLayoutPresetIfNeeded];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    [self.afkModeController forceDisableAndReveal];
    [self.transparentChromeAutoHideController forceDisableAndReveal];
    self.autoScrollController.enabled = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(persistLayoutPresetNow)
                                               object:nil];
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
    [self finishDeferredTransparentModeSetupIfNeeded];
    [self scheduleTrafficLightPositioning];
}

- (void)dealloc {
    [self uninstallReloadKeyMonitor];
    [self cancelAllPendingSSLAuthWithDisposition:NSURLSessionAuthChallengeCancelAuthenticationChallenge];
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    [self stopObservingLoadingProgress];
    [self stopFullscreenLayoutRepair];
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

    self.chromeActionsView = [[BrowserTabStripChromeActionsView alloc] initWithFrame:NSZeroRect];
    self.tabStripView.chromeActionsView = self.chromeActionsView;
    [self reloadChromeActionsFromStore];

    self.backButton = [self toolbarIconButtonWithSymbol:@"chevron.left"
                                                toolTip:@"后退"
                                                 action:@selector(goBack:)];
    self.forwardButton = [self toolbarIconButtonWithSymbol:@"chevron.right"
                                                   toolTip:@"前进"
                                                    action:@selector(goForward:)];
    self.reloadButton = [self toolbarIconButtonWithSymbol:@"arrow.clockwise"
                                                  toolTip:@"刷新"
                                                   action:@selector(reloadPage:)];

    self.navButtons = [NSStackView stackViewWithViews:@[
        self.backButton, self.forwardButton, self.reloadButton
    ]];
    self.navButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.navButtons.spacing = 2;
    self.navButtons.translatesAutoresizingMaskIntoConstraints = NO;

    self.addressField = [SBTextField standardField];
    self.addressField.placeholderString = @"输入网址";
    self.addressField.selectsAllOnMouseFocus = YES;
    self.addressField.delegate = self;
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    // 地址栏单独调文字边距；快捷方式编辑 / 设置等仍用默认贴顶。
    // topInset 与 upwardBias 合成：有效上边距 = max(0, topInset - upwardBias) → 2pt（整体再下移 2）。
    self.addressField.compactTextTopInset = 6.0;
    self.addressField.compactTextUpwardBias = 3.0;
    // 外框仍 25；文字区向下多扩 1pt，避免下移后字底被 bezel 裁切。
    self.addressField.compactTextBottomExtend = 1.0;
    // 编辑态：垂直居中后再上移 2pt（略偏下时的光学修正）。
    self.addressField.centersCompactTextWhenEditing = YES;
    self.addressField.compactTextUpwardBiasWhenEditing = 1.0;
    [self.addressField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    // 胶囊外框：地址栏 RowView 垫一层 sibling 浅灰胶囊（无描边）。
    self.addressField.usesCapsuleBezel = YES;
    // 半圆端头留白；与编辑态共用（再右移 2pt → 8）。
    self.addressField.leadingContentInset = 8.0;
    self.addressField.focusRingType = NSFocusRingTypeNone;
    [self.addressField.heightAnchor constraintEqualToConstant:25].active = YES;

    self.bookmarkButton = [self makeBookmarkButton];
    self.translateButton = [self makeTranslateButton];
    [self.addressField addSubview:self.bookmarkButton];
    [self.addressField addSubview:self.translateButton];
    self.addressField.trailingContentInset = 42;
    [NSLayoutConstraint activateConstraints:@[
        [self.translateButton.trailingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:-6],
        [self.translateButton.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
        [self.bookmarkButton.trailingAnchor constraintEqualToAnchor:self.translateButton.leadingAnchor constant:-4],
        [self.bookmarkButton.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
    ]];
    self.pageTranslationController.hostWindow = self.window;

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
    [self updateChromeCompanionToolAppearance];

    self.addressBarRow = [[BrowserAddressBarRowView alloc] initWithAddressField:self.addressField
                                                                 securityBadge:self.securityBadgeButton
                                                                   actionGroup:nil];

    self.toolbar = [NSStackView stackViewWithViews:@[
        self.navButtons, self.addressBarRow
    ]];
    self.toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.toolbar.spacing = 10;
    // 上下边距一致：输入框上边缘到工具栏顶 = 下边缘到网页顶。
    self.toolbar.edgeInsets = NSEdgeInsetsMake(4, 8, 4, 8);
    self.toolbar.distribution = NSStackViewDistributionFill;
    [self.toolbar setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationVertical];
    self.toolbar.wantsLayer = YES;
    self.toolbar.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;

    BrowserFileDropContentView *dropContainer = [[BrowserFileDropContentView alloc] initWithFrame:NSZeroRect];
    dropContainer.browserController = self;
    dropContainer.wantsLayer = YES;
    dropContainer.clipsToBounds = YES;
    [dropContainer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationVertical];
    [dropContainer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.contentContainer = dropContainer;

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

    self.historySidebarController = [[BrowserHistorySidebarController alloc] init];
    self.historySidebarController.delegate = self;
    self.historySidebarController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.historySidebarController.view setContentHuggingPriority:NSLayoutPriorityRequired
                                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.historySidebarController.view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.pagePackSidebarController = [[PagePackSidebarController alloc] init];
    self.pagePackSidebarController.delegate = self;
    self.pagePackSidebarController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pagePackSidebarController.view setContentHuggingPriority:NSLayoutPriorityRequired
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.pagePackSidebarController.view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                                  forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.trailingSidebarSlot = [[BrowserTrailingSidebarSlot alloc] init];
    self.trailingSidebarSlot.notificationSidebar = self.notificationSidebarController;
    self.trailingSidebarSlot.assistSidebar = self.assistSidebarController;
    self.trailingSidebarSlot.historySidebar = self.historySidebarController;
    self.trailingSidebarSlot.pagePackSidebar = self.pagePackSidebarController;

    self.contentRowStack = [NSStackView stackViewWithViews:@[
        self.contentContainer,
        self.notificationSidebarController.view,
        self.assistSidebarController.view,
        self.historySidebarController.view,
        self.pagePackSidebarController.view
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
    NSView *accessoryRoot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, BrowserTabStripHeightRegular)];
    accessoryRoot.wantsLayer = YES;
    accessoryRoot.layer.backgroundColor = BrowserTabStripFillColor().CGColor;
    self.tabStripAccessoryRoot = accessoryRoot;
    self.tabStripView.translatesAutoresizingMaskIntoConstraints = NO;
    [accessoryRoot addSubview:self.tabStripView];
    NSLayoutConstraint *accessoryHeight =
        [accessoryRoot.heightAnchor constraintEqualToConstant:BrowserTabStripHeightRegular];
    self.tabStripAccessoryHeightConstraint = accessoryHeight;
    [NSLayoutConstraint activateConstraints:@[
        [self.tabStripView.topAnchor constraintEqualToAnchor:accessoryRoot.topAnchor],
        [self.tabStripView.leadingAnchor constraintEqualToAnchor:accessoryRoot.leadingAnchor],
        [self.tabStripView.trailingAnchor constraintEqualToAnchor:accessoryRoot.trailingAnchor],
        [self.tabStripView.bottomAnchor constraintEqualToAnchor:accessoryRoot.bottomAnchor],
        accessoryHeight,
    ]];

    self.tabStripAccessory = [[NSTitlebarAccessoryViewController alloc] init];
    self.tabStripAccessory.view = accessoryRoot;
    // 必须在 add 之前设置
    self.tabStripAccessory.layoutAttribute = NSLayoutAttributeBottom;
    [self.window addTitlebarAccessoryViewController:self.tabStripAccessory];
    [self collapseSystemTitlebarDecoration];

    self.rootStack = [NSStackView stackViewWithViews:@[
        self.toolbar, self.contentRowStack
    ]];
    self.rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.rootStack.spacing = 0;
    self.rootStack.distribution = NSStackViewDistributionFill;

    NSView *contentView = self.window.contentView;
    self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.rootStack];

    // 对齐 contentLayoutGuide：内容紧贴 accessory 下方，避免重复留白
    NSLayoutGuide *contentGuide = (NSLayoutGuide *)self.window.contentLayoutGuide;
    self.rootStackTopToContentGuideConstraint =
        [self.rootStack.topAnchor constraintEqualToAnchor:contentGuide.topAnchor];
    self.rootStackTopToContentViewConstraint =
        [self.rootStack.topAnchor constraintEqualToAnchor:contentView.topAnchor];
    self.rootStackTopToContentViewConstraint.active = NO;
    [NSLayoutConstraint activateConstraints:@[
        self.rootStackTopToContentGuideConstraint,
        [self.rootStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.rootStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.rootStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
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

- (void)reloadChromeActionsFromStore {
    [self.chromeActionsView reloadFromLayoutStore];
    [self.tabStripView refreshChromeActionsLayout];
    [self wireChromeActionButtons];
    [self syncChromeActionButtonStates];
    [self rewireMigratedToolbarActionsAfterChromeReload];
}

- (void)chromeActionLayoutDidChange:(NSNotification *)notification {
    (void)notification;
    [self reloadChromeActionsFromStore];
}

- (void)wireChromeActionButtons {
    NSButton *afkButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionAfkModeID];
    afkButton.target = self;
    afkButton.action = @selector(toggleAfkMode:);

    NSButton *transparentButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionTransparentModeID];
    transparentButton.target = self;
    transparentButton.action = @selector(toggleTransparentMode:);

    NSButton *compactButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionCompactModeID];
    compactButton.target = self;
    compactButton.action = @selector(toggleCompactMode:);

    NSButton *pinButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionAlwaysOnTopID];
    pinButton.target = self;
    pinButton.action = @selector(toggleAlwaysOnTop:);

    NSButton *autoScrollButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionAutoScrollID];
    autoScrollButton.target = self;
    autoScrollButton.action = @selector(toggleAutoScrollFromMoreMenu:);

    NSButton *scrollSpeedButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionScrollSpeedID];
    scrollSpeedButton.target = self;
    scrollSpeedButton.action = @selector(openAutoScrollSpeedSettings:);

    NSButton *windowLayoutButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionWindowLayoutID];
    windowLayoutButton.target = self;
    windowLayoutButton.action = @selector(toggleWindowLayoutZoomFromMoreMenu:);

    NSButton *moreButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionMoreMenuID];
    moreButton.target = self;
    moreButton.action = @selector(showChromeMoreMenu:);

    [self wireChromeButton:BrowserChromeActionTabOverviewID action:@selector(toggleTabOverview:)];
    [self wireChromeButton:BrowserChromeActionFindInPageID action:@selector(toggleFindBar:)];
    [self wireChromeButton:BrowserChromeActionHistoryID action:@selector(toggleHistoryPanel:)];
    [self wireChromeButton:BrowserChromeActionDownloadID action:@selector(toggleDownloadsPanel:)];
    [self wireChromeButton:BrowserChromeActionCompanionLinkID action:@selector(showCompanionLinkSettings:)];
    [self wireChromeButton:BrowserChromeActionSendToPhoneID action:@selector(sendCurrentTabToPhone:)];
    [self wireChromeButton:BrowserChromeActionPhonePolicyID action:@selector(showPhonePolicyPanel:)];
    [self wireChromeButton:BrowserChromeActionNotificationInboxID action:@selector(toggleNotificationInboxSidebar:)];
    [self wireChromeButton:BrowserChromeActionShareID action:@selector(showChromePlaceholderTool:)];
    [self wireChromeButton:BrowserChromeActionScreenshotID action:@selector(showChromePlaceholderTool:)];
    [self wireChromeButton:BrowserChromeActionExtensionID action:@selector(togglePagePackSidebar:)];
}

- (void)wireChromeButton:(NSString *)itemID action:(SEL)action {
    NSButton *button = [self.chromeActionsView buttonForItemID:itemID];
    if (!button) {
        return;
    }
    button.target = self;
    button.action = action;
}

- (void)showChromePlaceholderTool:(id)sender {
    (void)sender;
    [BrowserTransientToast showMessage:@"即将推出" inWindow:self.window duration:1.6];
}

/// AT-1：Chrome 条上出现迁入工具后，重绑角标 / 登录点亮，并刷新外观。
- (void)rewireMigratedToolbarActionsAfterChromeReload {
    NSButton *chromeDownload = [self.chromeActionsView buttonForItemID:BrowserChromeActionDownloadID];
    if (chromeDownload) {
        self.downloadButton = chromeDownload;
        [self installDownloadBadgeOnButton:chromeDownload];
        [self installDownloadProgressRingOnButton:chromeDownload];
        chromeDownload.target = self;
        chromeDownload.action = @selector(toggleDownloadsPanel:);
        [self updateDownloadButtonAppearance];
    }

    NSButton *chromeLogin = [self.chromeActionsView buttonForItemID:BrowserChromeActionLoginAssistID];
    if (chromeLogin) {
        [self.loginAssistController wireLoginButton:chromeLogin];
    }
    NSButton *chromeCaptcha = [self.chromeActionsView buttonForItemID:BrowserChromeActionCaptchaAssistID];
    if (chromeCaptcha) {
        [self.captchaAssistController wireCaptchaButton:chromeCaptcha];
    }
    NSButton *chromeFeed = [self.chromeActionsView buttonForItemID:BrowserChromeActionRSSFeedID];
    if (chromeFeed) {
        [self.feedAssistController wireFeedButton:chromeFeed];
    }

    NSButton *chromeNotify = [self.chromeActionsView buttonForItemID:BrowserChromeActionNotificationInboxID];
    if (chromeNotify) {
        [self installNotificationInboxBadgeOnButton:chromeNotify];
    }

    [self updateTabOverviewButtonAppearance];
    [self updateHistoryButtonAppearance];
    [self updateNotificationInboxButtonAppearance];
    [self updateChromeCompanionToolAppearance];
}

- (void)syncChromeActionButtonStates {
    if (!self.chromeActionsView) {
        return;
    }
    [self.chromeActionsView setOn:self.afkModeEnabled forItemID:BrowserChromeActionAfkModeID];
    [self.chromeActionsView setOn:self.transparentModeEnabled forItemID:BrowserChromeActionTransparentModeID];
    [self.chromeActionsView setOn:self.compactModeEnabled forItemID:BrowserChromeActionCompactModeID];
    [self.chromeActionsView setOn:self.alwaysOnTopEnabled forItemID:BrowserChromeActionAlwaysOnTopID];
    [self.chromeActionsView setOn:self.autoScrollController.enabled forItemID:BrowserChromeActionAutoScrollID];

    BOOL isSmall = (self.windowLayoutMode == BrowserWindowLayoutModeSmall);
    [self.chromeActionsView setOn:isSmall forItemID:BrowserChromeActionWindowLayoutID];

    BOOL fullscreen = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    NSButton *layoutButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionWindowLayoutID];
    layoutButton.enabled = !fullscreen;
}

- (void)toggleCompactMode:(id)sender {
    (void)sender;
    [self setCompactModeEnabled:!self.compactModeEnabled];
}

- (void)toggleAlwaysOnTop:(id)sender {
    (void)sender;
    [self setAlwaysOnTopEnabled:!self.alwaysOnTopEnabled];
}

/// TM-1：隐藏全部 chrome + 窗口透明；页面「只留字」在 TM-2。
- (void)toggleTransparentMode:(id)sender {
    (void)sender;
    [self setTransparentModeEnabled:!self.transparentModeEnabled];
}

- (void)toggleAfkMode:(id)sender {
    (void)sender;
    [self setAfkModeEnabled:!self.afkModeEnabled];
}

- (void)setAfkModeEnabled:(BOOL)afkModeEnabled {
    if (afkModeEnabled && (self.window.styleMask & NSWindowStyleMaskFullScreen)) {
        [self.chromeActionsView setOn:NO forItemID:BrowserChromeActionAfkModeID];
        return;
    }

    if (_afkModeEnabled == afkModeEnabled) {
        [self.chromeActionsView setOn:afkModeEnabled forItemID:BrowserChromeActionAfkModeID];
        return;
    }

    _afkModeEnabled = afkModeEnabled;
    [self.chromeActionsView setOn:afkModeEnabled forItemID:BrowserChromeActionAfkModeID];
    self.afkModeController.enabled = afkModeEnabled;

    [[BrowserStatusItemController sharedController] refreshMenuAppearance];
    [self schedulePersistTabSession];
}

#pragma mark - Chrome More Menu (统一图钉列表)

- (NSString *)chromeActionMenuTitleForItemID:(NSString *)itemID {
    if ([itemID isEqualToString:BrowserChromeActionWindowLayoutID]) {
        return (self.windowLayoutMode == BrowserWindowLayoutModeSmall) ? @"窗口放大" : @"窗口缩小";
    }
    BrowserChromeActionItem *item = [BrowserChromeActionItem catalogItemWithID:itemID];
    return item.toolTip.length > 0 ? item.toolTip : (itemID ?: @"");
}

- (BOOL)chromeActionCheckedForItemID:(NSString *)itemID {
    if ([itemID isEqualToString:BrowserChromeActionAfkModeID]) {
        return self.afkModeEnabled;
    }
    if ([itemID isEqualToString:BrowserChromeActionTransparentModeID]) {
        return self.transparentModeEnabled;
    }
    if ([itemID isEqualToString:BrowserChromeActionCompactModeID]) {
        return self.compactModeEnabled;
    }
    if ([itemID isEqualToString:BrowserChromeActionAlwaysOnTopID]) {
        return self.alwaysOnTopEnabled;
    }
    if ([itemID isEqualToString:BrowserChromeActionAutoScrollID]) {
        return self.autoScrollController.enabled;
    }
    if ([itemID isEqualToString:BrowserChromeActionWindowLayoutID]) {
        return self.windowLayoutMode == BrowserWindowLayoutModeSmall;
    }
    return NO;
}

- (BOOL)chromeActionTitleEnabledForItemID:(NSString *)itemID {
    if ([itemID isEqualToString:BrowserChromeActionWindowLayoutID]) {
        return (self.window.styleMask & NSWindowStyleMaskFullScreen) == 0;
    }
    return YES;
}

- (void)performChromeActionForItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionAfkModeID]) {
        [self toggleAfkMode:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionTransparentModeID]) {
        [self toggleTransparentMode:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionCompactModeID]) {
        [self toggleCompactMode:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionAlwaysOnTopID]) {
        [self toggleAlwaysOnTop:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionAutoScrollID]) {
        [self toggleAutoScrollFromMoreMenu:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionScrollSpeedID]) {
        [self openAutoScrollSpeedSettings:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionWindowLayoutID]) {
        [self toggleWindowLayoutZoomFromMoreMenu:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionTabOverviewID]) {
        [self toggleTabOverview:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionFindInPageID]) {
        [self toggleFindBar:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionHistoryID]) {
        [self toggleHistoryPanel:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionDownloadID]) {
        [self toggleDownloadsPanel:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionLoginAssistID]) {
        NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionLoginAssistID];
        if (button.action && button.target) {
            [NSApp sendAction:button.action to:button.target from:button];
        } else {
            [self.loginAssistController oneClickLogin:nil];
        }
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionCaptchaAssistID]) {
        NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionCaptchaAssistID];
        if (button.action && button.target) {
            [NSApp sendAction:button.action to:button.target from:button];
        } else {
            [self.captchaAssistController toggleCaptchaAssistPanel:nil];
        }
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionRSSFeedID]) {
        NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionRSSFeedID];
        if (button.action && button.target) {
            [NSApp sendAction:button.action to:button.target from:button];
        } else {
            [self.feedAssistController showFeedMenu:nil];
        }
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionCompanionLinkID]) {
        [self showCompanionLinkSettings:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionSendToPhoneID]) {
        [self sendCurrentTabToPhone:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionPhonePolicyID]) {
        [self showPhonePolicyPanel:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionNotificationInboxID]) {
        [self toggleNotificationInboxSidebar:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionShareID]
        || [itemID isEqualToString:BrowserChromeActionScreenshotID]) {
        [self showChromePlaceholderTool:nil];
        return;
    }
    if ([itemID isEqualToString:BrowserChromeActionExtensionID]) {
        [self togglePagePackSidebar:nil];
        return;
    }
}

- (void)showChromeMoreMenu:(id)sender {
    NSButton *button = nil;
    if ([sender isKindOfClass:[NSButton class]]) {
        button = (NSButton *)sender;
    } else {
        button = [self.chromeActionsView buttonForItemID:BrowserChromeActionMoreMenuID];
    }
    if (!button) {
        return;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"更多"];
    menu.autoenablesItems = NO;

    __weak typeof(self) weakSelf = self;
    __weak NSMenu *weakMenu = menu;

    for (NSString *itemID in [BrowserChromeActionLayoutStore orderedCustomActionIDs]) {
        BrowserChromeActionItem *catalogItem = [BrowserChromeActionItem catalogItemWithID:itemID];
        if (!catalogItem) {
            continue;
        }

        BrowserChromeActionMenuRowView *row =
            [[BrowserChromeActionMenuRowView alloc] initWithFrame:NSZeroRect];
        row.itemID = itemID;
        row.titleText = [self chromeActionMenuTitleForItemID:itemID];
        row.checked = catalogItem.toggles ? [self chromeActionCheckedForItemID:itemID] : NO;
        row.pinnedToToolbar = ![BrowserChromeActionLayoutStore isActionIDHidden:itemID];
        row.titleEnabled = [self chromeActionTitleEnabledForItemID:itemID];

        __weak BrowserChromeActionMenuRowView *weakRow = row;
        row.onTitleClick = ^(NSString *clickedID) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf performChromeActionForItemID:clickedID];
            [weakMenu cancelTracking];
        };
        row.onPinClick = ^(NSString *clickedID) {
            BOOL currentlyPinned = ![BrowserChromeActionLayoutStore isActionIDHidden:clickedID];
            [BrowserChromeActionLayoutStore setActionID:clickedID hidden:currentlyPinned];
            weakRow.pinnedToToolbar = !currentlyPinned;
        };

        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:catalogItem.toolTip ?: itemID
                                                          action:nil
                                                   keyEquivalent:@""];
        menuItem.view = row;
        [menu addItem:menuItem];
    }

    NSRect bounds = button.bounds;
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(NSMinX(bounds), NSMaxY(bounds) + 2)
                            inView:button];
}

- (void)toggleAutoScrollFromMoreMenu:(id)sender {
    (void)sender;
    self.autoScrollController.enabled = !self.autoScrollController.enabled;
    [self.chromeActionsView setOn:self.autoScrollController.enabled forItemID:BrowserChromeActionAutoScrollID];
}

- (void)openAutoScrollSpeedSettings:(id)sender {
    (void)sender;
    id delegate = NSApp.delegate;
    if ([delegate respondsToSelector:@selector(showBrowserSettingsSelectingTabIdentifier:)]) {
        [(AppDelegate *)delegate showBrowserSettingsSelectingTabIdentifier:BrowserSettingsTabGeneral];
    }
}

/// 单一菜单项切换：缩小态 → 放大；否则（自由/放大）→ 缩小。
- (void)toggleWindowLayoutZoomFromMoreMenu:(id)sender {
    (void)sender;
    if (self.window.styleMask & NSWindowStyleMaskFullScreen) {
        return;
    }
    if (self.windowLayoutMode == BrowserWindowLayoutModeSmall) {
        [self applyLargeWindowLayoutMode];
    } else {
        [self applySmallWindowLayoutMode];
    }
}

- (void)applyLargeWindowLayoutMode {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    if (self.windowLayoutMode == BrowserWindowLayoutModeSmall) {
        [self restoreTransparentSnapshotAfterLeavingSmallLayout];
    }

    self.windowLayoutMode = BrowserWindowLayoutModeLarge;
    if ([BrowserWindowLayoutPresetStore hasLargeFramePreset]) {
        NSRect frame = [BrowserWindowLayoutPresetStore clampFrame:[BrowserWindowLayoutPresetStore largeFramePreset]
                                                 toVisibleScreen:window.screen];
        self.applyingLayoutPreset = YES;
        [window setFrame:frame display:YES animate:YES];
        self.applyingLayoutPreset = NO;
    } else {
        [BrowserWindowLayoutPresetStore setLargeFramePreset:window.frame];
    }
    [self syncChromeActionButtonStates];
}

- (void)applySmallWindowLayoutMode {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    if (self.windowLayoutMode != BrowserWindowLayoutModeSmall) {
        self.smallLayoutTransparentSnapshot = self.transparentModeEnabled;
        self.smallLayoutTransparentSnapshotValid = YES;
    }

    self.windowLayoutMode = BrowserWindowLayoutModeSmall;

    NSRect targetFrame = NSZeroRect;
    BOOL targetTransparent = YES;
    if ([BrowserWindowLayoutPresetStore hasSmallFramePreset]) {
        targetFrame = [BrowserWindowLayoutPresetStore smallFramePreset];
        targetTransparent = [BrowserWindowLayoutPresetStore smallTransparentPreset];
    } else {
        targetFrame = [BrowserWindowLayoutPresetStore defaultSmallFrameOnScreen:window.screen
                                                                     relativeTo:window.frame];
        targetTransparent = YES;
    }

    NSInteger smallCount = 0;
    for (NSWindow *other in NSApp.windows) {
        id controller = other.windowController;
        if (controller == self) {
            continue;
        }
        if (![controller isKindOfClass:[BrowserWindowController class]]) {
            continue;
        }
        if (((BrowserWindowController *)controller).windowLayoutMode == BrowserWindowLayoutModeSmall) {
            smallCount += 1;
        }
    }
    if (smallCount > 0) {
        targetFrame.origin.x += 24.0 * smallCount;
        targetFrame.origin.y += 24.0 * smallCount;
    }
    targetFrame = [BrowserWindowLayoutPresetStore clampFrame:targetFrame toVisibleScreen:window.screen];

    self.applyingLayoutPreset = YES;
    [window setFrame:targetFrame display:YES animate:YES];
    self.applyingLayoutPreset = NO;

    [self setTransparentModeEnabled:targetTransparent];

    if (![BrowserWindowLayoutPresetStore hasSmallFramePreset]) {
        [BrowserWindowLayoutPresetStore setSmallFramePreset:window.frame
                                                transparent:self.transparentModeEnabled];
    }
    [self syncChromeActionButtonStates];
}

- (void)restoreTransparentSnapshotAfterLeavingSmallLayout {
    if (!self.smallLayoutTransparentSnapshotValid) {
        return;
    }
    BOOL snapshot = self.smallLayoutTransparentSnapshot;
    self.smallLayoutTransparentSnapshotValid = NO;
    if (self.transparentModeEnabled != snapshot) {
        [self setTransparentModeEnabled:snapshot];
    }
}

- (void)schedulePersistLayoutPresetIfNeeded {
    if (self.applyingLayoutPreset || !self.window) {
        return;
    }
    if (self.windowLayoutMode != BrowserWindowLayoutModeLarge
        && self.windowLayoutMode != BrowserWindowLayoutModeSmall) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(persistLayoutPresetNow)
                                               object:nil];
    [self performSelector:@selector(persistLayoutPresetNow)
               withObject:nil
               afterDelay:0.4];
}

- (void)persistLayoutPresetNow {
    if (!self.window || self.applyingLayoutPreset) {
        return;
    }
    NSRect frame = self.window.frame;
    if (self.windowLayoutMode == BrowserWindowLayoutModeLarge) {
        [BrowserWindowLayoutPresetStore setLargeFramePreset:frame];
    } else if (self.windowLayoutMode == BrowserWindowLayoutModeSmall) {
        [BrowserWindowLayoutPresetStore setSmallFramePreset:frame
                                                transparent:self.transparentModeEnabled];
    }
}

- (void)setTransparentModeEnabled:(BOOL)transparentModeEnabled {
    if (transparentModeEnabled && (self.window.styleMask & NSWindowStyleMaskFullScreen)) {
        [self.chromeActionsView setOn:NO forItemID:BrowserChromeActionTransparentModeID];
        return;
    }

    if (_transparentModeEnabled == transparentModeEnabled) {
        [self.chromeActionsView setOn:transparentModeEnabled forItemID:BrowserChromeActionTransparentModeID];
        return;
    }

    _transparentModeEnabled = transparentModeEnabled;
    [self.chromeActionsView setOn:transparentModeEnabled forItemID:BrowserChromeActionTransparentModeID];

    if (transparentModeEnabled) {
        if (self.window.isVisible) {
            [self enterTransparentModeChrome];
        } else {
            self.transparentModeChromeSetupPending = YES;
        }
    } else {
        self.transparentModeChromeSetupPending = NO;
        self.transparentChromeStableLayoutPending = NO;
        if (self.transparentModeController.hasSnapshot || self.transparentChromeStableLayoutActive) {
            [self exitTransparentModeChrome];
        } else {
            self.transparentChromeAutoHideController.enabled = NO;
        }
    }

    [[BrowserStatusItemController sharedController] refreshMenuAppearance];
    [self schedulePersistTabSession];
    [self schedulePersistLayoutPresetIfNeeded];
}

- (BOOL)shouldSuppressContextMenuForTransparentRightDrag {
    return self.transparentModeEnabled
        && self.transparentModeController.shouldSuppressContextMenuForRightDrag;
}

- (NSArray<WKWebView *> *)liveWebViewsForTransparentMode {
    NSMutableArray<WKWebView *> *views = [NSMutableArray array];
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab.webView) {
            [views addObject:tab.webView];
        }
    }
    return [views copy];
}

- (void)setStandardWindowButtonsHidden:(BOOL)hidden {
    static const NSWindowButton kButtons[] = {
        NSWindowCloseButton,
        NSWindowMiniaturizeButton,
        NSWindowZoomButton,
    };
    for (NSUInteger i = 0; i < sizeof(kButtons) / sizeof(kButtons[0]); i++) {
        NSButton *button = [self.window standardWindowButton:kButtons[i]];
        button.hidden = hidden;
    }
}

- (void)dismissTransientUIForTransparentMode {
    [self.findBarController hideFindBarClearingHighlights:YES];
    if (self.isTabOverviewVisible) {
        [self hideTabOverview];
    }
    if (self.downloadPanelVisible && self.downloadPanel.isVisible) {
        [self.downloadPanel dismissPanel];
        self.downloadPanelVisible = NO;
    }
    if ([self.addressAutocompleteController isPanelVisible]) {
        [self.addressAutocompleteController dismissPanel];
    }
    // 验证码面板若打开则关掉
    if (self.captchaAssistController) {
        NSNumber *visible = nil;
        @try {
            visible = [self.captchaAssistController valueForKey:@"panelVisible"];
        } @catch (__unused NSException *ex) {
            visible = nil;
        }
        if (visible.boolValue) {
            [self.captchaAssistController toggleCaptchaAssistPanel:nil];
        }
    }
}

- (void)enterTransparentModeChrome {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    self.addressBarPeekActive = NO;
    [self dismissTransientUIForTransparentMode];

    [self.trailingSidebarSlot hideAllAnimated:NO];

    [self.transparentModeController captureSnapshotFromWindow:window
                                            contentContainer:self.contentContainer];

    // TC：保留标签条与交通灯；地址栏跟随精简 + TH 自动藏壳
    if (self.tabStripAccessory
        && ![window.titlebarAccessoryViewControllers containsObject:self.tabStripAccessory]) {
        [window addTitlebarAccessoryViewController:self.tabStripAccessory];
    }

    if (self.compactModeEnabled) {
        [self moveNavButtonsToTabStrip];
    } else {
        [self moveNavButtonsToToolbar];
    }
    self.tabStripView.compactMetricsEnabled = self.compactModeEnabled;

    [self.transparentModeController applyWindowTransparency:window
                                          contentContainer:self.contentContainer
                                                  webViews:[self liveWebViewsForTransparentMode]];

    self.launchpadView.hidden = YES;
    [self syncTransparentPageStyleForSelection];
    [self.transparentModeController setWindowRightDragMoveEnabled:YES];

    self.transparentChromeStableLayoutPending = YES;
    if (self.window.isVisible) {
        [self finishTransparentChromeStableSetupIfNeeded];
    }
}

- (void)exitTransparentModeChrome {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    // 取消待执行的风格 refresh，避免退出后仍把设置色写回页面
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshTransparentPageStyleForSelection)
                                               object:nil];

    self.transparentModeChromeSetupPending = NO;
    self.transparentChromeAutoHideController.enabled = NO;
    self.transparentChromeStableLayoutPending = NO;

    [self disableTransparentChromeStableLayout];

    [self.transparentModeController setWindowRightDragMoveEnabled:NO];

    for (WKWebView *webView in [self liveWebViewsForTransparentMode]) {
        [self.transparentModeController removeTransparentPageStyleFromWebView:webView];
    }

    [self.transparentModeController restoreWindowAppearance:window
                                          contentContainer:self.contentContainer
                                                  webViews:[self liveWebViewsForTransparentMode]];

    // 标签条在透明态一直保留；兜底确保 accessory 仍挂在窗上
    if (self.tabStripAccessory
        && ![window.titlebarAccessoryViewControllers containsObject:self.tabStripAccessory]) {
        [window addTitlebarAccessoryViewController:self.tabStripAccessory];
    }

    // 重放精简布局（透明期间可能改过 compact）
    if (self.compactModeEnabled) {
        [self moveNavButtonsToTabStrip];
    } else {
        [self moveNavButtonsToToolbar];
    }
    self.tabStripView.compactMetricsEnabled = self.compactModeEnabled;
    [self applyChromeVisibilityForCurrentMode];
    [self applyAlwaysOnTopWindowLevel];

    // NTP launchpad 显隐由 refreshTabsUI 接管
    [self refreshTabsUI];

    [window.contentView layoutSubtreeIfNeeded];
    [self.tabStripView layoutSubtreeIfNeeded];
    [self scheduleTrafficLightPositioning];
    [self collapseSystemTitlebarDecoration];
}

- (void)setAlwaysOnTopEnabled:(BOOL)alwaysOnTopEnabled {
    _alwaysOnTopEnabled = alwaysOnTopEnabled;
    [self.chromeActionsView setOn:alwaysOnTopEnabled forItemID:BrowserChromeActionAlwaysOnTopID];
    [self applyAlwaysOnTopWindowLevel];
}

- (void)applyAlwaysOnTopWindowLevel {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    // 全屏空间内浮动 level 语义弱化；退出全屏后再应用。
    if (window.styleMask & NSWindowStyleMaskFullScreen) {
        return;
    }
    window.level = self.alwaysOnTopEnabled ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

/// 保证附属浮层不低于父窗，避免置顶后被压在下面。
- (void)ensureFloatingPanel:(NSWindow *)panel aboveParentWindow:(NSWindow *)parent {
    if (!panel || !parent) {
        return;
    }
    NSInteger minLevel = (NSInteger)parent.level + 1;
    if ((NSInteger)panel.level < minLevel) {
        panel.level = (NSWindowLevel)minLevel;
    }
}

- (void)setCompactModeEnabled:(BOOL)compactModeEnabled {
    if (_compactModeEnabled == compactModeEnabled) {
        [self.chromeActionsView setOn:compactModeEnabled forItemID:BrowserChromeActionCompactModeID];
        return;
    }

    // Peek 中关闭精简：退出 compact 并保持工具栏展开
    if (!compactModeEnabled && self.addressBarPeekActive) {
        self.addressBarPeekActive = NO;
    }

    _compactModeEnabled = compactModeEnabled;
    [self.chromeActionsView setOn:compactModeEnabled forItemID:BrowserChromeActionCompactModeID];

    if (compactModeEnabled) {
        [self moveNavButtonsToTabStrip];
    } else {
        [self moveNavButtonsToToolbar];
    }

    self.tabStripView.compactMetricsEnabled = compactModeEnabled;
    [self applyChromeVisibilityForCurrentMode];
    if (self.window.isVisible) {
        [self.window.contentView layoutSubtreeIfNeeded];
        [self.tabStripView layoutSubtreeIfNeeded];
        [self scheduleTrafficLightPositioning];
    }
}

- (void)moveNavButtonsToTabStrip {
    if (self.tabStripView.leadingNavigationView == self.navButtons) {
        self.reloadButton.hidden = YES;
        return;
    }
    [self.navButtons removeFromSuperview];
    self.reloadButton.hidden = YES;
    self.tabStripView.leadingNavigationView = self.navButtons;
}

- (void)moveNavButtonsToToolbar {
    if (self.tabStripView.leadingNavigationView == self.navButtons) {
        self.tabStripView.leadingNavigationView = nil;
    }
    self.reloadButton.hidden = NO;
    if (![self.toolbar.arrangedSubviews containsObject:self.navButtons]) {
        [self.toolbar insertArrangedSubview:self.navButtons atIndex:0];
    }
}

/// 非透明：条/灯常显，地址栏跟精简。透明：条/灯随指针；地址栏精简永藏，非精简随指针；Peek 强制显栏。
- (CGFloat)effectiveTransparentChromeToolbarHeight {
    if (!self.toolbar) {
        return 0.0;
    }
    [self.toolbar layoutSubtreeIfNeeded];
    NSSize fittingSize = self.toolbar.fittingSize;
    CGFloat height = fittingSize.height;
    if (height > 1.0) {
        return height;
    }
    // 地址栏 25 + 上下 inset 4+4
    return 33.0;
}

- (void)enableTransparentChromeStableLayout {
    if (self.transparentChromeStableLayoutActive || !self.rootStack) {
        return;
    }

    self.rootStackTopToContentGuideConstraint.active = NO;
    self.rootStackTopToContentViewConstraint.active = YES;

    if (self.tabStripAccessoryHeightConstraint) {
        self.tabStripAccessoryHeightConstraint.constant = self.tabStripView.effectiveStripHeight;
    }

    if (!self.transparentChromeToolbarHeightConstraint) {
        if (!self.compactModeEnabled) {
            self.transparentChromeToolbarFullHeight = [self effectiveTransparentChromeToolbarHeight];
            self.transparentChromeToolbarHeightConstraint =
                [self.toolbar.heightAnchor constraintEqualToConstant:self.transparentChromeToolbarFullHeight];
            self.transparentChromeToolbarHeightConstraint.active = YES;
        }
    }

    self.transparentChromeStableLayoutActive = YES;
}

- (void)disableTransparentChromeStableLayout {
    if (!self.transparentChromeStableLayoutActive) {
        return;
    }

    self.transparentChromeStableLayoutActive = NO;

    if (self.transparentChromeToolbarHeightConstraint) {
        self.transparentChromeToolbarHeightConstraint.active = NO;
        self.transparentChromeToolbarHeightConstraint = nil;
    }
    self.transparentChromeToolbarFullHeight = 0.0;

    self.rootStackTopToContentViewConstraint.active = NO;
    self.rootStackTopToContentGuideConstraint.active = YES;

    if (self.tabStripAccessoryRoot) {
        self.tabStripAccessoryRoot.hidden = NO;
        self.tabStripAccessoryRoot.alphaValue = 1.0;
    }
    if (self.toolbar) {
        self.toolbar.hidden = NO;
        self.toolbar.alphaValue = 1.0;
    }
    if (self.tabStripAccessoryHeightConstraint) {
        self.tabStripAccessoryHeightConstraint.constant = self.tabStripView.effectiveStripHeight;
    }
}

- (void)finishDeferredTransparentModeSetupIfNeeded {
    if (!self.transparentModeEnabled) {
        return;
    }
    if (self.transparentModeChromeSetupPending) {
        self.transparentModeChromeSetupPending = NO;
        [self enterTransparentModeChrome];
        return;
    }
    [self finishTransparentChromeStableSetupIfNeeded];
}

- (void)finishTransparentChromeStableSetupIfNeeded {
    if (!self.transparentModeEnabled || !self.transparentChromeStableLayoutPending) {
        return;
    }
    self.transparentChromeStableLayoutPending = NO;
    [self enableTransparentChromeStableLayout];
    self.transparentChromeAutoHideController.enabled = YES;
    [self applyChromeVisibilityForCurrentMode];
    [self collapseSystemTitlebarDecoration];
    if (self.transparentChromeAutoHideController.chromeRevealed) {
        [self.tabStripView layoutSubtreeIfNeeded];
        [self scheduleTrafficLightPositioning];
    }
}

- (void)applyTransparentChromeStableVisibilityTabStrip:(BOOL)showTabStrip
                                              toolbar:(BOOL)showToolbar {
    if (self.tabStripAccessoryRoot) {
        self.tabStripAccessoryRoot.alphaValue = showTabStrip ? 1.0 : 0.0;
    }
    if (self.tabStripAccessoryHeightConstraint) {
        self.tabStripAccessoryHeightConstraint.constant = self.tabStripView.effectiveStripHeight;
    }

    CGFloat toolbarHeight = 0.0;
    if (!self.compactModeEnabled) {
        toolbarHeight = self.transparentChromeToolbarFullHeight;
        if (toolbarHeight <= 0.0) {
            toolbarHeight = [self effectiveTransparentChromeToolbarHeight];
            self.transparentChromeToolbarFullHeight = toolbarHeight;
        }
    }
    if (self.transparentChromeToolbarHeightConstraint) {
        self.transparentChromeToolbarHeightConstraint.constant = toolbarHeight;
    }
    if (self.toolbar) {
        self.toolbar.alphaValue = showToolbar ? 1.0 : 0.0;
        self.toolbar.hidden = NO;
    }

    if (showTabStrip) {
        [self scheduleTrafficLightPositioning];
    }
}

- (void)setTransparentChromeRevealSuppressedForDrag:(BOOL)transparentChromeRevealSuppressedForDrag {
    if (_transparentChromeRevealSuppressedForDrag == transparentChromeRevealSuppressedForDrag) {
        return;
    }
    _transparentChromeRevealSuppressedForDrag = transparentChromeRevealSuppressedForDrag;
    if (self.transparentModeEnabled) {
        [self applyChromeVisibilityForCurrentMode];
    }
}

- (void)applyChromeVisibilityForCurrentMode {
    BOOL transparent = self.transparentModeEnabled;
    BOOL chromeRevealed = !transparent || (self.transparentChromeAutoHideController.chromeRevealed
                                           && !self.transparentChromeRevealSuppressedForDrag);
    BOOL showTabStrip = !transparent || chromeRevealed;

    BOOL showToolbar = NO;
    if (self.addressBarPeekActive) {
        showToolbar = YES;
    } else if (self.compactModeEnabled) {
        showToolbar = NO;
    } else if (!transparent) {
        showToolbar = YES;
    } else {
        showToolbar = chromeRevealed;
    }

    [self setStandardWindowButtonsHidden:!showTabStrip];

    if (transparent && self.transparentChromeStableLayoutActive) {
        [self applyTransparentChromeStableVisibilityTabStrip:showTabStrip toolbar:showToolbar];
        [self syncTransparentPointerOutsideToSelectedPage:!chromeRevealed];
        return;
    }

    if (self.tabStripAccessoryRoot) {
        self.tabStripAccessoryRoot.hidden = !showTabStrip;
    }
    CGFloat stripHeight = showTabStrip ? self.tabStripView.effectiveStripHeight : 0.0;
    if (self.tabStripAccessoryHeightConstraint) {
        self.tabStripAccessoryHeightConstraint.constant = stripHeight;
    }
    self.toolbar.hidden = !showToolbar;

    if (self.window.isVisible) {
        [self.window.contentView layoutSubtreeIfNeeded];
        if (showTabStrip) {
            [self.tabStripView layoutSubtreeIfNeeded];
            [self scheduleTrafficLightPositioning];
        }
    }

    if (transparent) {
        [self syncTransparentPointerOutsideToSelectedPage:!chromeRevealed];
    }
}

/// 透明模式下把「指针是否在窗外」同步给当前页（微信读书底栏等据此隐藏）。
- (void)syncTransparentPointerOutsideToSelectedPage:(BOOL)pointerOutside {
    BrowserTab *selected = self.tabController.selectedTab;
    WKWebView *webView = selected.isNewTabPage ? nil : selected.webView;
    if (!webView) {
        return;
    }
    [self.transparentModeController setPointerOutside:pointerOutside onWebView:webView];
}

- (void)applyToolbarVisibilityForCompactState {
    [self applyChromeVisibilityForCurrentMode];
}

- (void)beginAddressBarPeek {
    if (!self.compactModeEnabled) {
        return;
    }
    self.addressBarPeekActive = YES;
    [self applyChromeVisibilityForCurrentMode];
}

- (void)endAddressBarPeekResigning:(BOOL)resignFirstResponder {
    if (!self.addressBarPeekActive) {
        if (resignFirstResponder) {
            [self resignAddressBarFocusIfNeeded];
        }
        return;
    }
    self.addressBarPeekActive = NO;
    [self applyChromeVisibilityForCurrentMode];
    if (resignFirstResponder) {
        [self resignAddressBarFocusIfNeeded];
    }
}

- (void)resignAddressBarFocusIfNeeded {
    NSResponder *first = self.window.firstResponder;
    NSText *editor = self.addressField.currentEditor;
    if (first == self.addressField || first == editor) {
        [self.window makeFirstResponder:self.webView ?: (NSResponder *)self.window];
    }
}

- (void)focusAddressBar:(id)sender {
    (void)sender;
    if (self.compactModeEnabled) {
        [self beginAddressBarPeek];
    }
    [self.window makeFirstResponder:self.addressField];
    [self.addressField selectText:nil];
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

- (void)updateTabOverviewButtonAppearance {
    NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionTabOverviewID];
    if (!button) {
        return;
    }
    BOOL visible = self.tabOverviewController.isVisible;
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

- (void)updateNotificationInboxButtonAppearance {
    NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionNotificationInboxID];
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
    if (unread > 0) {
        button.toolTip = [NSString stringWithFormat:@"手机通知 · %lu 条未读", (unsigned long)MIN(unread, 99)];
    } else {
        button.toolTip = open ? @"手机通知（已打开）" : @"手机通知";
    }
    self.notificationInboxBadgeView.hidden = (unread == 0);
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
    [self updateHistoryButtonAppearance];
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
    [self updateHistoryButtonAppearance];
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
    [self updateNotificationInboxButtonAppearance];
    [self updateHistoryButtonAppearance];
}

- (void)showAssistSidebar:(id)sender {
    [self setAssistSidebarVisible:YES revealingRecipeID:nil memoID:nil];
}

- (void)assistSidebarDidRequestClose:(AssistSidebarController *)controller {
    (void)controller;
    [self.trailingSidebarSlot setAssistVisible:NO animated:YES];
    [self updateNotificationInboxButtonAppearance];
    [self updateHistoryButtonAppearance];
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
    [self updateChromeCompanionToolAppearance];
}

- (void)updateChromeCompanionToolAppearance {
    CompanionLinkUIState state = [CompanionLinkUI stateFromChannel:[CompanionChannel sharedChannel]];
    NSString *title = [CompanionLinkUI titleForChannel:[CompanionChannel sharedChannel]];
    BOOL connected = (state == CompanionLinkUIStateConnected);

    NSButton *link = [self.chromeActionsView buttonForItemID:BrowserChromeActionCompanionLinkID];
    if (link) {
        link.alphaValue = (state == CompanionLinkUIStateDisconnected) ? 0.7 : 1.0;
        link.toolTip = [NSString stringWithFormat:@"互联 · %@", title];
        link.accessibilityLabel = link.toolTip;
    }
    NSButton *send = [self.chromeActionsView buttonForItemID:BrowserChromeActionSendToPhoneID];
    if (send) {
        send.alphaValue = connected ? 1.0 : 0.7;
        send.toolTip = connected ? @"发送到手机" : @"发送到手机（未连接）";
        send.accessibilityLabel = send.toolTip;
        send.enabled = connected;
    }
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
    [self.addressAutocompleteController dismissPanel];
    if (!self.downloadPanel) {
        self.downloadPanel = [[BrowserDownloadPanel alloc] init];
        self.downloadPanel.panelDelegate = self;
        self.downloadPanel.manager = self.downloadManager;
    }
    [self.downloadManager markAllCompletedAsRead];
    [self updateDownloadButtonAppearance];

    NSButton *anchor = self.downloadButton
        ?: [self.chromeActionsView buttonForItemID:BrowserChromeActionDownloadID]
        ?: [self.chromeActionsView buttonForItemID:BrowserChromeActionMoreMenuID];
    if (!anchor) {
        return;
    }
    NSRect buttonRect = [anchor convertRect:anchor.bounds toView:nil];
    NSRect screenRect = [self.window convertRectToScreen:buttonRect];
    self.downloadPanel.dismissExclusionRectOnScreen = NSInsetRect(screenRect, -4, -4);
    [self ensureFloatingPanel:self.downloadPanel aboveParentWindow:self.window];
    [self.downloadPanel presentAnchoredToRect:screenRect ofWindow:self.window];
    self.downloadPanelVisible = YES;
}

- (void)downloadPanelDidRequestClose:(BrowserDownloadPanel *)panel {
    (void)panel;
    self.downloadPanelVisible = NO;
}

- (void)downloadPanelDidRequestSettings:(BrowserDownloadPanel *)panel {
    (void)panel;
    id delegate = NSApp.delegate;
    if ([delegate respondsToSelector:@selector(showBrowserSettingsSelectingTabIdentifier:)]) {
        [(AppDelegate *)delegate showBrowserSettingsSelectingTabIdentifier:BrowserSettingsTabGeneral];
    } else if ([delegate respondsToSelector:@selector(showBrowserSettings:)]) {
        [delegate showBrowserSettings:nil];
    }
}

#pragma mark - History Sidebar

- (void)toggleHistoryPanel:(id)sender {
    (void)sender;
    BOOL open = !self.historySidebarController.visible;
    [self.trailingSidebarSlot setHistoryVisible:open animated:YES];
    [self updateHistoryButtonAppearance];
    [self updateNotificationInboxButtonAppearance];
}

- (void)historySidebarDidRequestClose:(BrowserHistorySidebarController *)controller {
    (void)controller;
    [self.trailingSidebarSlot setHistoryVisible:NO animated:YES];
    [self updateHistoryButtonAppearance];
    [self updateNotificationInboxButtonAppearance];
}

- (void)historySidebar:(BrowserHistorySidebarController *)controller
               openURL:(NSURL *)url
              inNewTab:(BOOL)inNewTab {
    (void)controller;
    if (inNewTab) {
        [self launchpadView:self.launchpadView openURLInNewTab:url];
    } else {
        [self launchpadView:self.launchpadView openURL:url];
    }
}

- (void)historySidebar:(BrowserHistorySidebarController *)controller didChangeWidth:(CGFloat)width {
    (void)controller;
    (void)width;
}

#pragma mark - Page Pack Sidebar

- (void)togglePagePackSidebar:(id)sender {
    (void)sender;
    BOOL open = !self.pagePackSidebarController.visible;
    [self.trailingSidebarSlot setPagePackVisible:open animated:YES];
    [self updatePagePackButtonAppearance];
    [self updateHistoryButtonAppearance];
    [self updateNotificationInboxButtonAppearance];
}

- (void)pagePackSidebarDidRequestClose:(PagePackSidebarController *)controller {
    (void)controller;
    [self.trailingSidebarSlot setPagePackVisible:NO animated:YES];
    [self updatePagePackButtonAppearance];
}

- (void)pagePackSidebar:(PagePackSidebarController *)controller didChangeWidth:(CGFloat)width {
    (void)controller;
    (void)width;
}

- (NSURL *)pagePackSidebarCurrentURL:(PagePackSidebarController *)controller {
    (void)controller;
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        return nil;
    }
    return [BrowserWebView publicURLFromInternalURL:self.webView.URL] ?: self.webView.URL;
}

- (WKWebView *)pagePackSidebarCurrentWebView:(PagePackSidebarController *)controller {
    (void)controller;
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        return nil;
    }
    return self.webView;
}

- (void)pagePackSidebarDidRequestReloadPage:(PagePackSidebarController *)controller {
    (void)controller;
    [self reloadPage:nil];
}

- (void)reloadPagePackSidebarIfVisible {
    if (self.pagePackSidebarController.visible) {
        [self.pagePackSidebarController reloadForCurrentURL];
    }
}

- (void)updatePagePackButtonAppearance {
    NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionExtensionID];
    if (!button) {
        return;
    }
    BOOL visible = self.pagePackSidebarController.visible;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = visible ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }
}

- (void)updateHistoryButtonAppearance {
    NSButton *button = [self.chromeActionsView buttonForItemID:BrowserChromeActionHistoryID];
    if (!button) {
        return;
    }
    BOOL visible = self.historySidebarController.visible;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = visible ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }
    if (@available(macOS 11.0, *)) {
        NSString *symbol = visible ? @"clock.fill" : @"clock";
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:15
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"历史"];
        button.image = [image imageWithSymbolConfiguration:config];
    }
}

- (void)downloadManagerDidChange:(BrowserDownloadManager *)manager {
    (void)manager;
    [self updateDownloadButtonAppearance];
    if (self.downloadPanelVisible && self.downloadPanel.isVisible) {
        [self.downloadPanel reloadFromManager];
    }
}

- (void)updateDownloadButtonAppearance {
    if (!self.downloadButton) {
        self.downloadButton = [self.chromeActionsView buttonForItemID:BrowserChromeActionDownloadID];
    }
    if (!self.downloadButton) {
        return;
    }

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

- (NSButton *)makeTranslateButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.target = self;
    button.action = @selector(showPageTranslationMenu:);
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"翻译网页";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:16],
        [button.heightAnchor constraintEqualToConstant:16],
    ]];
    NSImage *image = [self translateSymbolImage];
    if (image) {
        button.image = image;
    }
    return button;
}

- (NSImage *)translateSymbolImage {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:11
                                                            weight:NSFontWeightRegular
                                                             scale:NSImageSymbolScaleSmall];
        NSArray<NSString *> *candidates = @[ @"translate", @"character.bubble", @"text.bubble" ];
        for (NSString *name in candidates) {
            NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:@"翻译"];
            if (image) {
                return [image imageWithSymbolConfiguration:config];
            }
        }
    }
    return nil;
}

- (void)updateTranslateButtonState {
    BrowserTab *tab = self.tabController.selectedTab;
    WKWebView *webView = self.webView;
    BOOL pageOK = tab != nil && !tab.isNewTabPage && webView != nil
        && [BrowsingPreferences isPersistableURL:(webView.URL ?: [tab currentOrRestorableURL])];
    self.translateButton.enabled = pageOK;
    BrowserPageTranslationUIState state = [self.pageTranslationController uiStateForWebView:webView];
    if (@available(macOS 10.14, *)) {
        if (!pageOK) {
            self.translateButton.contentTintColor = [NSColor tertiaryLabelColor];
        } else if (state == BrowserPageTranslationUIStateTranslating) {
            self.translateButton.contentTintColor = [NSColor controlAccentColor];
        } else if (state == BrowserPageTranslationUIStateTranslated) {
            self.translateButton.contentTintColor = [NSColor systemBlueColor];
        } else {
            self.translateButton.contentTintColor = [NSColor secondaryLabelColor];
        }
    }
    switch (state) {
        case BrowserPageTranslationUIStateTranslating:
            self.translateButton.toolTip = @"正在翻译…（打开菜单可取消）";
            break;
        case BrowserPageTranslationUIStateTranslated: {
            BrowserTranslationPresentationMode mode =
                [self.pageTranslationController presentationModeForWebView:webView];
            if (mode == BrowserTranslationPresentationModeBilingual) {
                self.translateButton.toolTip = @"双语对照中（可恢复原文）";
            } else if (mode == BrowserTranslationPresentationModeHover) {
                self.translateButton.toolTip = @"即指即译已开启（可恢复原文）";
            } else {
                self.translateButton.toolTip = @"已显示译文（可恢复原文）";
            }
            break;
        }
        case BrowserPageTranslationUIStateIdle:
        default:
            self.translateButton.toolTip = @"翻译网页";
            break;
    }
}

- (void)showPageTranslationMenu:(id)sender {
    (void)sender;
    self.pageTranslationController.hostWindow = self.window;
    [self.pageTranslationController showMenuFromButton:self.translateButton
                                            forWebView:self.webView
                                                   tab:self.tabController.selectedTab];
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
        [self updateTranslateButtonState];
        return;
    }

    NSString *normalized = [BrowserShortcutStore normalizedURLStringFromInput:url.absoluteString];
    BOOL bookmarked = normalized ? [BrowserShortcutStore isURLStringBookmarked:normalized] : NO;
    [self setBookmarkButtonFilled:bookmarked enabled:YES];
    [self updateTranslateButtonState];
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
                                       iconStyle:BrowserShortcutIconStyleAuto
                                      iconLetter:@""
                                  iconColorIndex:0
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
        [self applyChromeStateFromSessionDictionary:session];
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
    [self applyChromeStateFromSessionDictionary:session];
}

- (void)applyChromeStateFromSessionDictionary:(nullable NSDictionary *)session {
    BOOL compact = NO;
    BOOL alwaysOnTop = NO;
    BOOL transparent = NO;
    BOOL afk = NO;
    if ([session isKindOfClass:[NSDictionary class]]) {
        NSNumber *compactValue = session[BrowserWindowSessionCompactModeKey];
        if ([compactValue isKindOfClass:[NSNumber class]]) {
            compact = compactValue.boolValue;
        }
        NSNumber *alwaysOnTopValue = session[BrowserWindowSessionAlwaysOnTopKey];
        if ([alwaysOnTopValue isKindOfClass:[NSNumber class]]) {
            alwaysOnTop = alwaysOnTopValue.boolValue;
        }
        NSNumber *transparentValue = session[BrowserWindowSessionTransparentModeKey];
        if ([transparentValue isKindOfClass:[NSNumber class]]) {
            transparent = transparentValue.boolValue;
        }
        NSNumber *afkValue = session[BrowserWindowSessionAfkModeKey];
        if ([afkValue isKindOfClass:[NSNumber class]]) {
            afk = afkValue.boolValue;
        }
    }
    [self setCompactModeEnabled:compact];
    [self setAlwaysOnTopEnabled:alwaysOnTop];
    [self setTransparentModeEnabled:transparent];
    [self setAfkModeEnabled:afk];
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
        NSMutableDictionary *empty = [@{
            BrowserWindowSessionTabsKey: @[BrowserTabSessionNewTabMarker],
            BrowserWindowSessionSelectedIndexKey: @0,
            BrowserWindowSessionPinnedCountKey: @0,
        } mutableCopy];
        if (self.compactModeEnabled) {
            empty[BrowserWindowSessionCompactModeKey] = @YES;
        }
        if (self.alwaysOnTopEnabled) {
            empty[BrowserWindowSessionAlwaysOnTopKey] = @YES;
        }
        if (self.transparentModeEnabled) {
            empty[BrowserWindowSessionTransparentModeKey] = @YES;
        }
        if (self.afkModeEnabled) {
            empty[BrowserWindowSessionAfkModeKey] = @YES;
        }
        if (self.window) {
            empty[BrowserWindowSessionFrameKey] = NSStringFromRect(self.window.frame);
        }
        return [empty copy];
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
    if (self.compactModeEnabled) {
        session[BrowserWindowSessionCompactModeKey] = @YES;
    }
    if (self.alwaysOnTopEnabled) {
        session[BrowserWindowSessionAlwaysOnTopKey] = @YES;
    }
    if (self.transparentModeEnabled) {
        session[BrowserWindowSessionTransparentModeKey] = @YES;
    }
    if (self.afkModeEnabled) {
        session[BrowserWindowSessionAfkModeKey] = @YES;
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
    // 切走标签不取消导航超时：后台标签仍可独立超时失败。
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
    [webView setNeedsLayout:YES];
    [webView setNeedsDisplay:YES];
    [superview setNeedsLayout:YES];
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
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if ([strongSelf openURLInExternalApplicationIfNeeded:url]) {
                return;
            }
            [strongSelf.tabController addTabWithURL:url];
        };
        browserWebView.openURLInNewWindowHandler = ^(NSURL *url) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if ([strongSelf openURLInExternalApplicationIfNeeded:url]) {
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
    tab.navigationSessionDidBeginHandler = ^(BrowserTab *changedTab, BrowserNavigationSession *session) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !session) {
            return;
        }
        WKWebView *sessionWebView = changedTab.webView;
        if (!sessionWebView) {
            return;
        }
        [strongSelf startOverallNavigationWatchdogForWebView:sessionWebView
                                                     session:session
                                                         URL:session.URL];
        BrowserNavigationLog(@"nav-begin tab=%@ gen=%ld url=%@",
                             changedTab.tabID.UUIDString,
                             (long)session.generation,
                             session.URL.absoluteString ?: @"(nil)");
        [strongSelf startReachabilityProbeForWebView:sessionWebView
                                                 tab:changedTab
                                             session:session
                                                 URL:session.URL];
        if (sessionWebView == strongSelf.webView) {
            [strongSelf.loadingProgressView beginLoading];
            [strongSelf updateReloadStopButtonAppearance];
        }
        [strongSelf updateTabStripDisplay];
    };
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

    // Element Fullscreen 时 WebKit 已把 WKWebView 挪到自有全屏窗口。
    // 若此处再 addSubview 回 contentContainer，会拆掉全屏层级 → 全屏区黑屏
    //（常见于后台标签休眠触发 refreshTabsUI → attach）。退出全屏才看似「恢复」。
    if ([self webViewIsInElementFullscreen:webView]) {
        [self pinWebViewLayoutInSuperview:webView];
        [self observeFullscreenStateForSelectedTab];
        [self startFullscreenLayoutRepairIfNeededForWebView:webView];
        return;
    }
    if (webView.superview != nil && webView.superview != self.contentContainer) {
        // 过渡态或其它宿主：勿强行抢回，只保证当前父视图内铺满。
        [self pinWebViewLayoutInSuperview:webView];
        [self observeFullscreenStateForSelectedTab];
        return;
    }

    if (webView.superview != self.contentContainer) {
        [self.contentContainer addSubview:webView];
    }
    [self pinWebViewLayoutInSuperview:webView];
    [self applyTransparentAppearanceIfNeededForWebView:webView];
    [self observeFullscreenStateForSelectedTab];
}

- (void)applyTransparentAppearanceIfNeededForWebView:(WKWebView *)webView {
    if (!self.transparentModeEnabled || !webView) {
        return;
    }
    [self.transparentModeController applyWindowTransparency:self.window
                                          contentContainer:self.contentContainer
                                                  webViews:@[webView]];
    if (webView == self.webView) {
        [self.transparentModeController applyTransparentPageStyleToWebView:webView];
        BOOL chromeRevealed = self.transparentChromeAutoHideController.chromeRevealed
            && !self.transparentChromeRevealSuppressedForDrag;
        [self.transparentModeController setPointerOutside:!chromeRevealed onWebView:webView];
    }
}

/// 仅对当前可见 WebView 注入透明模式样式；其它存活页移除，避免切回脏样式。
- (void)syncTransparentPageStyleForSelection {
    if (!self.transparentModeEnabled) {
        return;
    }
    BrowserTab *selected = self.tabController.selectedTab;
    WKWebView *selectedWebView = selected.isNewTabPage ? nil : selected.webView;
    BOOL chromeRevealed = self.transparentChromeAutoHideController.chromeRevealed
        && !self.transparentChromeRevealSuppressedForDrag;
    for (BrowserTab *tab in self.tabController.tabs) {
        WKWebView *webView = tab.webView;
        if (!webView) {
            continue;
        }
        if (webView == selectedWebView) {
            [self.transparentModeController applyTransparentPageStyleToWebView:webView];
            [self.transparentModeController setPointerOutside:!chromeRevealed onWebView:webView];
        } else {
            [self.transparentModeController removeTransparentPageStyleFromWebView:webView];
        }
    }
}

/// 设置面板改风格时用轻量 refresh，避免全页遍历 / 多次像素重绘造成白屏卡顿。
- (void)refreshTransparentPageStyleForSelection {
    if (!self.transparentModeEnabled) {
        return;
    }
    BrowserTab *selected = self.tabController.selectedTab;
    WKWebView *webView = selected.isNewTabPage ? nil : selected.webView;
    if (!webView) {
        return;
    }
    [self.transparentModeController refreshTransparentPageStyleOnWebView:webView];
}

- (void)transparentModePreferencesDidChange:(NSNotification *)note {
    (void)note;
    if (!self.transparentModeEnabled) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshTransparentPageStyleForSelection)
                                               object:nil];
    [self performSelector:@selector(refreshTransparentPageStyleForSelection)
               withObject:nil
               afterDelay:0.05];
}

- (void)refreshTabsUI {
    BrowserTab *selectedTab = self.tabController.selectedTab;
    self.refreshTabsUIGeneration += 1;
    NSInteger generation = self.refreshTabsUIGeneration;
    NSUUID *selectedIDAtStart = selectedTab.tabID;

    // 仅挂载当前标签的 WebView；其余离屏但仍可常驻（休眠由 TabController 销毁）。
    // 重页：先 pause 媒体；确认无媒体后再异步 takeSnapshot（不堵切页关键路径）。
    for (BrowserTab *tab in self.tabController.tabs) {
        if (tab == selectedTab) {
            continue;
        }
        WKWebView *wv = tab.webView;
        BOOL wasAttached = (wv != nil && wv.superview == self.contentContainer && !tab.isNewTabPage);
        if (wasAttached && wv != nil) {
            __weak typeof(self) weakSelf = self;
            __weak BrowserTab *weakTab = tab;
            __weak WKWebView *weakWebView = wv;
            NSUUID *tabID = tab.tabID;
            BOOL alreadyHeavy = tab.mediaHeavy;
            [BrowserBackgroundMediaController pauseMediaInWebView:wv
                                                       completion:^(BOOL foundMedia) {
                                                           typeof(self) strongSelf = weakSelf;
                                                           BrowserTab *strongTab = weakTab;
                                                           WKWebView *strongWebView = weakWebView;
                                                           if (!strongSelf || !strongTab) {
                                                               return;
                                                           }
                                                           if (foundMedia) {
                                                               strongTab.mediaHeavy = YES;
                                                               return;
                                                           }
                                                           if (alreadyHeavy || strongTab.mediaHeavy) {
                                                               return;
                                                           }
                                                           if (strongTab == strongSelf.tabController.selectedTab) {
                                                               return;
                                                           }
                                                           if (strongWebView == nil || strongWebView != strongTab.webView) {
                                                               return;
                                                           }
                                                           [strongSelf.tabOverviewController.thumbnailCache
                                                               captureFromWebView:strongWebView
                                                                          forTabID:tabID
                                                                        completion:nil];
                                                       }];
        }
        [self detachWebViewIfNeeded:wv];
    }

    if (selectedTab != nil && !selectedTab.isNewTabPage) {
        WKWebView *selectedWebView = selectedTab.webView;
        if ([self webViewIsInElementFullscreen:selectedWebView]) {
            // 当前标签正在 HTML5 全屏：勿 wake/attach 重挂，只维持全屏窗口内布局。
            [self pinWebViewLayoutInSuperview:selectedWebView];
            [self observeFullscreenStateForSelectedTab];
            [self startFullscreenLayoutRepairIfNeededForWebView:selectedWebView];
            selectedWebView.hidden = NO;
        } else {
            // 先创建 WebView → 挂 navigationDelegate → 再 load。
            // 若先 load，document-start 写回 #hash 时无 delegate，代理下会把 # 编成 %23 → 404。
            [selectedTab wakeFromHibernationIfNeeded];
            [self attachWebViewForTab:selectedTab];
            [selectedTab loadPendingRestorableURLIfNeeded];
            if (selectedTab.webView != nil) {
                selectedTab.webView.hidden = NO;
            }
            if (selectedTab.pendingHardRecover) {
                [self presentHardRecoverErrorForSelectedTabIfNeeded];
            }
        }
    } else if (selectedTab != nil) {
        [self detachWebViewIfNeeded:selectedTab.webView];
    }

    BOOL showLaunchpad = selectedTab.isNewTabPage;
    self.launchpadView.hidden = !showLaunchpad || self.transparentModeEnabled;

    [self.contentContainer addSubview:self.loadingProgressView positioned:NSWindowAbove relativeTo:nil];
    [self.contentContainer addSubview:self.certificateWarningView positioned:NSWindowAbove relativeTo:nil];
    [self.contentContainer addSubview:self.navigationErrorView positioned:NSWindowAbove relativeTo:nil];
    if (self.findBarController.isVisible) {
        [self.contentContainer addSubview:self.findBarController.findBarView positioned:NSWindowAbove relativeTo:nil];
    }
    if (self.tabOverviewController.isVisible) {
        [self.tabOverviewController bringToFront];
    }
    [self.findBarController syncWithSelectedTab];
    [self observeLoadingProgressForSelectedTab];

    // 切换标签时结束地址栏编辑，避免不安全徽章的 leading inset 留在 field editor 里带到新标签。
    [self endAddressBarEditingIfNeeded];

    // sync：顺序/数量不变时保留标签视图，避免 mouseDown 选中后重建导致拖拽失效
    [self updateTabStripDisplay];
    [self repositionTrafficLightButtonsAfterLayout];
    [self updateNavigationState];

    NSUUID *selectedID = selectedTab.tabID;
    BOOL selectionChanged = selectedID != nil
        && ![selectedID isEqual:self.lastSelectedTabIDForAddressFocus];
    self.lastSelectedTabIDForAddressFocus = selectedID;
    if (selectionChanged && selectedTab.isNewTabPage) {
        [self focusAddressBarForNewTabPage];
    }

    // 非关键 chrome：下一 runloop，避免占满 mouseDown→切页关键路径。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (strongSelf.refreshTabsUIGeneration != generation) {
            return;
        }
        BrowserTab *stillSelected = strongSelf.tabController.selectedTab;
        if (selectedIDAtStart != nil && ![stillSelected.tabID isEqual:selectedIDAtStart]) {
            return;
        }
        BOOL showLP = stillSelected.isNewTabPage;
        if (showLP && !strongSelf.transparentModeEnabled) {
            [strongSelf.launchpadView reloadShortcuts];
        }
        if (strongSelf.tabOverviewController.isVisible) {
            [strongSelf.tabOverviewController reloadFromTabController];
        }
        [strongSelf syncCertificateWarningVisibilityForSelectedTab];
        [strongSelf syncNavigationErrorVisibilityForSelectedTab];
        [strongSelf updateTabOverviewButtonAppearance];
        if (strongSelf.transparentModeEnabled) {
            [strongSelf syncTransparentPageStyleForSelection];
        }
    });
}

#pragma mark - Loading Progress

- (void)stopObservingLoadingProgress {
    [self cancelPendingProgressUIUpdate];
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

- (BOOL)webViewIsInElementFullscreen:(WKWebView *)webView {
    if (webView == nil) {
        return NO;
    }
    if (@available(macOS 13.0, *)) {
        return webView.fullscreenState != WKFullscreenStateNotInFullscreen;
    }
    return NO;
}

- (void)stopFullscreenLayoutRepair {
    self.fullscreenLayoutRepairGeneration += 1;
    [self.fullscreenLayoutRepairTimer invalidate];
    self.fullscreenLayoutRepairTimer = nil;
}

- (void)startFullscreenLayoutRepairIfNeededForWebView:(WKWebView *)webView {
    if (![self webViewIsInElementFullscreen:webView]) {
        [self stopFullscreenLayoutRepair];
        return;
    }
    if (self.fullscreenLayoutRepairTimer != nil) {
        return;
    }
    self.fullscreenLayoutRepairGeneration += 1;
    NSInteger generation = self.fullscreenLayoutRepairGeneration;
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;

    // 进入全屏后短延迟再钉几次，覆盖 WebKit 异步换父视图 / 清约束的竞态。
    for (NSNumber *delay in @[ @0.0, @0.05, @0.25, @1.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           typeof(self) strongSelf = weakSelf;
                           WKWebView *strongWebView = weakWebView;
                           if (!strongSelf || !strongWebView) {
                               return;
                           }
                           if (strongSelf.fullscreenLayoutRepairGeneration != generation) {
                               return;
                           }
                           if (![strongSelf webViewIsInElementFullscreen:strongWebView]) {
                               return;
                           }
                           [strongSelf pinWebViewLayoutInSuperview:strongWebView];
                       });
    }

    // 长时全屏：若 frame 被剥成空矩形则立即修补（抖音等约数分钟后偶发黑屏）。
    self.fullscreenLayoutRepairTimer =
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                        repeats:YES
                                          block:^(NSTimer *timer) {
                                              (void)timer;
                                              typeof(self) strongSelf = weakSelf;
                                              WKWebView *strongWebView = weakWebView;
                                              if (!strongSelf || !strongWebView) {
                                                  [strongSelf stopFullscreenLayoutRepair];
                                                  return;
                                              }
                                              if (strongSelf.fullscreenLayoutRepairGeneration != generation ||
                                                  ![strongSelf webViewIsInElementFullscreen:strongWebView]) {
                                                  [strongSelf stopFullscreenLayoutRepair];
                                                  return;
                                              }
                                              NSView *superview = strongWebView.superview;
                                              if (superview == nil) {
                                                  return;
                                              }
                                              NSSize viewSize = strongWebView.bounds.size;
                                              NSSize hostSize = superview.bounds.size;
                                              BOOL emptyView = (viewSize.width < 1.0 || viewSize.height < 1.0);
                                              BOOL mismatched = (fabs(viewSize.width - hostSize.width) > 1.0 ||
                                                                 fabs(viewSize.height - hostSize.height) > 1.0);
                                              if (emptyView || mismatched) {
                                                  [strongSelf pinWebViewLayoutInSuperview:strongWebView];
                                              }
                                          }];
    self.fullscreenLayoutRepairTimer.tolerance = 0.5;
}

- (void)stopObservingFullscreenState {
    WKWebView *webView = self.observedFullscreenWebView;
    if (!webView) {
        [self stopFullscreenLayoutRepair];
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
    [self stopFullscreenLayoutRepair];
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
                [self pinWebViewLayoutInSuperview:webView];
                [self startFullscreenLayoutRepairIfNeededForWebView:webView];
                break;
            case WKFullscreenStateExitingFullscreen:
                [self pinWebViewLayoutInSuperview:webView];
                break;
            case WKFullscreenStateNotInFullscreen:
                [self stopFullscreenLayoutRepair];
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
        [self cancelPendingProgressUIUpdate];
        [self syncFromWebView:webView];
        return;
    }

    BOOL terminal = (progress >= 1.0) || (!webView.isLoading && !tab.isLoading);
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    BOOL smallDelta = fabs(progress - self.lastProgressUIValue) < 0.02;
    BOOL tooSoon = (now - self.lastProgressUIUpdateTime) < 0.08;
    if (!terminal && smallDelta && tooSoon) {
        [self scheduleCoalescedProgressUIUpdate];
        return;
    }
    [self applyProgressUIUpdate:progress animated:!terminal];
}

- (void)cancelPendingProgressUIUpdate {
    if (self.pendingProgressUIBlock) {
        dispatch_block_cancel(self.pendingProgressUIBlock);
        self.pendingProgressUIBlock = nil;
    }
}

- (void)scheduleCoalescedProgressUIUpdate {
    if (self.pendingProgressUIBlock) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingProgressUIBlock = nil;
        WKWebView *webView = strongSelf.webView;
        BrowserTab *tab = strongSelf.tabController.selectedTab;
        if (!webView || !tab || tab.isNewTabPage) {
            return;
        }
        [strongSelf applyProgressUIUpdate:webView.estimatedProgress animated:YES];
    });
    self.pendingProgressUIBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)applyProgressUIUpdate:(double)progress animated:(BOOL)animated {
    [self cancelPendingProgressUIUpdate];
    self.lastProgressUIUpdateTime = [NSDate date].timeIntervalSince1970;
    self.lastProgressUIValue = progress;

    WKWebView *webView = self.webView;
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage || !webView) {
        [self.loadingProgressView resetHidden];
        return;
    }
    if (webView.isLoading || tab.isLoading || (progress > 0.0 && progress < 1.0)) {
        [self.loadingProgressView setProgress:progress animated:animated];
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
    if (self.autoScrollController.enabled) {
        self.autoScrollController.enabled = NO;
    }
    // 选中标签未变且正在 Element Fullscreen：只刷标签栏，避免整页 refresh 扰动全屏层。
    NSUUID *selectedID = self.tabController.selectedTab.tabID;
    WKWebView *selectedWebView = self.tabController.selectedTab.webView;
    BOOL selectionUnchanged = selectedID != nil
        && [selectedID isEqual:self.lastSelectedTabIDForAddressFocus];
    if (selectionUnchanged && [self webViewIsInElementFullscreen:selectedWebView]) {
        [self updateTabStripDisplay];
        [self pinWebViewLayoutInSuperview:selectedWebView];
        [self startFullscreenLayoutRepairIfNeededForWebView:selectedWebView];
        [self schedulePersistTabSession];
        return;
    }
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
    [self endAddressBarPeekResigning:YES];
}

- (void)autocompleteController:(BrowserAddressBarAutocompleteController *)controller openURLInNewTab:(NSURL *)url {
    (void)controller;
    [self launchpadView:self.launchpadView openURLInNewTab:url];
    [self endAddressBarPeekResigning:YES];
}

- (NSWindow *)windowForAutocompleteController:(BrowserAddressBarAutocompleteController *)controller {
    (void)controller;
    return self.window;
}

#pragma mark - BrowserLaunchpadViewDelegate

- (void)launchpadView:(BrowserLaunchpadView *)view openURL:(NSURL *)url {
    (void)view;
    if ([self openURLInExternalApplicationIfNeeded:url]) {
        return;
    }
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab) {
        [tab loadURL:url];
        [self refreshTabsUI];
    }
}

- (void)launchpadView:(BrowserLaunchpadView *)view openURLInNewTab:(NSURL *)url {
    (void)view;
    if ([self openURLInExternalApplicationIfNeeded:url]) {
        return;
    }
    [self.tabController addTabWithURL:url];
}

- (void)openURLsFromExternalSource:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }

    NSMutableArray<NSURL *> *accepted = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL isWebURL = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
        if (isWebURL) {
            [accepted addObject:url];
            continue;
        }
        NSURL *localFile = [BrowserLocalFileSupport normalizedPreviewableFileURL:url];
        if (localFile) {
            [accepted addObject:localFile];
        }
    }
    if (accepted.count == 0) {
        return;
    }
    [self openAcceptedURLsInBrowser:accepted];
}

- (void)openAcceptedURLsInBrowser:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }

    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];

    // 当前为新标签页且只打开一个文件时，直接落在当前标签。
    BrowserTab *selected = self.tabController.selectedTab;
    NSUInteger index = 0;
    if (urls.count == 1 && selected != nil && selected.isNewTabPage) {
        [selected loadURL:urls.firstObject];
        index = 1;
    }

    BOOL openedAny = (index > 0);
    for (; index < urls.count; index++) {
        [self.tabController addTabWithURL:urls[index]];
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
    BrowserTab *tab = self.tabController.selectedTab;
    [tab beginNavigationSessionWithURL:nil];
    [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    [self cancelPendingSSLAuthForWebView:self.webView];
    [self clearNavigationErrorForWebView:self.webView];
    BrowserTab *tab = self.tabController.selectedTab;
    [tab beginNavigationSessionWithURL:nil];
    [self.webView goForward];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab.pendingHardRecover) {
        [self reloadAfterHardRecoverForTab:tab];
        return;
    }
    if (tab.isHibernated) {
        [self refreshTabsUI];
        return;
    }
    WKWebView *webView = self.webView;
    if (webView && (webView.isLoading || tab.isLoading)) {
        [self stopLoadingInWebView:webView];
        return;
    }
    [self cancelPendingSSLAuthForWebView:webView];
    BrowserPendingNavigationError *pending =
        [self.pendingNavigationErrorByWebView objectForKey:webView];
    NSURL *reloadURL = pending.failingURL;
    [self clearNavigationErrorForWebView:webView];
    if (reloadURL) {
        [tab beginNavigationSessionWithURL:reloadURL];
        [webView loadRequest:[NSURLRequest requestWithURL:reloadURL]];
    } else {
        NSURL *current = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
        [tab beginNavigationSessionWithURL:current];
        [webView reload];
    }
}

- (void)hardReloadPage:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab.pendingHardRecover) {
        [self reloadAfterHardRecoverForTab:tab];
        return;
    }
    if (tab.isHibernated) {
        [self refreshTabsUI];
        return;
    }
    WKWebView *webView = self.webView;
    if (webView && (webView.isLoading || tab.isLoading)) {
        [self stopLoadingInWebView:webView];
        return;
    }
    [self cancelPendingSSLAuthForWebView:webView];
    BrowserPendingNavigationError *pending =
        [self.pendingNavigationErrorByWebView objectForKey:webView];
    NSURL *reloadURL = pending.failingURL;
    [self clearNavigationErrorForWebView:webView];
    if (reloadURL) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:reloadURL];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [tab beginNavigationSessionWithURL:reloadURL];
        [webView loadRequest:request];
        return;
    }
    NSURL *current = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    [tab beginNavigationSessionWithURL:current];
    if ([webView isKindOfClass:[BrowserWebView class]]) {
        [(BrowserWebView *)webView reloadFromOrigin];
    } else {
        [webView reloadFromOrigin];
    }
}

- (void)stopLoadingInWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    [self cancelHardRecoverWatchdogForWebView:webView];
    [self cancelReachabilityProbeForWebView:webView];
    [self.navigationWatchdog cancelAllForWebView:webView];
    [tab clearNavigationSession];
    [webView stopLoading];
    tab.isLoading = NO;
    [self updateTabStripDisplay];
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
        [self updateReloadStopButtonAppearance];
        [self updateNavigationState];
    }
}

- (void)reloadAfterHardRecoverForTab:(BrowserTab *)tab {
    if (!tab) {
        return;
    }
    NSURL *url = [BrowserWebView publicURLFromInternalURL:tab.restorableURL] ?: tab.restorableURL;
    tab.pendingHardRecover = NO;
    tab.hardRecoverMessage = nil;
    [self clearNavigationErrorForWebView:tab.webView];
    [self hideNavigationErrorOverlay];
    if (url) {
        [tab loadURL:url];
    }
    [self refreshTabsUI];
}

- (void)presentHardRecoverErrorForSelectedTabIfNeeded {
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab.pendingHardRecover || tab.webView == nil) {
        return;
    }
    NSURL *url = tab.restorableURL;
    NSString *message = tab.hardRecoverMessage.length > 0
        ? tab.hardRecoverMessage
        : @"页面无响应，已停止。可重新加载。";
    [self presentNavigationErrorForWebView:tab.webView
                                     title:@"页面无响应"
                                   message:message
                                failingURL:url
                          fromNegativeCache:NO];
}

- (void)forceStopSelectedTab:(id)sender {
    (void)sender;
    BrowserTab *tab = self.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        return;
    }
    NSURL *url = [tab currentOrRestorableURL];
    [self forceAbandonTab:tab
               failingURL:url
                  message:@"已强制停止此标签的页面进程。可重新加载。"];
}

- (void)forceAbandonTab:(BrowserTab *)tab
             failingURL:(NSURL *)failingURL
                message:(NSString *)message {
    if (!tab || tab.isNewTabPage) {
        return;
    }
    WKWebView *oldWebView = tab.webView;
    [self cancelHardRecoverWatchdogForWebView:oldWebView];
    [self cancelReachabilityProbeForWebView:oldWebView];
    [self.navigationWatchdog cancelAllForWebView:oldWebView];
    [self clearNavigationErrorForWebView:oldWebView];
    [self cancelPendingSSLAuthForWebView:oldWebView];

    tab.hardRecoverMessage = message.length > 0 ? message : @"页面无响应，已停止。可重新加载。";
    [BrowserTabLoadIsolator forceAbandonWebViewInTab:tab failingURL:failingURL];

    BrowserNavigationLog(@"force-abandon done tab=%@ selected=%d",
                         tab.tabID.UUIDString,
                         tab == self.tabController.selectedTab);

    if (tab == self.tabController.selectedTab) {
        [self refreshTabsUI];
        [self presentHardRecoverErrorForSelectedTabIfNeeded];
        [self updateNavigationState];
        [self updateTabStripDisplay];
    } else {
        [self updateTabStripDisplay];
    }
}

- (void)cancelHardRecoverWatchdogForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    [self.hardRecoverTokenByWebView removeObjectForKey:webView];
}

- (void)scheduleHardRecoverWatchdogForWebView:(WKWebView *)webView
                                          tab:(BrowserTab *)tab
                                          URL:(NSURL *)url {
    if (!webView || !tab) {
        return;
    }
    NSInteger token = ++self.hardRecoverTokenCounter;
    [self.hardRecoverTokenByWebView setObject:@(token) forKey:webView];
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    __weak BrowserTab *weakTab = tab;
    NSURL *failingURL = url;
    BrowserNavigationLog(@"schedule-T3 tab=%@ delay=%.0fs gen-check webView=%p",
                         tab.tabID.UUIDString,
                         BrowserStuckWebViewHardRecoverDelay,
                         webView);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(BrowserStuckWebViewHardRecoverDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        BrowserTab *strongTab = weakTab;
        if (!strongSelf || !strongWebView || !strongTab) {
            return;
        }
        NSNumber *current = [strongSelf.hardRecoverTokenByWebView objectForKey:strongWebView];
        if (!current || current.integerValue != token) {
            return;
        }
        [strongSelf.hardRecoverTokenByWebView removeObjectForKey:strongWebView];
        // 仍挂着同一 WebView 且 stopLoading 未真正结束 → 硬杀内容进程。
        if (strongTab.webView != strongWebView) {
            return;
        }
        if (strongTab.pendingHardRecover) {
            return;
        }
        if (!strongWebView.isLoading && !strongTab.isLoading) {
            BrowserNavigationLog(@"T3 skip (idle) tab=%@", strongTab.tabID.UUIDString);
            return;
        }
        BrowserNavigationLog(@"T3 fire tab=%@ stillLoading wv=%d tab=%d",
                             strongTab.tabID.UUIDString,
                             strongWebView.isLoading,
                             strongTab.isLoading);
        [strongSelf forceAbandonTab:strongTab
                         failingURL:failingURL
                            message:@"页面长时间无响应，已停止该标签的页面进程。可重新加载。"];
    });
}

- (BOOL)canReloadCurrentPage {
    BrowserTab *tab = self.tabController.selectedTab;
    return tab != nil && (tab.isHibernated || tab.pendingHardRecover || !tab.isNewTabPage);
}

- (BOOL)canOpenWebInspector {
    BrowserTab *tab = self.tabController.selectedTab;
    return tab != nil && !tab.isNewTabPage && !tab.isHibernated && self.webView != nil;
}

- (BOOL)canViewPageSource {
    return [self canOpenWebInspector];
}

- (void)viewPageSource:(id)sender {
    (void)sender;
    if (![self canViewPageSource]) {
        return;
    }

    WKWebView *webView = self.webView;
    BrowserTab *sourceTab = self.tabController.selectedTab;
    NSString *pageTitle = sourceTab.title ?: @"";
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:@"document.documentElement ? document.documentElement.outerHTML : ''"
              completionHandler:^(id result, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) {
            return;
        }
        NSString *outer = [result isKindOfClass:[NSString class]] ? (NSString *)result : nil;
        if (error != nil || outer.length == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"无法查看源代码";
            alert.informativeText = error.localizedDescription.length > 0
                ? error.localizedDescription
                : @"当前页面没有可读取的文档内容。";
            [alert addButtonWithTitle:@"好"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }

        BOOL truncated = NO;
        NSUInteger maxLen = [BrowserPageSource maxSourceLength];
        if (outer.length > maxLen) {
            outer = [outer substringToIndex:maxLen];
            truncated = YES;
        }

        NSString *tabTitle = [NSString stringWithFormat:@"源代码 — %@",
                              pageTitle.length > 0 ? pageTitle : @"页面"];
        NSString *html = [BrowserPageSource HTMLDocumentForSource:outer
                                                        pageTitle:pageTitle
                                                        truncated:truncated];
        [self.tabController addTabWithHTMLString:html title:tabTitle];
    }];
}

- (void)openWebInspector:(id)sender {
    (void)sender;
    if (![self canOpenWebInspector]) {
        return;
    }

    if (![BrowserWebInspector isInspectionSupported]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法打开 Web Inspector";
        alert.informativeText = @"需要 macOS 13.3 或更高版本。";
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    if (![BrowserDeveloperPreferences sharedPreferences].allowWebInspection) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"尚未允许网页检查";
        alert.informativeText = @"请先在设置中开启「允许网页检查」，再打开 Web Inspector。";
        [alert addButtonWithTitle:@"打开设置"];
        [alert addButtonWithTitle:@"取消"];
        [alert beginSheetModalForWindow:self.window
                      completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn) {
                return;
            }
            id delegate = NSApp.delegate;
            if ([delegate respondsToSelector:@selector(showBrowserSettings:)]) {
                [delegate showBrowserSettings:nil];
            }
        }];
        return;
    }

    if ([BrowserWebInspector showInspectorForWebView:self.webView]) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"无法直接打开检查器";
    alert.informativeText =
        @"已开启网页检查时，也可：\n"
        @"1. 在页面上右键 →「检查元素」\n"
        @"2. 或在 Safari → 开发 →（你的 Mac）→ MeoBrowser 中选择页面\n\n"
        @"若 Safari 没有「开发」菜单：Safari → 设置 → 高级 → 勾选「在菜单栏中显示开发菜单」。";
    [alert addButtonWithTitle:@"好"];
    [alert addButtonWithTitle:@"打开设置"];
    [alert beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn) {
            id <NSObject> delegate = NSApp.delegate;
            if ([delegate respondsToSelector:@selector(showBrowserSettings:)]) {
                [(id)delegate showBrowserSettings:nil];
            }
        }
    }];
}

#pragma mark - Reload shortcut (F5 / configurable)

- (void)installReloadKeyMonitor {
    if (self.reloadKeyMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.reloadKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                  handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handleReloadKeyEvent:event];
    }];
}

- (void)uninstallReloadKeyMonitor {
    if (self.reloadKeyMonitor) {
        [NSEvent removeMonitor:self.reloadKeyMonitor];
        self.reloadKeyMonitor = nil;
    }
}

- (NSEvent *)handleReloadKeyEvent:(NSEvent *)event {
    if (self.window != NSApp.keyWindow) {
        return event;
    }
    if (event.isARepeat) {
        return event;
    }
    // Esc：停止当前标签加载（即使尚未进入 provisional）。
    if (event.keyCode == 53) {
        BrowserTab *tab = self.tabController.selectedTab;
        WKWebView *webView = self.webView;
        if (webView && tab && !tab.isNewTabPage && (webView.isLoading || tab.isLoading)) {
            [self stopLoadingInWebView:webView];
            return nil;
        }
        return event;
    }
    if (![BrowserKeyboardPreferences eventMatchesReloadShortcut:event]) {
        return event;
    }
    if (![self canReloadCurrentPage]) {
        return nil;
    }
    [self reloadPage:nil];
    return nil;
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
    if (action == @selector(toggleCompactMode:)) {
        menuItem.state = self.compactModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(toggleAlwaysOnTop:)) {
        menuItem.state = self.alwaysOnTopEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(toggleTransparentMode:)) {
        if (self.window.styleMask & NSWindowStyleMaskFullScreen) {
            return NO;
        }
        menuItem.state = self.transparentModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(toggleAfkMode:)) {
        if (self.window.styleMask & NSWindowStyleMaskFullScreen) {
            return NO;
        }
        menuItem.state = self.afkModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(focusAddressBar:)) {
        return YES;
    }
    if (action == @selector(reloadPage:) || action == @selector(hardReloadPage:)) {
        return [self canReloadCurrentPage];
    }
    if (action == @selector(forceStopSelectedTab:)) {
        BrowserTab *tab = self.tabController.selectedTab;
        return tab != nil && !tab.isNewTabPage && tab.webView != nil && !tab.pendingHardRecover;
    }
    if (action == @selector(openWebInspector:) || action == @selector(viewPageSource:)) {
        return [self canOpenWebInspector];
    }
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
    if (action == @selector(toggleHistoryPanel:)) {
        return YES;
    }
    if (action == @selector(togglePagePackSidebar:)) {
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
    if ([self openURLInExternalApplicationIfNeeded:url]) {
        [self endAddressBarPeekResigning:YES];
        return;
    }

    BrowserTab *tab = self.tabController.selectedTab;
    if (tab) {
        [self cancelPendingSSLAuthForWebView:tab.webView];
        [self clearNavigationErrorForWebView:tab.webView];
        [tab loadURL:url];
        [self refreshTabsUI];
    }
    [self endAddressBarPeekResigning:YES];
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
        [self updateReloadStopButtonAppearance];
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
        [self reloadPagePackSidebarIfVisible];
        [self.captchaAssistController updateForURL:nil];
        [self.feedAssistController updateForURL:nil];
        return;
    }

    self.backButton.enabled = webView.canGoBack;
    self.forwardButton.enabled = webView.canGoForward;
    self.reloadButton.enabled = YES;
    [self updateReloadStopButtonAppearance];

    NSString *title = tab.displayTitle;
    [self setDisplayedWindowTitle:title];

    [self persistAddressBarDraftFromField];
    [self applyAddressBarStringForTab:tab];
    [self updateBookmarkButtonState];
    [self updateConnectionSecurityStateForTab:tab webView:webView];
    [self updateSecurityBadgeVisibility];
    [self.loginAssistController updateForURL:webView.URL];
    [self reloadAssistSidebarIfVisible];
    [self reloadPagePackSidebarIfVisible];
    [self.captchaAssistController updateForURL:webView.URL];
    [self.feedAssistController updateForURL:webView.URL];
}

- (void)updateReloadStopButtonAppearance {
    BrowserTab *tab = self.tabController.selectedTab;
    WKWebView *webView = self.webView;
    BrowserNavigationSession *session = tab.navigationSession;
    BOOL sessionActive = session != nil
        && session.phase != BrowserNavigationSessionPhaseIdle;
    BOOL loading = webView != nil && tab != nil && !tab.isNewTabPage
        && (tab.isLoading || (sessionActive && webView.isLoading));
    NSString *symbolName = loading ? @"xmark" : @"arrow.clockwise";
    NSImage *image = [self toolbarSymbolImageNamed:symbolName];
    if (image) {
        self.reloadButton.image = image;
    }
    self.reloadButton.toolTip = loading ? @"停止" : @"刷新";
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
        if (self.addressBarPeekActive) {
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.addressBarPeekActive || strongSelf.addressFieldIsEditing) {
                    return;
                }
                if ([strongSelf.addressAutocompleteController isPanelVisible]) {
                    return;
                }
                NSResponder *first = strongSelf.window.firstResponder;
                NSText *editor = strongSelf.addressField.currentEditor;
                if (first == strongSelf.addressField || first == editor) {
                    return;
                }
                [strongSelf endAddressBarPeekResigning:NO];
            });
        }
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
        if (commandSelector == @selector(cancelOperation:)) {
            if (self.addressBarPeekActive) {
                [self endAddressBarPeekResigning:YES];
                return YES;
            }
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
    NSString *reloadTitle = pending.fromNegativeCache ? @"仍要访问" : @"重新加载";
    [self.navigationErrorView configureWithTitle:pending.title
                                         message:pending.message
                                      showGoBack:pending.canGoBack
                               reloadButtonTitle:reloadTitle];
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
    [self presentNavigationErrorForWebView:webView
                                     title:title
                                   message:message
                                failingURL:failingURL
                          fromNegativeCache:NO];
}

- (void)presentNavigationErrorForWebView:(WKWebView *)webView
                                   title:(NSString *)title
                                 message:(NSString *)message
                              failingURL:(NSURL *)failingURL
                        fromNegativeCache:(BOOL)fromNegativeCache {
    if (!webView) {
        return;
    }
    BrowserPendingNavigationError *pending = [[BrowserPendingNavigationError alloc] init];
    pending.webView = webView;
    pending.title = title.length > 0 ? title : @"无法加载页面";
    pending.message = message.length > 0 ? message : @"发生未知错误。";
    pending.failingURL = failingURL;
    pending.canGoBack = webView.canGoBack;
    pending.fromNegativeCache = fromNegativeCache;
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

- (void)cancelNavigationWatchdogForWebView:(WKWebView *)webView {
    [self cancelReachabilityProbeForWebView:webView];
    [self.navigationWatchdog cancelAllForWebView:webView];
}

- (void)cancelReachabilityProbeForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserReachabilityProbeHandle *handle = [self.reachabilityProbeByWebView objectForKey:webView];
    if (handle) {
        [handle cancel];
        [self.reachabilityProbeByWebView removeObjectForKey:webView];
    }
}

- (void)startReachabilityProbeForWebView:(WKWebView *)webView
                                     tab:(BrowserTab *)tab
                                 session:(BrowserNavigationSession *)session
                                     URL:(NSURL *)url {
    [self cancelReachabilityProbeForWebView:webView];
    if (!webView || !tab || !session || !url) {
        return;
    }
    if (![BrowserReachabilityProbe shouldProbeURL:url]) {
        return;
    }

    NSString *hostKey = [BrowserHostNegativeCache hostKeyForURL:url];
    NSNumber *cachedCode = hostKey.length > 0
        ? [[BrowserHostNegativeCache sharedCache] failureCodeForHostKey:hostKey]
        : nil;
    if (cachedCode != nil) {
        NSInteger generation = session.generation;
        __weak typeof(self) weakSelf = self;
        __weak WKWebView *weakWebView = webView;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            WKWebView *strongWebView = weakWebView;
            if (!strongSelf || !strongWebView) {
                return;
            }
            BrowserTab *current = [strongSelf.tabController tabForWebView:strongWebView];
            if (!current || current.navigationSession.generation != generation) {
                return;
            }
            if (current.navigationSession.phase == BrowserNavigationSessionPhaseCommitted) {
                return;
            }
            [strongSelf applyReachabilityProbeFailureForWebView:strongWebView
                                                            tab:current
                                                            URL:url
                                                      errorCode:cachedCode.integerValue
                                               fromNegativeCache:YES];
        });
        return;
    }

    NSInteger generation = session.generation;
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    BrowserReachabilityProbeHandle *handle =
        [[BrowserReachabilityProbe sharedProbe] probeURL:url
                                              completion:^(BrowserReachabilityProbeResult result,
                                                           NSInteger suggestedURLErrorCode) {
        typeof(self) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView) {
            return;
        }
        [strongSelf.reachabilityProbeByWebView removeObjectForKey:strongWebView];
        BrowserTab *current = [strongSelf.tabController tabForWebView:strongWebView];
        if (!current || current.navigationSession.generation != generation) {
            return;
        }
        if (current.navigationSession.phase == BrowserNavigationSessionPhaseCommitted
            || current.navigationSession.phase == BrowserNavigationSessionPhaseIdle) {
            return;
        }
        if (result == BrowserReachabilityProbeResultReachable
            || result == BrowserReachabilityProbeResultUnknown) {
            BrowserNavigationLog(@"probe tab=%@ result=%ld (no-op)",
                                 current.tabID.UUIDString,
                                 (long)result);
            return;
        }
        BrowserNavigationLog(@"probe fail-fast tab=%@ result=%ld code=%ld",
                             current.tabID.UUIDString,
                             (long)result,
                             (long)suggestedURLErrorCode);
        NSInteger code = suggestedURLErrorCode;
        if (code == 0) {
            code = (result == BrowserReachabilityProbeResultDNSFailed)
                ? NSURLErrorDNSLookupFailed
                : NSURLErrorCannotConnectToHost;
        }
        if (hostKey.length > 0) {
            [[BrowserHostNegativeCache sharedCache] recordFailureCode:code forHostKey:hostKey];
        }
        [strongSelf applyReachabilityProbeFailureForWebView:strongWebView
                                                        tab:current
                                                        URL:url
                                                  errorCode:code
                                           fromNegativeCache:NO];
    }];
    if (handle) {
        [self.reachabilityProbeByWebView setObject:handle forKey:webView];
    }
}

- (void)applyReachabilityProbeFailureForWebView:(WKWebView *)webView
                                            tab:(BrowserTab *)tab
                                            URL:(NSURL *)url
                                      errorCode:(NSInteger)errorCode
                               fromNegativeCache:(BOOL)fromNegativeCache {
    if (!webView || !tab) {
        return;
    }
    [self cancelReachabilityProbeForWebView:webView];
    [self.navigationWatchdog cancelAllForWebView:webView];
    [webView stopLoading];
    tab.isLoading = NO;
    [tab clearNavigationSession];
    [self updateTabStripDisplay];
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
        [self updateReloadStopButtonAppearance];
    }
    NSURL *failingURL = url ?: [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    [self presentNavigationErrorForWebView:webView
                                     title:@"无法加载页面"
                                   message:[self userFacingMessageForNavigationErrorCode:errorCode
                                                                   fallbackDescription:nil]
                                failingURL:failingURL
                          fromNegativeCache:fromNegativeCache];
    if (webView == self.webView) {
        [self updateNavigationState];
    }
}

- (void)cancelPreCommitNavigationWatchdogForWebView:(WKWebView *)webView {
    [self cancelReachabilityProbeForWebView:webView];
    [self.navigationWatchdog cancelOverallForWebView:webView];
    [self.navigationWatchdog cancelProvisionalForWebView:webView];
}

- (void)startOverallNavigationWatchdogForWebView:(WKWebView *)webView
                                         session:(BrowserNavigationSession *)session
                                             URL:(NSURL *)url {
    if (!webView || !session) {
        return;
    }
    // 新导航开始：清掉上一轮残留的 T2，避免跨代际误触发。
    [self.navigationWatchdog cancelDocumentLoadGraceForWebView:webView];
    __weak typeof(self) weakSelf = self;
    [self.navigationWatchdog startOverallTimeoutForWebView:webView
                                                   session:session
                                                       URL:url
                                                   handler:^(WKWebView *timedWebView,
                                                             BrowserNavigationSession *timedSession,
                                                             NSURL *failingURL) {
        [weakSelf fireNavigationTimeoutForWebView:timedWebView
                                          session:timedSession
                                              URL:failingURL];
    }];
}

- (void)startProvisionalNavigationWatchdogForWebView:(WKWebView *)webView
                                             session:(BrowserNavigationSession *)session
                                                 URL:(NSURL *)url {
    if (!webView || !session) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.navigationWatchdog startProvisionalTimeoutForWebView:webView
                                                       session:session
                                                           URL:url
                                                       handler:^(WKWebView *timedWebView,
                                                                 BrowserNavigationSession *timedSession,
                                                                 NSURL *failingURL) {
        [weakSelf fireNavigationTimeoutForWebView:timedWebView
                                          session:timedSession
                                              URL:failingURL];
    }];
}

- (void)startDocumentLoadGraceWatchdogForWebView:(WKWebView *)webView
                                         session:(BrowserNavigationSession *)session
                                             URL:(NSURL *)url {
    if (!webView || !session) {
        return;
    }
    BOOL shortGrace = session.usesShortDocumentLoadGrace
        || [BrowserWebView URLContainsHashRestoreQuery:webView.URL]
        || [BrowserWebView URLContainsHashRestoreQuery:url];
    NSTimeInterval interval = shortGrace
        ? BrowserDocumentLoadGraceTimeoutShort
        : BrowserDocumentLoadGraceTimeout;
    __weak typeof(self) weakSelf = self;
    [self.navigationWatchdog startDocumentLoadGraceForWebView:webView
                                                      session:session
                                                          URL:url
                                                     interval:interval
                                                      handler:^(WKWebView *timedWebView,
                                                                BrowserNavigationSession *timedSession,
                                                                NSURL *failingURL) {
        (void)failingURL;
        [weakSelf fireDocumentLoadGraceForWebView:timedWebView session:timedSession];
    }];
}

- (void)fireDocumentLoadGraceForWebView:(WKWebView *)webView
                                session:(BrowserNavigationSession *)session {
    if (!webView || !session) {
        return;
    }
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab || tab.navigationSession.generation != session.generation) {
        return;
    }
    // 已结束加载则无需 stop。
    if (!tab.isLoading && !webView.isLoading) {
        [self.navigationWatchdog cancelDocumentLoadGraceForWebView:webView];
        [tab clearNavigationSession];
        if (webView == self.webView) {
            [self updateReloadStopButtonAppearance];
        }
        return;
    }

    [self.navigationWatchdog cancelDocumentLoadGraceForWebView:webView];
    // 截断子资源等待；保留已渲染文档，不展示错误页。
    [webView stopLoading];
    tab.isLoading = NO;
    [tab clearNavigationSession];
    [self updateTabStripDisplay];
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
        [self updateReloadStopButtonAppearance];
        [self updateNavigationState];
    }
}

- (void)fireNavigationTimeoutForWebView:(WKWebView *)webView
                                session:(BrowserNavigationSession *)session
                                    URL:(NSURL *)failingURL {
    if (!webView || !session) {
        return;
    }
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab || tab.navigationSession.generation != session.generation) {
        return;
    }

    BrowserNavigationLog(@"T0/T1 timeout tab=%@ gen=%ld phase=%ld url=%@",
                         tab.tabID.UUIDString,
                         (long)session.generation,
                         (long)session.phase,
                         (failingURL ?: session.URL).absoluteString ?: @"");

    [self.navigationWatchdog cancelAllForWebView:webView];
    [self cancelReachabilityProbeForWebView:webView];

    // stopLoading 会触发 Cancelled 失败回调（被忽略）；此处直接展示超时错误页。
    [webView stopLoading];

    tab.isLoading = NO;
    [tab clearNavigationSession];
    [self updateTabStripDisplay];
    if (webView == self.webView) {
        [self.loadingProgressView resetHidden];
        [self updateReloadStopButtonAppearance];
    }
    NSURL *errorURL = failingURL ?: session.URL ?: [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    [self presentNavigationErrorForWebView:webView
                                     title:@"无法加载页面"
                                   message:[self userFacingMessageForNavigationErrorCode:NSURLErrorTimedOut
                                                                   fallbackDescription:nil]
                                failingURL:errorURL];
    if (webView == self.webView) {
        [self updateNavigationState];
    }
    // stopLoading 若未真正结束 isLoading，武装 T3 硬恢复。
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    __weak BrowserTab *weakTab = tab;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        BrowserTab *strongTab = weakTab;
        if (!strongSelf || !strongWebView || !strongTab) {
            return;
        }
        if (strongTab.webView != strongWebView || strongTab.pendingHardRecover) {
            return;
        }
        if (strongWebView.isLoading || strongTab.isLoading) {
            BrowserNavigationLog(@"stopLoading ineffective → arm T3 tab=%@", strongTab.tabID.UUIDString);
            [strongSelf scheduleHardRecoverWatchdogForWebView:strongWebView
                                                          tab:strongTab
                                                          URL:errorURL];
        }
    });
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
        [strongSelf focusAddressBar:nil];
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
    BrowserTab *tab = self.tabController.selectedTab;
    if (tab.pendingHardRecover) {
        [self reloadAfterHardRecoverForTab:tab];
        return;
    }
    WKWebView *webView = self.webView;
    BrowserPendingNavigationError *pending =
        webView ? [self.pendingNavigationErrorByWebView objectForKey:webView] : nil;
    NSURL *reloadURL = pending.failingURL;
    BOOL clearNegative = pending.fromNegativeCache || reloadURL != nil;
    NSString *hostKey = clearNegative ? [BrowserHostNegativeCache hostKeyForURL:reloadURL] : nil;
    if (hostKey.length > 0) {
        [[BrowserHostNegativeCache sharedCache] clearHostKey:hostKey];
    }
    [self clearNavigationErrorForWebView:webView];
    if (reloadURL) {
        [tab beginNavigationSessionWithURL:reloadURL];
        [webView loadRequest:[NSURLRequest requestWithURL:reloadURL]];
    } else {
        NSURL *current = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
        [tab beginNavigationSessionWithURL:current];
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
    NSURL *requestURL = [BrowserWebView URLByNormalizingEmbeddedFragment:navigationAction.request.URL];
    BOOL isMainFrame = navigationAction.targetFrame.isMainFrame
        || (navigationAction.targetFrame == nil && navigationAction.sourceFrame == nil);

    // 自定义应用协议（OAuth / 浏览器登录回调等）：取消 WebView 加载，改交 Launch Services。
    if ([BrowserWindowController shouldHandOffURLToExternalApplication:requestURL]) {
        BOOL shouldOpenExternally = isMainFrame
            || navigationAction.targetFrame == nil
            || navigationAction.navigationType == WKNavigationTypeLinkActivated;
        decisionHandler(WKNavigationActionPolicyCancel);
        if (shouldOpenExternally) {
            [self openURLInExternalApplication:requestURL];
        }
        return;
    }

    // Safari 对齐：`<a download>` / blob 附件走 WK 原生下载，而不是整页打开或视频专用 JS。
    if (@available(macOS 11.3, *)) {
        if ([BrowserDownloadManager shouldDownloadNavigationAction:navigationAction]) {
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
    }

    // blob: 点击下载 / 主框架导航：勿整页打开（会失败并显示 Plug-in handled load），改走下载。
    if ([requestURL.scheme.lowercaseString isEqualToString:@"blob"]) {
        BOOL treatAsDownload = isMainFrame
            || navigationAction.targetFrame == nil
            || navigationAction.navigationType == WKNavigationTypeLinkActivated;
        if (treatAsDownload) {
            NSString *downloadName = nil;
            if (@available(macOS 11.3, *)) {
                downloadName = [BrowserDownloadManager downloadAttributeFromNavigationAction:navigationAction];
            }
            decisionHandler(WKNavigationActionPolicyCancel);
            [self beginBlobDownloadFromURL:requestURL suggestedFilename:downloadName inWebView:webView];
            return;
        }
    }

    // ⌘+点击链接：在新标签页中打开，取消当前页导航（避免与 createWebView 重复开页）
    // blob: 已在上方统一改走下载，此处不必再分支。
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
        NSURL *trackedURL = [BrowserWebView publicURLFromInternalURL:requestURL] ?: requestURL;
        if (trackedURL) {
            [self.pendingProvisionalURLByWebView setObject:trackedURL forKey:webView];
        }
        // 链接点击等 WebKit 自发导航：若尚无活跃会话，立刻挂上 T0（覆盖无 provisional 空等）。
        BrowserNavigationSession *session = tab.navigationSession;
        BOOL active = session != nil
            && (session.phase == BrowserNavigationSessionPhaseLoading
                || session.phase == BrowserNavigationSessionPhaseProvisional);
        if (!active) {
            [tab beginNavigationSessionWithURL:trackedURL];
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
    if (@available(macOS 11.3, *)) {
        NSString *name = [BrowserDownloadManager downloadAttributeFromNavigationAction:navigationAction];
        [self.downloadManager takeOwnershipOfDownload:download suggestedFilename:name];
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
        [self updateReloadStopButtonAppearance];
    }
    NSURL *provisionalURL = [self.pendingProvisionalURLByWebView objectForKey:webView];
    [self.pendingProvisionalURLByWebView removeObjectForKey:webView];
    if (!provisionalURL) {
        provisionalURL = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    }

    BrowserNavigationSession *session = tab.navigationSession;
    if (!session
        || session.phase == BrowserNavigationSessionPhaseCommitted
        || session.phase == BrowserNavigationSessionPhaseIdle) {
        session = [tab beginNavigationSessionWithURL:provisionalURL];
    }
    [tab markNavigationSessionProvisional];
    [self startProvisionalNavigationWatchdogForWebView:webView
                                               session:tab.navigationSession ?: session
                                                   URL:provisionalURL];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (![tab isMainFrameNavigation:navigation]) {
        return;
    }
    if (webView == self.webView && self.autoScrollController.enabled) {
        self.autoScrollController.enabled = NO;
    }
    [self cancelPreCommitNavigationWatchdogForWebView:webView];
    [tab markNavigationSessionCommitted];

    BrowserNavigationSession *session = tab.navigationSession;
    if (session) {
        if ([BrowserWebView URLContainsHashRestoreQuery:webView.URL]) {
            session.usesShortDocumentLoadGrace = YES;
        }
        NSURL *graceURL = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL ?: session.URL;
        [self startDocumentLoadGraceWatchdogForWebView:webView session:session URL:graceURL];
    }
    if (webView == self.webView) {
        [self updateReloadStopButtonAppearance];
    }

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
    NSURL *commitURL = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    [self.pageTranslationController webViewDidCommitNavigation:webView URL:commitURL];
    [[PagePackInjector sharedInjector] injectMatchingPacksIntoWebView:webView
                                                                   URL:commitURL
                                                                 phase:PagePackInjectionPhaseDocumentStart];

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
    [self cancelNavigationWatchdogForWebView:webView];
    [tab clearNavigationSession];
    [tab endMainFrameNavigation:navigation];
    [self syncFromWebView:webView];
    [self.feedAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
    NSURL *finishURL = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    [[PagePackInjector sharedInjector] injectMatchingPacksIntoWebView:webView
                                                                   URL:finishURL
                                                                 phase:PagePackInjectionPhaseDocumentEnd];
    if (webView == self.webView) {
        [self.loginAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
        [self.captchaAssistController noteNavigationFinishedInWebView:webView URL:webView.URL];
        [self.findBarController noteNavigationFinishedInWebView:webView];
        [self.tabOverviewController updateThumbnailForSelectedTabIfVisible];
        [self updateReloadStopButtonAppearance];
        [self reloadPagePackSidebarIfVisible];
        if (self.transparentModeEnabled) {
            [self.transparentModeController applyTransparentPageStyleToWebView:webView];
        }
    }
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self cancelNavigationWatchdogForWebView:webView];
    [tab clearNavigationSession];
    [self handleNavigationError:error forWebView:webView];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if ([tab isMainFrameNavigation:navigation]) {
        [tab endMainFrameNavigation:navigation];
    }
    [self cancelNavigationWatchdogForWebView:webView];
    [tab clearNavigationSession];
    [self handleNavigationError:error forWebView:webView];
}

- (void)syncFromWebView:(WKWebView *)webView {
    BrowserTab *tab = [self.tabController tabForWebView:webView];
    if (!tab) {
        return;
    }

    [self.navigationWatchdog cancelDocumentLoadGraceForWebView:webView];
    [tab clearNavigationSession];
    tab.isLoading = NO;
    tab.addressBarDraft = nil;

    if (webView == self.webView) {
        [self.loadingProgressView completeIfVisible];
        [self applyAddressBarStringForTab:tab];
        self.backButton.enabled = tab.isNewTabPage ? NO : webView.canGoBack;
        self.forwardButton.enabled = tab.isNewTabPage ? NO : webView.canGoForward;
        self.reloadButton.enabled = !tab.isNewTabPage;
        [self updateReloadStopButtonAppearance];
        [self updateBookmarkButtonState];
        [self updateConnectionSecurityStateForTab:tab webView:webView];
        [self updateSecurityBadgeVisibility];
    }

    [self recordHistoryForWebView:webView tab:tab];

    if (!tab.isNewTabPage) {
        NSURL *pageURL = [tab currentOrRestorableURL];
        NSString *pageURLString = pageURL.absoluteString;
        if (pageURLString.length > 0) {
            [[BrowserFaviconService sharedService] fetchAndCacheForPageURLString:pageURLString
                                                                 preferredIconURL:nil
                                                                           reason:BrowserFaviconFetchReasonSilent
                                                                       completion:nil];
        }
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

- (void)recordHistoryForWebView:(WKWebView *)webView tab:(BrowserTab *)tab {
    if (!tab || tab.isNewTabPage || !webView) {
        return;
    }
    if (!self.navigationErrorView.hidden || !self.certificateWarningView.hidden) {
        return;
    }
    NSURL *url = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
    if (![BrowsingPreferences isPersistableURL:url]) {
        url = [BrowserWebView publicURLFromInternalURL:tab.restorableURL] ?: tab.restorableURL;
    }
    if (![BrowsingPreferences isPersistableURL:url]) {
        return;
    }
    NSString *title = webView.title.length > 0 ? webView.title : tab.title;
    [[BrowserHistoryStore sharedStore] recordURL:url title:title];
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

    if (titleChanged) {
        NSURL *url = [BrowserWebView publicURLFromInternalURL:webView.URL] ?: webView.URL;
        if (![BrowsingPreferences isPersistableURL:url]) {
            url = [BrowserWebView publicURLFromInternalURL:tab.restorableURL] ?: tab.restorableURL;
        }
        if ([BrowsingPreferences isPersistableURL:url] && tab.title.length > 0) {
            [[BrowserHistoryStore sharedStore] updateTitle:tab.title forURL:url];
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
    // 用户取消、策略改为下载、或 blob 的 Plug-in handled load(204)：不应弹错误页。
    // blob 下载已在 decidePolicy 拦截，此处勿再 beginBlobDownload，以免重复任务。
    if ([self shouldIgnoreNavigationError:error]) {
        BrowserTab *tab = [self.tabController tabForWebView:webView];
        tab.isLoading = NO;
        if (webView == self.webView) {
            if (webView.isLoading) {
                [self.loadingProgressView setProgress:webView.estimatedProgress animated:YES];
            } else {
                [self.loadingProgressView resetHidden];
            }
            [self updateReloadStopButtonAppearance];
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
            [self updateReloadStopButtonAppearance];
            [self updateNavigationState];
        }
        return;
    }

    NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
    if ([self isCertificateRelatedError:error]) {
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
    // WebKitErrorPlugInWillHandleLoad == 204（媒体/blob 被插件接管时的假失败）
    if ([error.domain isEqualToString:@"WebKitErrorDomain"]
        && (error.code == 102 || error.code == 204)) {
        return YES;
    }
    NSString *description = error.localizedDescription.lowercaseString;
    if ([description containsString:@"frame load interrupted"]
        || [description containsString:@"plug-in handled load"]
        || [description containsString:@"plugin handled load"]) {
        return YES;
    }
    return NO;
}

- (void)beginBlobDownloadFromURL:(NSURL *)url inWebView:(WKWebView *)webView {
    [self beginBlobDownloadFromURL:url suggestedFilename:nil inWebView:webView];
}

- (void)beginBlobDownloadFromURL:(NSURL *)url
              suggestedFilename:(NSString *)suggestedFilename
                       inWebView:(WKWebView *)webView {
    if (!url || !webView) {
        return;
    }
    [self.downloadManager startDownloadWithURL:url suggestedFilename:suggestedFilename fromWebView:webView];
    if (!self.downloadPanelVisible) {
        [self showDownloadsPanel];
    }
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
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
            if ([self openURLInExternalApplicationIfNeeded:newWindowURL]) {
                return nil;
            }
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
        NSString *downloadName = nil;
        BOOL performDownload = NO;
        if (@available(macOS 11.3, *)) {
            downloadName = [BrowserDownloadManager downloadAttributeFromNavigationAction:navigationAction];
            performDownload = navigationAction.shouldPerformDownload;
        }
        if (performDownload || [url.scheme.lowercaseString isEqualToString:@"blob"]) {
            [self beginBlobDownloadFromURL:url suggestedFilename:downloadName inWebView:webView];
            return nil;
        }
        if ([self openURLInExternalApplicationIfNeeded:url]) {
            return nil;
        }

        // 必须用 WebKit 传入的 configuration 创建并 return，才能保留 window.opener / postMessage
        //（Google GIS popup、gsi/transform 等依赖 related browsing context）。
        // 切勿 addTabWithURL + return nil：JS 会视 window.open 被拦截并常再开第二窗。
        MeoDisableProcessSwapOnNavigationIfAvailable(configuration.preferences);
        BrowserWebView *popupWebView = [[BrowserWebView alloc] initWithFrame:NSZeroRect
                                                              configuration:configuration];
        popupWebView.customUserAgent = [BrowserUserAgent safariAlignedUserAgent];
        [BrowserWebInspector applyInspectableToWebView:popupWebView];
        [self.tabController addRelatedPopupTabWithWebView:popupWebView initialURL:url];
        return popupWebView;
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

- (void)handleGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
                             decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler {
    NSString *host = origin.host.length > 0 ? origin.host : @"";
    [BrowserGeolocationBridge handleWebKitPermissionRequestForHost:host
                                                        hostWindow:self.window
                                                   decisionHandler:decisionHandler];
}

// WebKit SPI（macOS 10.13.4+）：部分版本仍走 frame 回调。
- (void)_webView:(WKWebView *)webView
    requestGeolocationPermissionForFrame:(WKFrameInfo *)frame
                         decisionHandler:(void (^)(BOOL allowed))decisionHandler
    API_AVAILABLE(macos(10.13.4)) {
    (void)webView;
    NSString *host = frame.request.URL.host ?: @"";
    [BrowserGeolocationBridge handleWebKitPermissionRequestForHost:host
                                                        hostWindow:self.window
                                                   decisionHandler:^(WKPermissionDecision decision) {
        decisionHandler(decision == WKPermissionDecisionGrant);
    }];
}

// WebKit SPI（macOS 12+）；公开 API 需 macOS 27+。
- (void)_webView:(WKWebView *)webView
    requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
                         initiatedByFrame:(WKFrameInfo *)frame
                          decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler
    API_AVAILABLE(macos(12.0)) {
    (void)webView;
    (void)frame;
    [self handleGeolocationPermissionForOrigin:origin decisionHandler:decisionHandler];
}

- (void)webView:(WKWebView *)webView
requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
                     initiatedByFrame:(WKFrameInfo *)frame
                      decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler
    API_AVAILABLE(macos(27.0)) {
    (void)webView;
    (void)frame;
    [self handleGeolocationPermissionForOrigin:origin decisionHandler:decisionHandler];
}

@end
