#import "BrowserSettingsWindowController.h"
#import "BrowsingPreferences.h"
#import "BrowserKeyboardPreferences.h"
#import "BrowserUserAgent.h"
#import "BrowserLocationPreferences.h"
#import "BrowserLocationService.h"
#import "BrowserDeveloperPreferences.h"
#import "BrowserWebInspector.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "ServerSyncSettings.h"
#import "ServerSyncEngine.h"
#import "ServerSyncAuth.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import "BrowserHistoryStore.h"
#import <WebKit/WebKit.h>

@interface BrowserSettingsWindowController () <NSTabViewDelegate>
@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic, strong) NSPopUpButton *searchEnginePopUp;
@property (nonatomic, strong) NSTextField *defaultBrowserStatusLabel;
@property (nonatomic, strong) NSButton *setDefaultBrowserButton;
@property (nonatomic, strong) NSButton *clearWebsiteDataButton;
@property (nonatomic, strong) NSButton *clearHistoryButton;
@property (nonatomic, strong) NSButton *clearHistoryOnQuitCheckbox;
@property (nonatomic, strong) NSButton *userAgentCopyButton;
@property (nonatomic, strong) NSTextField *clearWebsiteDataStatusLabel;
@property (nonatomic, strong) NSTextField *privacyHintLabel;
@property (nonatomic, strong) NSButton *geolocationEnabledCheckbox;
@property (nonatomic, strong) NSTextField *locationHintLabel;
@property (nonatomic, strong) NSButton *openSystemLocationSettingsButton;

@property (nonatomic, strong) NSButton *allowWebInspectionCheckbox;
@property (nonatomic, strong) NSTextField *developerHintLabel;

@property (nonatomic, strong) NSButton *reloadShortcutEnabledCheckbox;
@property (nonatomic, strong) NSButton *reloadShortcutButton;
@property (nonatomic, strong) NSButton *reloadShortcutResetButton;
@property (nonatomic, strong) NSTextField *keyboardHintLabel;
@property (nonatomic, assign) BOOL recordingReloadShortcut;
@property (nonatomic, strong, nullable) id reloadShortcutRecordMonitor;

@property (nonatomic, strong) SBTextField *serverURLField;
@property (nonatomic, strong) SBTextField *serverEmailField;
@property (nonatomic, strong) SBSecureTextField *serverPasswordField;
@property (nonatomic, strong) NSBox *serverLoginBadge;
@property (nonatomic, strong) NSTextField *serverLoginBadgeLabel;
@property (nonatomic, strong) NSTextField *serverStatusLabel;
@property (nonatomic, strong) NSButton *serverRegisterButton;
@property (nonatomic, strong) NSButton *serverLoginButton;
@property (nonatomic, strong) NSButton *serverLogoutButton;
@property (nonatomic, strong) NSButton *serverEnabledCheckbox;
@property (nonatomic, strong) NSButton *serverShortcutCheckbox;
@property (nonatomic, strong) NSButton *serverFormMemoCheckbox;
@property (nonatomic, strong) NSTextField *serverLastSyncLabel;
@property (nonatomic, strong) NSButton *serverSyncNowButton;
@property (nonatomic, strong) NSTextField *serverHintLabel;
@end

@implementation BrowserSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 520)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"设置";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(serverSyncUINeedsRefresh:)
                                                     name:ServerSyncSettingsDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(serverSyncUINeedsRefresh:)
                                                     name:ServerSyncEngineStateDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardPreferencesDidChange:)
                                                     name:BrowserKeyboardPreferencesDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(locationPreferencesDidChange:)
                                                     name:BrowserLocationPreferencesDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(developerPreferencesDidChange:)
                                                     name:BrowserDeveloperPreferencesDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self stopRecordingReloadShortcut];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *)makeCaption:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:13];
    return label;
}

- (NSTextField *)makeHint:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.preferredMaxLayoutWidth = 460;
    return label;
}

