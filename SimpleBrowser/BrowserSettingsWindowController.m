#import "BrowserSettingsWindowController.h"
#import "BrowsingPreferences.h"
#import "BrowserUserAgent.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "CloudSyncSettings.h"
#import "CloudSyncEngine.h"
#import "CloudSyncAccountObserver.h"
#import <WebKit/WebKit.h>

@interface BrowserSettingsWindowController ()
@property (nonatomic, strong) NSPopUpButton *searchEnginePopUp;
@property (nonatomic, strong) NSTextField *defaultBrowserStatusLabel;
@property (nonatomic, strong) NSButton *setDefaultBrowserButton;
@property (nonatomic, strong) NSButton *clearWebsiteDataButton;
@property (nonatomic, strong) NSButton *userAgentCopyButton;
@property (nonatomic, strong) NSTextField *clearWebsiteDataStatusLabel;
@property (nonatomic, strong) NSTextField *privacyHintLabel;
@property (nonatomic, strong) NSTextField *iCloudStatusLabel;
@property (nonatomic, strong) NSButton *iCloudEnabledCheckbox;
@property (nonatomic, strong) NSButton *iCloudShortcutCheckbox;
@property (nonatomic, strong) NSButton *iCloudFormMemoCheckbox;
@property (nonatomic, strong) NSTextField *iCloudLastSyncLabel;
@property (nonatomic, strong) NSButton *iCloudSyncNowButton;
@property (nonatomic, strong) NSButton *iCloudDeleteButton;
@property (nonatomic, strong) NSTextField *iCloudHintLabel;
@end

