#import "BrowserSettingsWindowController.h"
#import "BrowsingPreferences.h"
#import "BrowserUserAgent.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "ServerSyncSettings.h"
#import "ServerSyncEngine.h"
#import "ServerSyncAuth.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import <WebKit/WebKit.h>

@interface BrowserSettingsWindowController ()
@property (nonatomic, strong) NSPopUpButton *searchEnginePopUp;
@property (nonatomic, strong) NSTextField *defaultBrowserStatusLabel;
@property (nonatomic, strong) NSButton *setDefaultBrowserButton;
@property (nonatomic, strong) NSButton *clearWebsiteDataButton;
@property (nonatomic, strong) NSButton *userAgentCopyButton;
@property (nonatomic, strong) NSTextField *clearWebsiteDataStatusLabel;
@property (nonatomic, strong) NSTextField *privacyHintLabel;

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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 760)
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
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *)makeCaption:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:13];
    return label;
}

- (NSBox *)makeSeparator {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    return separator;
}

- (void)buildUI {
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

    NSTextField *searchHint = [NSTextField labelWithString:@"在地址栏输入非网址内容时将使用所选搜索引擎。"];
    searchHint.font = [NSFont systemFontOfSize:11];
    searchHint.textColor = [NSColor secondaryLabelColor];

    NSBox *separator = [self makeSeparator];
    NSTextField *browserCaption = [self makeCaption:@"默认浏览器"];
    self.defaultBrowserStatusLabel = [NSTextField labelWithString:@""];
    self.defaultBrowserStatusLabel.font = [NSFont systemFontOfSize:12];
    self.defaultBrowserStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.setDefaultBrowserButton = [NSButton buttonWithTitle:@"设为默认浏览器" target:self action:@selector(setDefaultBrowserClicked:)];
    self.setDefaultBrowserButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *browserRow = [NSStackView stackViewWithViews:@[self.defaultBrowserStatusLabel, self.setDefaultBrowserButton]];
    browserRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    browserRow.spacing = 12;
    NSTextField *browserHint = [NSTextField wrappingLabelWithString:@"设为默认后，系统中打开的 http/https 链接将由 MeoBrowser 处理。"];
    browserHint.font = [NSFont systemFontOfSize:11];
    browserHint.textColor = [NSColor secondaryLabelColor];
    browserHint.preferredMaxLayoutWidth = 448;

    NSBox *separator2 = [self makeSeparator];
    NSTextField *syncCaption = [self makeCaption:@"Meo 云同步"];

    // 登录状态徽标（显著）
    self.serverLoginBadge = [[NSBox alloc] initWithFrame:NSZeroRect];
    self.serverLoginBadge.boxType = NSBoxCustom;
    self.serverLoginBadge.borderType = NSLineBorder;
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

    self.serverHintLabel = [NSTextField wrappingLabelWithString:
        @"数据保存在你自己的 PocketBase 服务器，无需 Apple 开发者账号。"
        @"密码、Cookie、Companion 通知不会上传。表单备忘字段为明文。"];
    self.serverHintLabel.font = [NSFont systemFontOfSize:11];
    self.serverHintLabel.textColor = [NSColor secondaryLabelColor];
    self.serverHintLabel.preferredMaxLayoutWidth = 448;

    NSBox *separator3 = [self makeSeparator];
    NSTextField *privacyCaption = [self makeCaption:@"隐私与数据"];
    self.clearWebsiteDataButton = [NSButton buttonWithTitle:@"清除网站数据…" target:self action:@selector(clearWebsiteDataClicked:)];
    self.clearWebsiteDataButton.bezelStyle = NSBezelStyleRounded;
    self.userAgentCopyButton = [NSButton buttonWithTitle:@"复制 User-Agent" target:self action:@selector(copyUserAgentClicked:)];
    self.userAgentCopyButton.bezelStyle = NSBezelStyleRounded;
    self.clearWebsiteDataStatusLabel = [NSTextField labelWithString:@"缓存、Cookie 与网站本地存储"];
    self.clearWebsiteDataStatusLabel.font = [NSFont systemFontOfSize:11];
    self.clearWebsiteDataStatusLabel.textColor = [NSColor secondaryLabelColor];
    NSStackView *privacyRow = [NSStackView stackViewWithViews:@[self.clearWebsiteDataButton, self.userAgentCopyButton, self.clearWebsiteDataStatusLabel]];
    privacyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    privacyRow.spacing = 12;
    self.privacyHintLabel = [NSTextField wrappingLabelWithString:@"频繁清除 Cookie 可能导致部分站点反复要求人机验证。"];
    self.privacyHintLabel.font = [NSFont systemFontOfSize:11];
    self.privacyHintLabel.textColor = [NSColor secondaryLabelColor];
    self.privacyHintLabel.preferredMaxLayoutWidth = 448;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        searchGrid, searchHint, separator,
        browserCaption, browserRow, browserHint, separator2,
        syncCaption, self.serverLoginBadge, self.serverStatusLabel, syncGrid, authRow,
        self.serverEnabledCheckbox, self.serverShortcutCheckbox, self.serverFormMemoCheckbox,
        self.serverLastSyncLabel, self.serverSyncNowButton, self.serverHintLabel, separator3,
        privacyCaption, privacyRow, self.privacyHintLabel,
    ]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *contentView = self.window.contentView;
    [contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [separator.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [separator2.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [separator3.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [self.serverLoginBadge.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [self.serverHintLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [self.privacyHintLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
    ]];

    [self refreshDefaultBrowserStatus];
    [self refreshServerSyncUI];
}

- (void)serverSyncUINeedsRefresh:(NSNotification *)note {
    (void)note;
    [self refreshServerSyncUI];
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
    confirm.informativeText = @"将删除 Cookie、缓存与网站本地存储。不会删除登录助手与站点备忘。";
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

- (void)showWindow:(id)sender {
    [self selectCurrentSearchEngineInPopUp];
    [self refreshDefaultBrowserStatus];
    self.clearWebsiteDataStatusLabel.stringValue = @"缓存、Cookie 与网站本地存储";
    [self refreshServerSyncUI];
    [super showWindow:sender];
}

@end