- (NSStackView *)makeVerticalStackWithViews:(NSArray<NSView *> *)views {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

- (void)addTabNamed:(NSString *)title
              views:(NSArray<NSView *> *)views
          toTabView:(NSTabView *)tabView
       widthViews:(NSArray<NSView *> *)widthViews {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:title];
    item.label = title;
    NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = [self makeVerticalStackWithViews:views];
    [content addSubview:stack];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor],
    ]];
    for (NSView *view in widthViews) {
        [constraints addObject:[view.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    item.view = content;
    [tabView addTabViewItem:item];
}

- (void)buildUI {
    // —— 常规 ——
    NSTextField *searchCaption = [self makeCaption:@"默认搜索引擎"];
    self.searchEnginePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.searchEnginePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchEnginePopUp.target = self;
    self.searchEnginePopUp.action = @selector(searchEngineChanged:);
    for (NSDictionary *engine in [BrowsingPreferences availableSearchEngines]) {
        [self.searchEnginePopUp addItemWithTitle:engine[@"name"]];
        self.searchEnginePopUp.lastItem.representedObject = engine[@"id"];
    }
    [self selectCurrentSearchEngineInPopUp];
    NSGridView *searchGrid = [NSGridView gridViewWithViews:@[@[searchCaption, self.searchEnginePopUp]]];
    searchGrid.columnSpacing = 12;
    [searchGrid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSTextField *searchHint = [self makeHint:@"在地址栏输入非网址内容时将使用所选搜索引擎。"];

    NSTextField *browserCaption = [self makeCaption:@"默认浏览器"];
    self.defaultBrowserStatusLabel = [NSTextField labelWithString:@""];
    self.defaultBrowserStatusLabel.font = [NSFont systemFontOfSize:12];
    self.defaultBrowserStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.setDefaultBrowserButton = [NSButton buttonWithTitle:@"设为默认浏览器" target:self action:@selector(setDefaultBrowserClicked:)];
    self.setDefaultBrowserButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *browserRow = [NSStackView stackViewWithViews:@[self.defaultBrowserStatusLabel, self.setDefaultBrowserButton]];
    browserRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    browserRow.spacing = 12;
    NSTextField *browserHint = [self makeHint:@"设为默认后，系统中打开的 http/https 链接将由 MeoBrowser 处理。"];

    // —— 云同步 ——
    self.serverLoginBadge = [[NSBox alloc] initWithFrame:NSZeroRect];
    self.serverLoginBadge.boxType = NSBoxCustom;
    self.serverLoginBadge.borderWidth = 1;
    self.serverLoginBadge.cornerRadius = 8;
    self.serverLoginBadge.titlePosition = NSNoTitle;
    self.serverLoginBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.serverLoginBadgeLabel = [NSTextField labelWithString:@""];
    self.serverLoginBadgeLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.serverLoginBadgeLabel.alignment = NSTextAlignmentCenter;
    self.serverLoginBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverLoginBadge.contentView addSubview:self.serverLoginBadgeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.serverLoginBadge.heightAnchor constraintEqualToConstant:36],
        [self.serverLoginBadgeLabel.centerYAnchor constraintEqualToAnchor:self.serverLoginBadge.contentView.centerYAnchor],
        [self.serverLoginBadgeLabel.leadingAnchor constraintEqualToAnchor:self.serverLoginBadge.contentView.leadingAnchor constant:12],
        [self.serverLoginBadgeLabel.trailingAnchor constraintEqualToAnchor:self.serverLoginBadge.contentView.trailingAnchor constant:-12],
    ]];

    self.serverStatusLabel = [NSTextField labelWithString:@""];
    self.serverStatusLabel.font = [NSFont systemFontOfSize:12];
    self.serverStatusLabel.textColor = [NSColor secondaryLabelColor];

    self.serverURLField = [SBTextField standardField];
    self.serverURLField.placeholderString = @"http://117.72.44.160:8090";
    self.serverURLField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverURLField.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;

    self.serverEmailField = [SBTextField standardField];
    self.serverEmailField.placeholderString = @"邮箱";
    self.serverPasswordField = [SBSecureTextField standardField];
    self.serverPasswordField.placeholderString = @"密码（至少 8 位）";

    NSGridView *syncGrid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"服务器"], self.serverURLField],
        @[[NSTextField labelWithString:@"邮箱"], self.serverEmailField],
        @[[NSTextField labelWithString:@"密码"], self.serverPasswordField],
    ]];
    syncGrid.columnSpacing = 12;
    syncGrid.rowSpacing = 8;
    [syncGrid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    self.serverRegisterButton = [NSButton buttonWithTitle:@"注册" target:self action:@selector(serverRegisterClicked:)];
    self.serverLoginButton = [NSButton buttonWithTitle:@"登录" target:self action:@selector(serverLoginClicked:)];
    self.serverLogoutButton = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(serverLogoutClicked:)];
    for (NSButton *b in @[self.serverRegisterButton, self.serverLoginButton, self.serverLogoutButton]) {
        b.bezelStyle = NSBezelStyleRounded;
    }
    NSStackView *authRow = [NSStackView stackViewWithViews:@[self.serverRegisterButton, self.serverLoginButton, self.serverLogoutButton]];
    authRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    authRow.spacing = 8;

    self.serverEnabledCheckbox = [NSButton checkboxWithTitle:@"启用云同步" target:self action:@selector(serverEnabledToggled:)];
    self.serverShortcutCheckbox = [NSButton checkboxWithTitle:@"快捷方式（Launchpad）" target:self action:@selector(serverShortcutToggled:)];
    self.serverFormMemoCheckbox = [NSButton checkboxWithTitle:@"站点表单备忘" target:self action:@selector(serverFormMemoToggled:)];
    self.serverLastSyncLabel = [NSTextField labelWithString:@""];
    self.serverLastSyncLabel.font = [NSFont systemFontOfSize:11];
    self.serverLastSyncLabel.textColor = [NSColor secondaryLabelColor];
    self.serverSyncNowButton = [NSButton buttonWithTitle:@"立即同步" target:self action:@selector(serverSyncNowClicked:)];
    self.serverSyncNowButton.bezelStyle = NSBezelStyleRounded;

    self.serverHintLabel = [self makeHint:
        @"数据保存在你自己的 PocketBase 服务器，无需 Apple 开发者账号。"
        @"密码、Cookie、Companion 通知不会上传。表单备忘字段为明文。"];

    // —— 键盘 ——
    self.reloadShortcutEnabledCheckbox = [NSButton checkboxWithTitle:@"启用刷新快捷键"
                                                              target:self
                                                              action:@selector(reloadShortcutEnabledToggled:)];
    self.reloadShortcutButton = [NSButton buttonWithTitle:@"F5"
                                                   target:self
                                                   action:@selector(reloadShortcutButtonClicked:)];
    self.reloadShortcutButton.bezelStyle = NSBezelStyleRounded;
    [self.reloadShortcutButton.widthAnchor constraintGreaterThanOrEqualToConstant:88].active = YES;
    self.reloadShortcutResetButton = [NSButton buttonWithTitle:@"恢复默认"
                                                        target:self
                                                        action:@selector(reloadShortcutResetClicked:)];
    self.reloadShortcutResetButton.bezelStyle = NSBezelStyleRounded;
    NSTextField *reloadCaption = [NSTextField labelWithString:@"刷新页面"];
    reloadCaption.font = [NSFont systemFontOfSize:12];
    NSStackView *reloadShortcutRow = [NSStackView stackViewWithViews:@[
        reloadCaption, self.reloadShortcutButton, self.reloadShortcutResetButton
    ]];
    reloadShortcutRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    reloadShortcutRow.spacing = 12;
    reloadShortcutRow.alignment = NSLayoutAttributeCenterY;
    self.keyboardHintLabel = [self makeHint:
        @"默认 F5。点击快捷键按钮后按下新组合即可更改；Esc 取消。"
        @"⌘R 始终可用（查看 → 刷新）。"];

    // —— 隐私 ——
    self.clearWebsiteDataButton = [NSButton buttonWithTitle:@"清除网站数据…" target:self action:@selector(clearWebsiteDataClicked:)];
    self.clearWebsiteDataButton.bezelStyle = NSBezelStyleRounded;
    self.clearHistoryButton = [NSButton buttonWithTitle:@"清除浏览历史…" target:self action:@selector(clearHistoryClicked:)];
    self.clearHistoryButton.bezelStyle = NSBezelStyleRounded;
    self.userAgentCopyButton = [NSButton buttonWithTitle:@"复制 User-Agent" target:self action:@selector(copyUserAgentClicked:)];
    self.userAgentCopyButton.bezelStyle = NSBezelStyleRounded;
    self.clearWebsiteDataStatusLabel = [NSTextField labelWithString:@"缓存、Cookie 与网站本地存储"];
    self.clearWebsiteDataStatusLabel.font = [NSFont systemFontOfSize:11];
    self.clearWebsiteDataStatusLabel.textColor = [NSColor secondaryLabelColor];
    NSStackView *privacyRow = [NSStackView stackViewWithViews:@[self.clearWebsiteDataButton, self.clearHistoryButton, self.userAgentCopyButton]];
    privacyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    privacyRow.spacing = 12;
    self.clearHistoryOnQuitCheckbox = [NSButton checkboxWithTitle:@"退出时清除浏览历史"
                                                           target:self
                                                           action:@selector(clearHistoryOnQuitChanged:)];
    self.clearHistoryOnQuitCheckbox.state = BrowserHistoryStore.clearOnQuitEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.geolocationEnabledCheckbox = [NSButton checkboxWithTitle:@"允许网站请求定位"
                                                             target:self
                                                             action:@selector(geolocationEnabledChanged:)];
    self.geolocationEnabledCheckbox.state = [BrowserLocationPreferences sharedPreferences].geolocationEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.locationHintLabel = [self makeHint:
        @"网站可通过 navigator.geolocation 获取你的位置。首次访问时仍会询问是否允许该站点。"];
    self.openSystemLocationSettingsButton = [NSButton buttonWithTitle:@"打开系统定位设置…"
                                                               target:self
                                                               action:@selector(openSystemLocationSettingsClicked:)];
    self.openSystemLocationSettingsButton.bezelStyle = NSBezelStyleRounded;
    self.privacyHintLabel = [self makeHint:@"清除网站数据不会删除浏览历史；频繁清除 Cookie 可能导致部分站点反复要求人机验证。"];

    // —— 开发者 ——
    self.allowWebInspectionCheckbox = [NSButton checkboxWithTitle:@"允许网页检查"
                                                           target:self
                                                           action:@selector(allowWebInspectionChanged:)];
    self.developerHintLabel = [self makeHint:@""];
    [self refreshDeveloperInspectionUI];

    self.tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
    self.tabView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabView.tabViewType = NSTopTabsBezelBorder;
    self.tabView.delegate = self;

    [self addTabNamed:@"常规"
                views:@[searchGrid, searchHint, browserCaption, browserRow, browserHint]
            toTabView:self.tabView
           widthViews:@[searchHint, browserHint]];

    [self addTabNamed:@"云同步"
                views:@[
                    self.serverLoginBadge, self.serverStatusLabel, syncGrid, authRow,
                    self.serverEnabledCheckbox, self.serverShortcutCheckbox, self.serverFormMemoCheckbox,
                    self.serverLastSyncLabel, self.serverSyncNowButton, self.serverHintLabel,
                ]
            toTabView:self.tabView
           widthViews:@[self.serverLoginBadge, self.serverHintLabel]];

    [self addTabNamed:@"键盘"
                views:@[
                    self.reloadShortcutEnabledCheckbox, reloadShortcutRow, self.keyboardHintLabel,
                ]
            toTabView:self.tabView
           widthViews:@[self.keyboardHintLabel]];

    [self addTabNamed:@"隐私"
                views:@[
                    privacyRow, self.clearWebsiteDataStatusLabel,
                    self.geolocationEnabledCheckbox, self.locationHintLabel, self.openSystemLocationSettingsButton,
                    self.clearHistoryOnQuitCheckbox, self.privacyHintLabel,
                ]
            toTabView:self.tabView
           widthViews:@[self.locationHintLabel, self.privacyHintLabel]];

    [self addTabNamed:@"开发者"
                views:@[self.allowWebInspectionCheckbox, self.developerHintLabel]
            toTabView:self.tabView
           widthViews:@[self.developerHintLabel]];

    NSView *contentView = self.window.contentView;
    [contentView addSubview:self.tabView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:12],
        [self.tabView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12],
        [self.tabView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [self.tabView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-12],
    ]];

    [self refreshDefaultBrowserStatus];
    [self refreshServerSyncUI];
    [self refreshKeyboardShortcutUI];
    [self refreshLocationPermissionHint];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    (void)tabView;
    (void)tabViewItem;
    // 离开「键盘」页时结束快捷键录制，避免焦点混乱。
    if (self.recordingReloadShortcut) {
        [self stopRecordingReloadShortcut];
        [self refreshKeyboardShortcutUI];
    }
}