@implementation BrowserSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 640)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"设置";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cloudSyncUINeedsRefresh:)
                                                     name:CloudSyncSettingsDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cloudSyncUINeedsRefresh:)
                                                     name:CloudSyncEngineStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    NSTextField *searchCaption = [NSTextField labelWithString:@"默认搜索引擎"];
    searchCaption.font = [NSFont systemFontOfSize:13];

    self.searchEnginePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.searchEnginePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchEnginePopUp.controlSize = NSControlSizeRegular;
    self.searchEnginePopUp.target = self;
    self.searchEnginePopUp.action = @selector(searchEngineChanged:);

    for (NSDictionary *engine in [BrowsingPreferences availableSearchEngines]) {
        [self.searchEnginePopUp addItemWithTitle:engine[@"name"]];
        NSMenuItem *item = self.searchEnginePopUp.lastItem;
        item.representedObject = engine[@"id"];
    }
    [self selectCurrentSearchEngineInPopUp];

    NSGridView *searchGrid = [NSGridView gridViewWithViews:@[@[searchCaption, self.searchEnginePopUp]]];
    searchGrid.columnSpacing = 12;
    searchGrid.rowSpacing = 8;
    [searchGrid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [searchGrid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSTextField *searchHint = [NSTextField labelWithString:@"在地址栏输入非网址内容时将使用所选搜索引擎。"];
    searchHint.font = [NSFont systemFontOfSize:11];
    searchHint.textColor = [NSColor secondaryLabelColor];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *browserCaption = [NSTextField labelWithString:@"默认浏览器"];
    browserCaption.font = [NSFont systemFontOfSize:13];

    self.defaultBrowserStatusLabel = [NSTextField labelWithString:@""];
    self.defaultBrowserStatusLabel.font = [NSFont systemFontOfSize:12];
    self.defaultBrowserStatusLabel.textColor = [NSColor secondaryLabelColor];

    self.setDefaultBrowserButton = [NSButton buttonWithTitle:@"设为默认浏览器"
                                                      target:self
                                                      action:@selector(setDefaultBrowserClicked:)];
    self.setDefaultBrowserButton.bezelStyle = NSBezelStyleRounded;
    self.setDefaultBrowserButton.controlSize = NSControlSizeRegular;

    NSStackView *browserRow = [NSStackView stackViewWithViews:@[self.defaultBrowserStatusLabel, self.setDefaultBrowserButton]];
    browserRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    browserRow.alignment = NSLayoutAttributeCenterY;
    browserRow.spacing = 12;
    browserRow.distribution = NSStackViewDistributionFill;

    NSTextField *browserHint = [NSTextField wrappingLabelWithString:@"设为默认后，系统中打开的 http/https 链接将由 MeoBrowser 处理。更改时系统可能会弹出确认对话框。"];
    browserHint.font = [NSFont systemFontOfSize:11];
    browserHint.textColor = [NSColor secondaryLabelColor];
    browserHint.preferredMaxLayoutWidth = 428;

    NSBox *separator2 = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator2.boxType = NSBoxSeparator;
    separator2.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *iCloudCaption = [NSTextField labelWithString:@"iCloud 同步"];
    iCloudCaption.font = [NSFont systemFontOfSize:13];

    self.iCloudStatusLabel = [NSTextField labelWithString:@""];
    self.iCloudStatusLabel.font = [NSFont systemFontOfSize:12];
    self.iCloudStatusLabel.textColor = [NSColor secondaryLabelColor];

    self.iCloudEnabledCheckbox = [NSButton checkboxWithTitle:@"使用 iCloud 同步浏览数据"
                                                      target:self
                                                      action:@selector(iCloudEnabledToggled:)];

    self.iCloudShortcutCheckbox = [NSButton checkboxWithTitle:@"快捷方式（Launchpad）"
                                                       target:self
                                                       action:@selector(iCloudShortcutToggled:)];
    self.iCloudFormMemoCheckbox = [NSButton checkboxWithTitle:@"站点表单备忘"
                                                       target:self
                                                       action:@selector(iCloudFormMemoToggled:)];

    self.iCloudLastSyncLabel = [NSTextField labelWithString:@""];
    self.iCloudLastSyncLabel.font = [NSFont systemFontOfSize:11];
    self.iCloudLastSyncLabel.textColor = [NSColor secondaryLabelColor];

    self.iCloudSyncNowButton = [NSButton buttonWithTitle:@"立即同步"
                                                  target:self
                                                  action:@selector(iCloudSyncNowClicked:)];
    self.iCloudSyncNowButton.bezelStyle = NSBezelStyleRounded;
    self.iCloudSyncNowButton.controlSize = NSControlSizeRegular;

    self.iCloudDeleteButton = [NSButton buttonWithTitle:@"从 iCloud 删除同步数据…"
                                                 target:self
                                                 action:@selector(iCloudDeleteClicked:)];
    self.iCloudDeleteButton.bezelStyle = NSBezelStyleRounded;
    self.iCloudDeleteButton.controlSize = NSControlSizeRegular;

    NSStackView *iCloudButtons = [NSStackView stackViewWithViews:@[self.iCloudSyncNowButton, self.iCloudDeleteButton]];
    iCloudButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    iCloudButtons.spacing = 12;

    self.iCloudHintLabel = [NSTextField wrappingLabelWithString:
        @"数据保存在你自己的 iCloud 私有库，MeoBrowser 无自建同步服务器。"
        @"密码、Cookie、Companion 通知不会上传。"
        @"开启「站点表单备忘」时字段明文会进入你的 iCloud。"
        @"本地 adhoc 构建通常没有 CloudKit 签名 entitlement，打开本页不会调用 CloudKit；"
        @"真机双向同步需开发者证书签名并配置容器 iCloud.com.example.MeoBrowser。"];
    self.iCloudHintLabel.font = [NSFont systemFontOfSize:11];
    self.iCloudHintLabel.textColor = [NSColor secondaryLabelColor];
    self.iCloudHintLabel.preferredMaxLayoutWidth = 428;

    NSBox *separator3 = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator3.boxType = NSBoxSeparator;
    separator3.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *privacyCaption = [NSTextField labelWithString:@"隐私与数据"];
    privacyCaption.font = [NSFont systemFontOfSize:13];

    self.clearWebsiteDataButton = [NSButton buttonWithTitle:@"清除网站数据…"
                                                     target:self
                                                     action:@selector(clearWebsiteDataClicked:)];
    self.clearWebsiteDataButton.bezelStyle = NSBezelStyleRounded;
    self.clearWebsiteDataButton.controlSize = NSControlSizeRegular;

    self.userAgentCopyButton = [NSButton buttonWithTitle:@"复制 User-Agent"
                                                  target:self
                                                  action:@selector(copyUserAgentClicked:)];
    self.userAgentCopyButton.bezelStyle = NSBezelStyleRounded;
    self.userAgentCopyButton.controlSize = NSControlSizeRegular;

    self.clearWebsiteDataStatusLabel = [NSTextField labelWithString:@"缓存、Cookie 与网站本地存储"];
    self.clearWebsiteDataStatusLabel.font = [NSFont systemFontOfSize:11];
    self.clearWebsiteDataStatusLabel.textColor = [NSColor secondaryLabelColor];

    NSStackView *privacyRow = [NSStackView stackViewWithViews:@[
        self.clearWebsiteDataButton,
        self.userAgentCopyButton,
        self.clearWebsiteDataStatusLabel
    ]];
    privacyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    privacyRow.alignment = NSLayoutAttributeCenterY;
    privacyRow.spacing = 12;

    self.privacyHintLabel = [NSTextField wrappingLabelWithString:
        @"频繁清除 Cookie 可能导致 Google 等站点反复要求人机验证。"
        @"若使用 VPN/共享网络仍频繁验证，可先关闭 VPN 用本机网络重试。"];
    self.privacyHintLabel.font = [NSFont systemFontOfSize:11];
    self.privacyHintLabel.textColor = [NSColor secondaryLabelColor];
    self.privacyHintLabel.preferredMaxLayoutWidth = 428;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        searchGrid,
        searchHint,
        separator,
        browserCaption,
        browserRow,
        browserHint,
        separator2,
        iCloudCaption,
        self.iCloudStatusLabel,
        self.iCloudEnabledCheckbox,
        self.iCloudShortcutCheckbox,
        self.iCloudFormMemoCheckbox,
        self.iCloudLastSyncLabel,
        iCloudButtons,
        self.iCloudHintLabel,
        separator3,
        privacyCaption,
        privacyRow,
        self.privacyHintLabel,
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
        [browserRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [privacyRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [self.privacyHintLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [self.iCloudHintLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
    ]];

    [self refreshDefaultBrowserStatus];
    [self refreshICloudSyncUI];
}

- (void)cloudSyncUINeedsRefresh:(NSNotification *)note {
    (void)note;
    [self refreshICloudSyncUI];
}

- (void)refreshICloudSyncUI {
    CloudSyncSettings *settings = CloudSyncSettings.sharedSettings;
    CloudSyncEngine *engine = CloudSyncEngine.sharedEngine;
    CloudSyncAccountObserver *account = CloudSyncAccountObserver.sharedObserver;

    NSString *status = engine.statusText.length > 0 ? engine.statusText : account.statusMessage;
    if (settings.lastErrorMessage.length > 0 && engine.state == CloudSyncEngineStateError) {
        status = settings.lastErrorMessage;
    }
    self.iCloudStatusLabel.stringValue = [NSString stringWithFormat:@"状态：%@", status ?: @"—"];

    self.iCloudEnabledCheckbox.state = settings.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.iCloudShortcutCheckbox.state = settings.shortcutEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.iCloudFormMemoCheckbox.state = settings.formMemoEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL osOK = YES;
    if (@available(macOS 14.0, *)) {
        osOK = YES;
    } else {
        osOK = NO;
    }
    BOOL canUse = osOK;
    self.iCloudEnabledCheckbox.enabled = canUse;
    BOOL kindsEnabled = canUse && settings.enabled;
    self.iCloudShortcutCheckbox.enabled = kindsEnabled;
    self.iCloudFormMemoCheckbox.enabled = kindsEnabled;
    self.iCloudSyncNowButton.enabled = kindsEnabled;
    self.iCloudDeleteButton.enabled = kindsEnabled;

    if (settings.lastSyncAt > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:settings.lastSyncAt];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        self.iCloudLastSyncLabel.stringValue = [NSString stringWithFormat:@"上次同步：%@", [fmt stringFromDate:date]];
    } else {
        self.iCloudLastSyncLabel.stringValue = @"上次同步：—";
    }
}

- (void)iCloudEnabledToggled:(id)sender {
    (void)sender;
    CloudSyncSettings.sharedSettings.enabled = (self.iCloudEnabledCheckbox.state == NSControlStateValueOn);
    if (CloudSyncSettings.sharedSettings.enabled) {
        [[CloudSyncEngine sharedEngine] startIfNeeded];
    } else {
        [[CloudSyncEngine sharedEngine] stop];
    }
    [self refreshICloudSyncUI];
}

- (void)iCloudShortcutToggled:(id)sender {
    (void)sender;
    CloudSyncSettings.sharedSettings.shortcutEnabled = (self.iCloudShortcutCheckbox.state == NSControlStateValueOn);
}

- (void)iCloudFormMemoToggled:(id)sender {
    (void)sender;
    CloudSyncSettings.sharedSettings.formMemoEnabled = (self.iCloudFormMemoCheckbox.state == NSControlStateValueOn);
}

- (void)iCloudSyncNowClicked:(id)sender {
    (void)sender;
    [[CloudSyncEngine sharedEngine] syncNow];
    [self refreshICloudSyncUI];
}

- (void)iCloudDeleteClicked:(id)sender {
    (void)sender;
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"从 iCloud 删除 Meo 同步数据？";
    confirm.informativeText = @"将删除 iCloud 中的快捷方式与表单备忘同步副本，不会删除本机数据。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"删除"];
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) {
            return;
        }
        [[CloudSyncEngine sharedEngine] deleteCloudDataWithCompletion:^(NSError *error) {
            typeof(self) self = weakSelf;
            if (!self) {
                return;
            }
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法删除 iCloud 数据";
                alert.informativeText = error.localizedDescription ?: @"未知错误";
                alert.alertStyle = NSAlertStyleWarning;
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            }
            [self refreshICloudSyncUI];
        }];
    }];
}