- (void)serverSyncUINeedsRefresh:(NSNotification *)note {
    (void)note;
    [self refreshServerSyncUI];
}

- (void)keyboardPreferencesDidChange:(NSNotification *)note {
    (void)note;
    if (self.recordingReloadShortcut) {
        return;
    }
    [self refreshKeyboardShortcutUI];
}

- (void)refreshKeyboardShortcutUI {
    BOOL enabled = [BrowserKeyboardPreferences reloadShortcutEnabled];
    self.reloadShortcutEnabledCheckbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.reloadShortcutButton.enabled = enabled;
    self.reloadShortcutResetButton.enabled = enabled && !self.recordingReloadShortcut;
    if (self.recordingReloadShortcut) {
        self.reloadShortcutButton.title = @"按下新快捷键…";
    } else {
        self.reloadShortcutButton.title = [BrowserKeyboardPreferences displayStringForReloadShortcut];
    }
}

- (void)reloadShortcutEnabledToggled:(id)sender {
    (void)sender;
    [self stopRecordingReloadShortcut];
    [BrowserKeyboardPreferences setReloadShortcutEnabled:
        (self.reloadShortcutEnabledCheckbox.state == NSControlStateValueOn)];
    [self refreshKeyboardShortcutUI];
}

- (void)reloadShortcutResetClicked:(id)sender {
    (void)sender;
    [self stopRecordingReloadShortcut];
    [BrowserKeyboardPreferences resetReloadShortcutToDefault];
    [self refreshKeyboardShortcutUI];
}