- (nullable NSString *)currentBrowserPageHost {
    id delegate = NSApp.delegate;
    if (![delegate isKindOfClass:[AppDelegate class]]) {
        return nil;
    }
    BrowserWindowController *browser = [(AppDelegate *)delegate keyBrowserWindowController];
    NSURL *url = browser.webView.URL;
    if (![BrowsingPreferences isPersistableURL:url]) {
        return nil;
    }
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
    NSMenuItem *item = self.searchEnginePopUp.selectedItem;
    NSString *engineID = item.representedObject;
    if (![engineID isKindOfClass:[NSString class]]) {
        return;
    }
    [BrowsingPreferences setDefaultSearchEngineID:engineID];
}

- (void)setDefaultBrowserClicked:(id)sender {
    (void)sender;
    self.setDefaultBrowserButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [BrowsingPreferences requestSetAsDefaultBrowserWithCompletion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            BOOL cancelled = ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError)
                || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
            if (!cancelled) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法设为默认浏览器";
                alert.informativeText = error.localizedDescription.length > 0
                    ? error.localizedDescription
                    : @"请在「系统设置 › 桌面与 Dock › 默认网页浏览器」中手动选择 MeoBrowser。";
                alert.alertStyle = NSAlertStyleWarning;
                [alert beginSheetModalForWindow:strongSelf.window completionHandler:nil];
            }
        }
        [strongSelf refreshDefaultBrowserStatus];
    }];
}