- (void)reloadShortcutButtonClicked:(id)sender {
    (void)sender;
    if (self.recordingReloadShortcut) {
        [self stopRecordingReloadShortcut];
        [self refreshKeyboardShortcutUI];
        return;
    }
    [self startRecordingReloadShortcut];
}

- (void)startRecordingReloadShortcut {
    if (self.recordingReloadShortcut) {
        return;
    }
    self.recordingReloadShortcut = YES;
    [self refreshKeyboardShortcutUI];
    __weak typeof(self) weakSelf = self;
    self.reloadShortcutRecordMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                              handler:^NSEvent *(NSEvent *event) {
            return [weakSelf handleReloadShortcutRecordEvent:event];
        }];
}

- (void)stopRecordingReloadShortcut {
    self.recordingReloadShortcut = NO;
    if (self.reloadShortcutRecordMonitor) {
        [NSEvent removeMonitor:self.reloadShortcutRecordMonitor];
        self.reloadShortcutRecordMonitor = nil;
    }
}

- (NSEvent *)handleReloadShortcutRecordEvent:(NSEvent *)event {
    if (!self.recordingReloadShortcut || self.window != NSApp.keyWindow) {
        return event;
    }

    // Esc：取消录制
    NSEventModifierFlags mods =
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL cmd = (mods & NSEventModifierFlagCommand) != 0;
    BOOL alt = (mods & NSEventModifierFlagOption) != 0;
    BOOL ctrl = (mods & NSEventModifierFlagControl) != 0;
    if (event.keyCode == 53 && !cmd && !alt && !ctrl) {
        [self stopRecordingReloadShortcut];
        [self refreshKeyboardShortcutUI];
        return nil;
    }

    // 忽略纯修饰键（Shift / Ctrl / Opt / Cmd）
    switch (event.keyCode) {
        case 54: case 55: case 56: case 57: case 58:
        case 59: case 60: case 61: case 62: case 63:
            return nil;
        default:
            break;
    }

    [BrowserKeyboardPreferences setReloadShortcutFromEvent:event];
    [self stopRecordingReloadShortcut];
    [self refreshKeyboardShortcutUI];
    return nil;
}