- (void)copyUserAgentClicked:(id)sender {
    (void)sender;
    NSString *ua = [BrowserUserAgent safariAlignedUserAgent];
    if (ua.length == 0) {
        self.clearWebsiteDataStatusLabel.stringValue = @"无法读取 User-Agent";
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:ua forType:NSPasteboardTypeString];
    self.clearWebsiteDataStatusLabel.stringValue = @"已复制 User-Agent";
}

- (void)clearWebsiteDataClicked:(id)sender {
    (void)sender;
    NSString *currentHost = [self currentBrowserPageHost];

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"清除网站数据？";
    confirm.informativeText =
        @"将删除 Cookie、缓存与网站本地存储。已打开的标签页不会关闭，但登录状态可能会失效。"
        @"不会删除「登录助手」中保存的账号配置。\n\n"
        @"频繁清除全部数据可能导致 Google 等站点反复要求人机验证。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"清除全部"];
    NSButton *currentButton = [confirm addButtonWithTitle:@"清除当前站点"];
    currentButton.enabled = (currentHost.length > 0);
    [confirm addButtonWithTitle:@"取消"];

    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (returnCode == NSAlertThirdButtonReturn) {
            return;
        }
        BOOL clearAll = (returnCode == NSAlertFirstButtonReturn);
        BOOL clearCurrent = (returnCode == NSAlertSecondButtonReturn);
        if (!clearAll && !clearCurrent) {
            return;
        }
        if (clearCurrent && currentHost.length == 0) {
            return;
        }

        strongSelf.clearWebsiteDataButton.enabled = NO;
        strongSelf.clearWebsiteDataStatusLabel.stringValue = @"正在清除…";

        void (^finishUI)(NSError * _Nullable, NSString *) = ^(NSError * _Nullable error, NSString *okText) {
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            innerSelf.clearWebsiteDataButton.enabled = YES;
            if (error) {
                innerSelf.clearWebsiteDataStatusLabel.stringValue = @"清除失败";
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法清除网站数据";
                alert.informativeText = error.localizedDescription ?: @"未知错误";
                alert.alertStyle = NSAlertStyleWarning;
                [alert beginSheetModalForWindow:innerSelf.window completionHandler:nil];
            } else {
                innerSelf.clearWebsiteDataStatusLabel.stringValue = okText;
            }
        };

        if (clearAll) {
            [BrowsingPreferences clearWebsiteDataWithCompletion:^(NSError * _Nullable error) {
                finishUI(error, @"已清除全部");
            }];
        } else {
            [BrowsingPreferences clearWebsiteDataForHost:currentHost completion:^(NSError * _Nullable error) {
                NSString *ok = [NSString stringWithFormat:@"已清除 %@", currentHost];
                finishUI(error, ok);
            }];
        }
    }];
}

- (void)showWindow:(id)sender {
    [self selectCurrentSearchEngineInPopUp];
    [self refreshDefaultBrowserStatus];
    self.clearWebsiteDataStatusLabel.stringValue = @"缓存、Cookie 与网站本地存储";
    [[CloudSyncAccountObserver sharedObserver] refreshWithCompletion:nil];
    [self refreshICloudSyncUI];
    [super showWindow:sender];
}

@end