- (void)persistServerFields {
    ServerSyncSettings.sharedSettings.baseURL = self.serverURLField.stringValue ?: @"";
    ServerSyncSettings.sharedSettings.email = self.serverEmailField.stringValue ?: @"";
}

- (void)refreshServerSyncUI {
    ServerSyncSettings *settings = ServerSyncSettings.sharedSettings;
    ServerSyncEngine *engine = ServerSyncEngine.sharedEngine;
    BOOL loggedIn = ServerSyncAuth.sharedAuth.isLoggedIn;

    if (self.serverURLField.currentEditor == nil) {
        self.serverURLField.stringValue = settings.baseURL.length ? settings.baseURL : @"http://117.72.44.160:8090";
    }
    if (self.serverEmailField.currentEditor == nil) {
        self.serverEmailField.stringValue = settings.email ?: @"";
    }

    // 登录徽标
    if (loggedIn) {
        NSString *email = settings.email.length ? settings.email : @"已登录";
        self.serverLoginBadgeLabel.stringValue = [NSString stringWithFormat:@"● 已登录  ·  %@", email];
        self.serverLoginBadgeLabel.textColor = [NSColor colorWithCalibratedRed:0.10 green:0.45 blue:0.20 alpha:1.0];
        self.serverLoginBadge.fillColor = [NSColor colorWithCalibratedRed:0.82 green:0.94 blue:0.86 alpha:1.0];
        self.serverLoginBadge.borderColor = [NSColor colorWithCalibratedRed:0.35 green:0.70 blue:0.45 alpha:1.0];
    } else {
        self.serverLoginBadgeLabel.stringValue = @"○ 未登录  ·  请先注册或登录";
        self.serverLoginBadgeLabel.textColor = [NSColor colorWithCalibratedRed:0.55 green:0.25 blue:0.10 alpha:1.0];
        self.serverLoginBadge.fillColor = [NSColor colorWithCalibratedRed:0.98 green:0.92 blue:0.86 alpha:1.0];
        self.serverLoginBadge.borderColor = [NSColor colorWithCalibratedRed:0.85 green:0.55 blue:0.30 alpha:1.0];
    }

    NSString *status = engine.statusText.length ? engine.statusText : (loggedIn ? @"就绪" : @"等待登录");
    if (settings.lastErrorMessage.length > 0 && engine.state == ServerSyncEngineStateError) {
        status = settings.lastErrorMessage;
    }
    self.serverStatusLabel.stringValue = [NSString stringWithFormat:@"同步：%@", status];

    self.serverEnabledCheckbox.state = settings.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.serverShortcutCheckbox.state = settings.shortcutEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.serverFormMemoCheckbox.state = settings.formMemoEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    // 未登录时仍可勾选「启用」，但会提示先登录；分项随总开关
    self.serverEnabledCheckbox.enabled = YES;
    self.serverEnabledCheckbox.toolTip = loggedIn ? nil : @"勾选后需登录才会开始同步";
    self.serverShortcutCheckbox.enabled = settings.enabled;
    self.serverFormMemoCheckbox.enabled = settings.enabled;
    self.serverSyncNowButton.enabled = settings.enabled && loggedIn;
    self.serverLogoutButton.enabled = loggedIn;
    self.serverRegisterButton.enabled = !loggedIn;
    self.serverLoginButton.enabled = !loggedIn;

    if (settings.lastSyncAt > 0) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        self.serverLastSyncLabel.stringValue = [NSString stringWithFormat:@"上次同步：%@", [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:settings.lastSyncAt]]];
    } else {
        self.serverLastSyncLabel.stringValue = @"上次同步：—";
    }
}

- (void)serverRegisterClicked:(id)sender {
    (void)sender;
    [self persistServerFields];
    NSString *email = self.serverEmailField.stringValue;
    NSString *password = self.serverPasswordField.stringValue;
    __weak typeof(self) weakSelf = self;
    [[ServerSyncAuth sharedAuth] registerWithEmail:email password:password completion:^(NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"注册失败";
            alert.informativeText = error.localizedDescription ?: @"";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        } else {
            self.serverPasswordField.stringValue = @"";
            // 注册成功后自动打开云同步
            ServerSyncSettings.sharedSettings.enabled = YES;
            [[ServerSyncEngine sharedEngine] startIfNeeded];
        }
        [self refreshServerSyncUI];
    }];
}

- (void)serverLoginClicked:(id)sender {
    (void)sender;
    [self persistServerFields];
    NSString *email = self.serverEmailField.stringValue;
    NSString *password = self.serverPasswordField.stringValue;
    __weak typeof(self) weakSelf = self;
    [[ServerSyncAuth sharedAuth] loginWithEmail:email password:password completion:^(NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"登录失败";
            alert.informativeText = error.localizedDescription ?: @"";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        } else {
            self.serverPasswordField.stringValue = @"";
            if (!ServerSyncSettings.sharedSettings.enabled) {
                ServerSyncSettings.sharedSettings.enabled = YES;
            }
            [[ServerSyncEngine sharedEngine] startIfNeeded];
        }
        [self refreshServerSyncUI];
    }];
}

- (void)serverLogoutClicked:(id)sender {
    (void)sender;
    [[ServerSyncAuth sharedAuth] logout];
    [[ServerSyncEngine sharedEngine] stop];
    [self refreshServerSyncUI];
}

- (void)serverEnabledToggled:(id)sender {
    (void)sender;
    // 必须先读 checkbox 状态：persist 可能触发 refresh，会把状态写回旧值
    BOOL turnOn = (self.serverEnabledCheckbox.state == NSControlStateValueOn);
    [self persistServerFields];
    ServerSyncSettings.sharedSettings.enabled = turnOn;
    if (turnOn) {
        [[ServerSyncEngine sharedEngine] startIfNeeded];
    } else {
        [[ServerSyncEngine sharedEngine] stop];
    }
    [self refreshServerSyncUI];
}

- (void)serverShortcutToggled:(id)sender {
    (void)sender;
    ServerSyncSettings.sharedSettings.shortcutEnabled = (self.serverShortcutCheckbox.state == NSControlStateValueOn);
}

- (void)serverFormMemoToggled:(id)sender {
    (void)sender;
    ServerSyncSettings.sharedSettings.formMemoEnabled = (self.serverFormMemoCheckbox.state == NSControlStateValueOn);
}

- (void)serverSyncNowClicked:(id)sender {
    (void)sender;
    [self persistServerFields];
    [[ServerSyncEngine sharedEngine] syncNow];
    [self refreshServerSyncUI];
}

- (nullable NSString *)currentBrowserPageHost {
    id delegate = NSApp.delegate;
    if (![delegate isKindOfClass:[AppDelegate class]]) return nil;
    BrowserWindowController *browser = [(AppDelegate *)delegate keyBrowserWindowController];
    NSURL *url = browser.webView.URL;
    if (![BrowsingPreferences isPersistableURL:url]) return nil;
    return url.host;
}

- (void)selectCurrentSearchEngineInPopUp {
    NSString *currentID = [BrowsingPreferences defaultSearchEngineID];
    for (NSInteger i = 0; i < self.searchEnginePopUp.numberOfItems; i++) {
        NSMenuItem *item = [self.searchEnginePopUp itemAtIndex:i];
        if ([item.representedObject isEqual:currentID]) {
            [self.searchEnginePopUp selectItemAtIndex:i];
            return;
        }
    }
}

- (void)refreshDefaultBrowserStatus {
    BOOL isDefault = [BrowsingPreferences isDefaultBrowser];
    if (isDefault) {
        self.defaultBrowserStatusLabel.stringValue = @"当前已是默认浏览器";
        self.setDefaultBrowserButton.enabled = NO;
        self.setDefaultBrowserButton.title = @"已是默认浏览器";
    } else {
        self.defaultBrowserStatusLabel.stringValue = @"当前不是默认浏览器";
        self.setDefaultBrowserButton.enabled = YES;
        self.setDefaultBrowserButton.title = @"设为默认浏览器";
    }
}

- (void)searchEngineChanged:(id)sender {
    (void)sender;
    NSString *engineID = self.searchEnginePopUp.selectedItem.representedObject;
    if ([engineID isKindOfClass:[NSString class]]) {
        [BrowsingPreferences setDefaultSearchEngineID:engineID];
    }
}

- (void)setDefaultBrowserClicked:(id)sender {
    (void)sender;
    self.setDefaultBrowserButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [BrowsingPreferences requestSetAsDefaultBrowserWithCompletion:^(NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            BOOL cancelled = ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError)
                || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
            if (!cancelled) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法设为默认浏览器";
                alert.informativeText = error.localizedDescription ?: @"";
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            }
        }
        [self refreshDefaultBrowserStatus];
    }];
}

- (void)copyUserAgentClicked:(id)sender {
    (void)sender;
    NSString *ua = [BrowserUserAgent safariAlignedUserAgent];
    if (ua.length == 0) {
        self.clearWebsiteDataStatusLabel.stringValue = @"无法读取 User-Agent";
        return;
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:ua forType:NSPasteboardTypeString];
    self.clearWebsiteDataStatusLabel.stringValue = @"已复制 User-Agent";
}

- (void)clearWebsiteDataClicked:(id)sender {
    (void)sender;
    NSString *currentHost = [self currentBrowserPageHost];
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"清除网站数据？";
    confirm.informativeText = @"将删除 Cookie、缓存与网站本地存储。不会删除登录助手、站点备忘与浏览历史。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"清除全部"];
    NSButton *currentButton = [confirm addButtonWithTitle:@"清除当前站点"];
    currentButton.enabled = (currentHost.length > 0);
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        typeof(self) self = weakSelf;
        if (!self || returnCode == NSAlertThirdButtonReturn) return;
        BOOL clearAll = (returnCode == NSAlertFirstButtonReturn);
        BOOL clearCurrent = (returnCode == NSAlertSecondButtonReturn);
        if (!clearAll && !clearCurrent) return;
        if (clearCurrent && currentHost.length == 0) return;
        self.clearWebsiteDataButton.enabled = NO;
        self.clearWebsiteDataStatusLabel.stringValue = @"正在清除…";
        void (^finish)(NSError *, NSString *) = ^(NSError *error, NSString *ok) {
            typeof(self) inner = weakSelf;
            if (!inner) return;
            inner.clearWebsiteDataButton.enabled = YES;
            inner.clearWebsiteDataStatusLabel.stringValue = error ? @"清除失败" : ok;
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法清除网站数据";
                alert.informativeText = error.localizedDescription ?: @"";
                [alert beginSheetModalForWindow:inner.window completionHandler:nil];
            }
        };
        if (clearAll) {
            [BrowsingPreferences clearWebsiteDataWithCompletion:^(NSError *error) { finish(error, @"已清除全部"); }];
        } else {
            [BrowsingPreferences clearWebsiteDataForHost:currentHost completion:^(NSError *error) {
                finish(error, [NSString stringWithFormat:@"已清除 %@", currentHost]);
            }];
        }
    }];
}

- (void)clearHistoryClicked:(id)sender {
    (void)sender;
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"清除全部浏览历史？";
    confirm.informativeText = @"将删除本地浏览记录。不会删除快捷方式、Cookie 或网站数据。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"清除"];
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        typeof(self) self = weakSelf;
        if (!self || returnCode != NSAlertFirstButtonReturn) {
            return;
        }
        [[BrowserHistoryStore sharedStore] clearAll];
        [[BrowserHistoryStore sharedStore] flushSynchronously];
        self.clearWebsiteDataStatusLabel.stringValue = @"已清除浏览历史";
    }];
}

- (void)locationPreferencesDidChange:(NSNotification *)note {
    (void)note;
    self.geolocationEnabledCheckbox.state = [BrowserLocationPreferences sharedPreferences].geolocationEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshLocationPermissionHint];
}

- (void)refreshLocationPermissionHint {
    NSString *status = [BrowserLocationService systemAuthorizationStatusDescription];
    if ([BrowserLocationPreferences sharedPreferences].geolocationEnabled) {
        self.locationHintLabel.stringValue =
            [NSString stringWithFormat:@"%@。网站首次请求定位时会询问是否允许该站点。", status];
    } else {
        self.locationHintLabel.stringValue =
            [NSString stringWithFormat:@"%@。开启上方选项后，网站才可请求定位。", status];
    }
}

- (void)geolocationEnabledChanged:(id)sender {
    (void)sender;
    [BrowserLocationPreferences sharedPreferences].geolocationEnabled =
        (self.geolocationEnabledCheckbox.state == NSControlStateValueOn);
    [self refreshLocationPermissionHint];
}

- (void)developerPreferencesDidChange:(NSNotification *)note {
    (void)note;
    [self refreshDeveloperInspectionUI];
}

- (void)refreshDeveloperInspectionUI {
    BOOL supported = [BrowserWebInspector isInspectionSupported];
    self.allowWebInspectionCheckbox.enabled = supported;
    self.allowWebInspectionCheckbox.state =
        [BrowserDeveloperPreferences sharedPreferences].allowWebInspection
            ? NSControlStateValueOn : NSControlStateValueOff;
    if (!supported) {
        self.developerHintLabel.stringValue =
            @"需要 macOS 13.3 或更高版本才能使用系统 Web Inspector。";
        return;
    }
    self.developerHintLabel.stringValue =
        @"开启后可使用系统 Web Inspector（检查元素、控制台、网络等）。"
        @"快捷键 ⌘⌥I，或页面右键「检查元素」。"
        @"也可在 Safari 启用「开发」菜单后，通过「开发 → MeoBrowser」附加调试。"
        @"仅在调试时建议开启；关闭时不影响日常浏览。";
}

- (void)allowWebInspectionChanged:(id)sender {
    (void)sender;
    [BrowserDeveloperPreferences sharedPreferences].allowWebInspection =
        (self.allowWebInspectionCheckbox.state == NSControlStateValueOn);
}

- (void)openSystemLocationSettingsClicked:(id)sender {
    (void)sender;
    [BrowserLocationService openSystemLocationSettings];
}

- (void)clearHistoryOnQuitChanged:(id)sender {
    (void)sender;
    BrowserHistoryStore.clearOnQuitEnabled = (self.clearHistoryOnQuitCheckbox.state == NSControlStateValueOn);
}

- (void)showWindow:(id)sender {
    [self stopRecordingReloadShortcut];
    [self selectCurrentSearchEngineInPopUp];
    [self refreshDefaultBrowserStatus];
    self.clearWebsiteDataStatusLabel.stringValue = @"缓存、Cookie 与网站本地存储";
    self.clearHistoryOnQuitCheckbox.state = BrowserHistoryStore.clearOnQuitEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.geolocationEnabledCheckbox.state = [BrowserLocationPreferences sharedPreferences].geolocationEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshLocationPermissionHint];
    [self refreshDeveloperInspectionUI];
    [self refreshServerSyncUI];
    [self refreshKeyboardShortcutUI];
    [super showWindow:sender];
}

@end
