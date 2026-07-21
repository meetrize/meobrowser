#import "BrowserLoginAssistSettingsWindowController.h"
#import "LoginAssistController.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginElementPicker.h"
#import "LoginAssistPreferences.h"
#import "CompanionChannel.h"
#import "CompanionPairingStore.h"
#import "CompanionLinkUI.h"
#import "PhoneNotificationSettings.h"
#import "CompanionSyncSettings.h"
#import "PhoneNotificationPresenter.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>

@interface BrowserLoginAssistSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<LoginRecipe *> *recipes;
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *hostField;
@property (nonatomic, strong) SBTextField *pathPrefixField;
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) SBTextField *usernameField;
@property (nonatomic, strong) SBSecureTextField *passwordField;
@property (nonatomic, strong) SBTextField *phoneField;
@property (nonatomic, strong) SBTextField *usernameSelectorField;
@property (nonatomic, strong) SBTextField *passwordSelectorField;
@property (nonatomic, strong) SBTextField *phoneSelectorField;
@property (nonatomic, strong) SBTextField *otpSelectorField;
@property (nonatomic, strong) SBTextField *sendCodeSelectorField;
@property (nonatomic, strong) SBTextField *submitSelectorField;
@property (nonatomic, strong) NSButton *submitByEnterCheck;
@property (nonatomic, strong) NSButton *autoLoginCheck;
@property (nonatomic, strong) NSButton *defaultCheck;
@property (nonatomic, strong) NSButton *inlineAssistCheck;
@property (nonatomic, strong) NSButton *promptSaveCheck;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSView *companionStatusCard;
@property (nonatomic, strong) NSView *companionStatusIconBg;
@property (nonatomic, strong) NSView *companionStatusDotView;
@property (nonatomic, strong) NSTextField *companionConnectionLabel;
@property (nonatomic, strong) NSButton *companionEndpointButton;
@property (nonatomic, strong) NSSegmentedControl *companionAuthModeControl;
@property (nonatomic, strong) NSStackView *pairingModeStack;
@property (nonatomic, strong) NSStackView *securityModeStack;
@property (nonatomic, strong) NSTextField *pairingCodeCaption;
@property (nonatomic, strong) NSButton *pairingCodeButton;
@property (nonatomic, strong) NSButton *refreshPairingButton;
@property (nonatomic, strong) NSStackView *pairingRow;
@property (nonatomic, strong) SBTextField *securityCodeField;
@property (nonatomic, strong) NSButton *saveSecurityCodeButton;
@property (nonatomic, strong) NSButton *changePortButton;
@property (nonatomic, strong) NSTextField *companionHintLabel;
@property (nonatomic, strong) NSButton *mirrorEnabledCheck;
@property (nonatomic, strong) NSButton *otpBannerEnabledCheck;
@property (nonatomic, strong) NSButton *openNotificationSettingsButton;
@property (nonatomic, strong) NSTextField *mirrorHintLabel;
@property (nonatomic, strong) NSButton *syncEnabledCheck;
@property (nonatomic, strong) NSButton *syncShortcutsCheck;
@property (nonatomic, strong) NSButton *syncHistoryCheck;
@property (nonatomic, strong) NSButton *syncBookmarksCheck;
@property (nonatomic, strong) NSScrollView *formScrollView;
@property (nonatomic, copy, nullable) NSString *editingRecipeID;
@property (nonatomic, copy, nullable) NSString *pickingTarget;
@property (nonatomic, copy, nullable) NSString *displayedPairingCode;
@property (nonatomic, copy, nullable) NSString *displayedEndpoint;
@end

@implementation BrowserLoginAssistSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 720)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"登录助手与互联";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(700, 600);
    self = [super initWithWindow:window];
    if (self) {
        _recipes = @[];
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recipesDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(companionStateDidChange:)
                                                     name:CompanionChannelStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)recipesDidChange:(NSNotification *)note {
    (void)note;
    NSString *keepID = self.editingRecipeID;
    [self reloadRecipes];
    if (keepID.length > 0) {
        [self selectRecipeID:keepID];
    }
}

- (SBTextField *)makeField {
    SBTextField *field = [SBTextField standardField];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:22].active = YES;
    return field;
}

- (SBSecureTextField *)makeSecureField {
    SBSecureTextField *field = [SBSecureTextField standardField];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:22].active = YES;
    return field;
}

- (NSTextField *)caption:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:12];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSStackView *)labeledRow:(NSString *)title field:(NSView *)field pickAction:(nullable SEL)pickAction {
    NSTextField *caption = [self caption:title];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [caption.widthAnchor constraintEqualToConstant:88].active = YES;

    NSMutableArray *views = [NSMutableArray arrayWithObjects:caption, field, nil];
    if (pickAction) {
        NSButton *pick = [NSButton buttonWithTitle:@"拾取"
                                            target:self
                                            action:pickAction];
        pick.bezelStyle = NSBezelStyleRounded;
        pick.controlSize = NSControlSizeSmall;
        [views addObject:pick];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.distribution = NSStackViewDistributionFill;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

- (void)buildUI {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"站点配置";
    col.width = 200;
    [self.tableView addTableColumn:col];
    self.tableView.headerView = nil;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.target = self;
    self.tableView.action = @selector(tableSelectionChanged:);
    scroll.documentView = self.tableView;

    NSButton *addButton = [NSButton buttonWithTitle:@"新建"
                                             target:self
                                             action:@selector(addRecipe:)];
    addButton.bezelStyle = NSBezelStyleRounded;
    NSButton *deleteButton = [NSButton buttonWithTitle:@"删除"
                                                target:self
                                                action:@selector(deleteRecipe:)];
    deleteButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *listButtons = [NSStackView stackViewWithViews:@[addButton, deleteButton]];
    listButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    listButtons.spacing = 8;

    NSStackView *listColumn = [NSStackView stackViewWithViews:@[scroll, listButtons]];
    listColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    listColumn.spacing = 8;
    listColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    self.titleField = [self makeField];
    self.hostField = [self makeField];
    self.pathPrefixField = [self makeField];
    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modePopup removeAllItems];
    [self.modePopup addItemWithTitle:@"密码"];
    [self.modePopup addItemWithTitle:@"短信验证码"];
    [self.modePopup addItemWithTitle:@"账密 + 短信"];
    self.modePopup.target = self;
    self.modePopup.action = @selector(modeChanged:);
    self.usernameField = [self makeField];
    self.passwordField = [self makeSecureField];
    self.phoneField = [self makeField];
    self.usernameSelectorField = [self makeField];
    self.passwordSelectorField = [self makeField];
    self.phoneSelectorField = [self makeField];
    self.otpSelectorField = [self makeField];
    self.sendCodeSelectorField = [self makeField];
    self.submitSelectorField = [self makeField];

    self.submitByEnterCheck = [NSButton checkboxWithTitle:@"默认：密码/验证码框回车提交（不勾选则点击下方提交选择器）"
                                                   target:self
                                                   action:@selector(submitModeChanged:)];
    self.autoLoginCheck = [NSButton checkboxWithTitle:@"自动登录（进入匹配页后自动执行）"
                                               target:nil
                                               action:nil];
    self.defaultCheck = [NSButton checkboxWithTitle:@"设为该站点默认账号"
                                             target:nil
                                             action:nil];

    self.inlineAssistCheck = [NSButton checkboxWithTitle:@"检测到登录表单时显示内联图标（新标签生效）"
                                                  target:self
                                                  action:@selector(prefsChanged:)];
    self.promptSaveCheck = [NSButton checkboxWithTitle:@"登录成功后询问是否保存为配置"
                                                target:self
                                                action:@selector(prefsChanged:)];
    self.inlineAssistCheck.state = [LoginAssistPreferences inlineAssistEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    self.promptSaveCheck.state = [LoginAssistPreferences promptSaveOnSuccess] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *saveButton = [NSButton buttonWithTitle:@"保存"
                                              target:self
                                              action:@selector(saveRecipe:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";

    self.statusLabel = [NSTextField wrappingLabelWithString:@"凭证保存在本地钥匙串；清除「网站数据」不会删除登录配置。"];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.preferredMaxLayoutWidth = 460;

    // Companion：状态卡片 + 分区卡片（与 Android 互联页同构）
    self.companionConnectionLabel = [NSTextField labelWithString:@"未连接"];
    self.companionConnectionLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    self.companionConnectionLabel.selectable = NO;

    self.companionHintLabel = [NSTextField wrappingLabelWithString:@""];
    self.companionHintLabel.font = [NSFont systemFontOfSize:12];
    self.companionHintLabel.textColor = [NSColor secondaryLabelColor];
    self.companionHintLabel.preferredMaxLayoutWidth = 360;

    self.companionStatusIconBg = [[NSView alloc] initWithFrame:NSZeroRect];
    self.companionStatusIconBg.wantsLayer = YES;
    self.companionStatusIconBg.layer.cornerRadius = 22;
    self.companionStatusIconBg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.companionStatusIconBg.widthAnchor constraintEqualToConstant:44].active = YES;
    [self.companionStatusIconBg.heightAnchor constraintEqualToConstant:44].active = YES;

    NSImageView *statusIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    statusIconView.translatesAutoresizingMaskIntoConstraints = NO;
    statusIconView.imageScaling = NSImageScaleProportionallyDown;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:16
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *linkImage = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:nil];
        statusIconView.image = [linkImage imageWithSymbolConfiguration:config];
        if (@available(macOS 10.14, *)) {
            statusIconView.contentTintColor = [NSColor labelColor];
        }
    }
    [self.companionStatusIconBg addSubview:statusIconView];
    [NSLayoutConstraint activateConstraints:@[
        [statusIconView.centerXAnchor constraintEqualToAnchor:self.companionStatusIconBg.centerXAnchor],
        [statusIconView.centerYAnchor constraintEqualToAnchor:self.companionStatusIconBg.centerYAnchor],
        [statusIconView.widthAnchor constraintEqualToConstant:20],
        [statusIconView.heightAnchor constraintEqualToConstant:20],
    ]];

    self.companionStatusDotView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.companionStatusDotView.wantsLayer = YES;
    self.companionStatusDotView.layer.cornerRadius = 5;
    self.companionStatusDotView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.companionStatusIconBg addSubview:self.companionStatusDotView];
    [NSLayoutConstraint activateConstraints:@[
        [self.companionStatusDotView.widthAnchor constraintEqualToConstant:10],
        [self.companionStatusDotView.heightAnchor constraintEqualToConstant:10],
        [self.companionStatusDotView.trailingAnchor constraintEqualToAnchor:self.companionStatusIconBg.trailingAnchor constant:1],
        [self.companionStatusDotView.bottomAnchor constraintEqualToAnchor:self.companionStatusIconBg.bottomAnchor constant:1],
    ]];

    NSStackView *statusTextCol = [NSStackView stackViewWithViews:@[self.companionConnectionLabel, self.companionHintLabel]];
    statusTextCol.orientation = NSUserInterfaceLayoutOrientationVertical;
    statusTextCol.alignment = NSLayoutAttributeLeading;
    statusTextCol.spacing = 4;

    NSStackView *statusHeader = [NSStackView stackViewWithViews:@[self.companionStatusIconBg, statusTextCol]];
    statusHeader.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusHeader.alignment = NSLayoutAttributeCenterY;
    statusHeader.spacing = 12;

    self.companionEndpointButton = [NSButton buttonWithTitle:@"主机：—"
                                                      target:self
                                                      action:@selector(copyCompanionEndpoint:)];
    self.companionEndpointButton.bordered = NO;
    self.companionEndpointButton.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium];
    self.companionEndpointButton.contentTintColor = [NSColor linkColor];
    self.companionEndpointButton.toolTip = @"点击复制完整地址（IP:端口）";
    self.companionEndpointButton.alignment = NSTextAlignmentLeft;

    self.changePortButton = [NSButton buttonWithTitle:@"更换端口…"
                                               target:self
                                               action:@selector(changeCompanionPort:)];
    self.changePortButton.bezelStyle = NSBezelStyleRounded;
    self.changePortButton.toolTip = @"端口默认固定；仅在手动确认后才会更换";

    NSStackView *endpointRow = [NSStackView stackViewWithViews:@[self.companionEndpointButton, self.changePortButton]];
    endpointRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    endpointRow.alignment = NSLayoutAttributeCenterY;
    endpointRow.spacing = 12;

    self.companionStatusCard = [self makeSettingsCardWithTitle:nil
                                              arrangedSubviews:@[statusHeader, endpointRow]];

    self.companionAuthModeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.companionAuthModeControl.segmentCount = 2;
    [self.companionAuthModeControl setLabel:@"临时配对码" forSegment:0];
    [self.companionAuthModeControl setLabel:@"固定安全码" forSegment:1];
    self.companionAuthModeControl.selectedSegment =
        ([CompanionPairingStore sharedStore].authMode == CompanionAuthModeSecurityCode) ? 1 : 0;
    self.companionAuthModeControl.target = self;
    self.companionAuthModeControl.action = @selector(companionAuthModeChanged:);
    self.companionAuthModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.companionAuthModeControl.widthAnchor constraintEqualToConstant:260].active = YES;

    self.pairingCodeCaption = [NSTextField labelWithString:@"配对码（点击可复制）"];
    self.pairingCodeCaption.font = [NSFont systemFontOfSize:11];
    self.pairingCodeCaption.textColor = [NSColor secondaryLabelColor];

    self.pairingCodeButton = [NSButton buttonWithTitle:@"----"
                                                target:self
                                                action:@selector(copyPairingCode:)];
    self.pairingCodeButton.bordered = NO;
    self.pairingCodeButton.font = [NSFont monospacedDigitSystemFontOfSize:28 weight:NSFontWeightBold];
    self.pairingCodeButton.toolTip = @"点击复制配对码";
    self.pairingCodeButton.alignment = NSTextAlignmentLeft;

    self.refreshPairingButton = [NSButton buttonWithTitle:@"刷新配对码"
                                                   target:self
                                                   action:@selector(refreshPairingCode:)];
    self.refreshPairingButton.bezelStyle = NSBezelStyleRounded;

    self.pairingRow = [NSStackView stackViewWithViews:@[self.pairingCodeButton, self.refreshPairingButton]];
    self.pairingRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.pairingRow.alignment = NSLayoutAttributeCenterY;
    self.pairingRow.spacing = 12;

    self.pairingModeStack = [NSStackView stackViewWithViews:@[self.pairingCodeCaption, self.pairingRow]];
    self.pairingModeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.pairingModeStack.alignment = NSLayoutAttributeLeading;
    self.pairingModeStack.spacing = 4;

    NSTextField *securityCaption = [NSTextField labelWithString:@"固定安全码（4～12 位字母或数字，手机端保存后可自动连接）"];
    securityCaption.font = [NSFont systemFontOfSize:11];
    securityCaption.textColor = [NSColor secondaryLabelColor];

    self.securityCodeField = [self makeField];
    self.securityCodeField.placeholderString = @"例如 884422";
    NSString *existingSecurity = [CompanionPairingStore sharedStore].securityCode;
    if (existingSecurity.length > 0) {
        self.securityCodeField.stringValue = existingSecurity;
    }
    [self.securityCodeField.widthAnchor constraintEqualToConstant:180].active = YES;

    self.saveSecurityCodeButton = [NSButton buttonWithTitle:@"保存安全码"
                                                     target:self
                                                     action:@selector(saveSecurityCode:)];
    self.saveSecurityCodeButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *securityInputRow = [NSStackView stackViewWithViews:@[self.securityCodeField, self.saveSecurityCodeButton]];
    securityInputRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    securityInputRow.alignment = NSLayoutAttributeCenterY;
    securityInputRow.spacing = 12;

    self.securityModeStack = [NSStackView stackViewWithViews:@[securityCaption, securityInputRow]];
    self.securityModeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.securityModeStack.alignment = NSLayoutAttributeLeading;
    self.securityModeStack.spacing = 4;

    NSButton *revokeDevices = [NSButton buttonWithTitle:@"注销已配对设备"
                                                 target:self
                                                 action:@selector(revokeCompanionDevices:)];
    revokeDevices.bezelStyle = NSBezelStyleRounded;

    NSView *authCard = [self makeSettingsCardWithTitle:@"连接方式"
                                      arrangedSubviews:@[
                                          self.companionAuthModeControl,
                                          self.pairingModeStack,
                                          self.securityModeStack,
                                          revokeDevices,
                                      ]];

    PhoneNotificationSettings *mirrorSettings = [PhoneNotificationSettings sharedSettings];
    self.mirrorEnabledCheck = [NSButton checkboxWithTitle:@"接收手机通知镜像（全部通知模式）"
                                                   target:self
                                                   action:@selector(mirrorSettingsChanged:)];
    self.mirrorEnabledCheck.state = mirrorSettings.mirrorEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    self.otpBannerEnabledCheck = [NSButton checkboxWithTitle:@"收到验证码时显示系统通知"
                                                      target:self
                                                      action:@selector(mirrorSettingsChanged:)];
    self.otpBannerEnabledCheck.state = mirrorSettings.otpBannerEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    self.openNotificationSettingsButton = [NSButton buttonWithTitle:@"打开系统通知设置…"
                                                             target:self
                                                             action:@selector(openSystemNotificationSettings:)];
    self.openNotificationSettingsButton.bezelStyle = NSBezelStyleRounded;

    self.mirrorHintLabel = [NSTextField wrappingLabelWithString:@"系统通知左侧图标为本应用（MeoBrowser）；来源看标题前缀（如「微信 · …」）。手机端需在 Companion 选择「全部通知」。"];
    self.mirrorHintLabel.font = [NSFont systemFontOfSize:11];
    self.mirrorHintLabel.textColor = [NSColor secondaryLabelColor];
    self.mirrorHintLabel.preferredMaxLayoutWidth = 420;

    NSView *mirrorCard = [self makeSettingsCardWithTitle:@"通知镜像"
                                        arrangedSubviews:@[
                                            self.mirrorEnabledCheck,
                                            self.otpBannerEnabledCheck,
                                            self.openNotificationSettingsButton,
                                            self.mirrorHintLabel,
                                        ]];

    CompanionSyncSettings *syncSettings = [CompanionSyncSettings sharedSettings];
    self.syncEnabledCheck = [NSButton checkboxWithTitle:@"启用与 Android 的自动同步（局域网）"
                                                 target:self
                                                 action:@selector(syncSettingsChanged:)];
    self.syncEnabledCheck.state = syncSettings.syncEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncShortcutsCheck = [NSButton checkboxWithTitle:@"同步新标签页快捷方式"
                                                   target:self
                                                   action:@selector(syncSettingsChanged:)];
    self.syncShortcutsCheck.state = syncSettings.syncShortcuts ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncHistoryCheck = [NSButton checkboxWithTitle:@"同步历史（明文 LAN）"
                                                 target:self
                                                 action:@selector(syncSettingsChanged:)];
    self.syncHistoryCheck.state = syncSettings.syncHistory ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncBookmarksCheck = [NSButton checkboxWithTitle:@"同步书签"
                                                   target:self
                                                   action:@selector(syncSettingsChanged:)];
    self.syncBookmarksCheck.state = syncSettings.syncBookmarks ? NSControlStateValueOn : NSControlStateValueOff;

    NSTextField *privacyNote = [NSTextField wrappingLabelWithString:@"默认：Android 仅上传验证码与时间戳。手机开启「全部通知」后会上传通知标题与正文（同局域网明文）。同步开启后会交换快捷方式等数据。端口默认固定，仅手动确认后才会更换。"];
    privacyNote.font = [NSFont systemFontOfSize:11];
    privacyNote.textColor = [NSColor secondaryLabelColor];
    privacyNote.preferredMaxLayoutWidth = 420;

    NSView *syncCard = [self makeSettingsCardWithTitle:@"局域网同步"
                                      arrangedSubviews:@[
                                          self.syncEnabledCheck,
                                          self.syncShortcutsCheck,
                                          self.syncHistoryCheck,
                                          self.syncBookmarksCheck,
                                          privacyNote,
                                      ]];

    NSTextField *recipeSectionTitle = [NSTextField labelWithString:@"登录配置"];
    recipeSectionTitle.font = [NSFont boldSystemFontOfSize:13];

    NSStackView *modeRow = [NSStackView stackViewWithViews:@[
        ({
            NSTextField *c = [self caption:@"登录方式"];
            c.translatesAutoresizingMaskIntoConstraints = NO;
            [c.widthAnchor constraintEqualToConstant:88].active = YES;
            c;
        }),
        self.modePopup
    ]];
    modeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    modeRow.alignment = NSLayoutAttributeCenterY;
    modeRow.spacing = 8;

    NSView *recipeCard = [self makeSettingsCardWithTitle:nil
                                        arrangedSubviews:@[
                                            [self labeledRow:@"名称" field:self.titleField pickAction:nil],
                                            [self labeledRow:@"主机" field:self.hostField pickAction:nil],
                                            [self labeledRow:@"路径前缀" field:self.pathPrefixField pickAction:nil],
                                            modeRow,
                                            [self labeledRow:@"用户名" field:self.usernameField pickAction:nil],
                                            [self labeledRow:@"密码" field:self.passwordField pickAction:nil],
                                            [self labeledRow:@"手机号" field:self.phoneField pickAction:nil],
                                            [self labeledRow:@"用户名选择器" field:self.usernameSelectorField pickAction:@selector(pickUsernameSelector:)],
                                            [self labeledRow:@"密码选择器" field:self.passwordSelectorField pickAction:@selector(pickPasswordSelector:)],
                                            [self labeledRow:@"手机号选择器" field:self.phoneSelectorField pickAction:@selector(pickPhoneSelector:)],
                                            [self labeledRow:@"验证码选择器" field:self.otpSelectorField pickAction:@selector(pickOTPSelector:)],
                                            [self labeledRow:@"发码按钮" field:self.sendCodeSelectorField pickAction:@selector(pickSendCodeSelector:)],
                                            [self labeledRow:@"提交选择器" field:self.submitSelectorField pickAction:@selector(pickSubmitSelector:)],
                                            self.submitByEnterCheck,
                                            self.autoLoginCheck,
                                            self.defaultCheck,
                                            saveButton,
                                            self.inlineAssistCheck,
                                            self.promptSaveCheck,
                                            self.statusLabel,
                                        ]];

    NSStackView *form = [NSStackView stackViewWithViews:@[
        self.companionStatusCard,
        authCard,
        mirrorCard,
        syncCard,
        recipeSectionTitle,
        recipeCard,
    ]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 12;
    form.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *row in form.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:form.widthAnchor].active = YES;
    }

    NSScrollView *formScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    formScroll.translatesAutoresizingMaskIntoConstraints = NO;
    formScroll.hasVerticalScroller = YES;
    formScroll.borderType = NSNoBorder;
    formScroll.drawsBackground = NO;
    self.formScrollView = formScroll;
    NSView *formDocument = [[NSView alloc] initWithFrame:NSZeroRect];
    formDocument.translatesAutoresizingMaskIntoConstraints = NO;
    [formDocument addSubview:form];
    [NSLayoutConstraint activateConstraints:@[
        [form.topAnchor constraintEqualToAnchor:formDocument.topAnchor],
        [form.leadingAnchor constraintEqualToAnchor:formDocument.leadingAnchor],
        [form.trailingAnchor constraintEqualToAnchor:formDocument.trailingAnchor],
        [form.bottomAnchor constraintEqualToAnchor:formDocument.bottomAnchor],
        [form.widthAnchor constraintEqualToConstant:460],
    ]];
    formScroll.documentView = formDocument;

    NSStackView *root = [NSStackView stackViewWithViews:@[listColumn, formScroll]];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.alignment = NSLayoutAttributeTop;
    root.spacing = 16;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [listColumn.widthAnchor constraintEqualToConstant:220],
        [formScroll.widthAnchor constraintGreaterThanOrEqualToConstant:480],
    ]];

    [self reloadRecipes];
    [self clearForm];
    [self refreshCompanionUI];
}

- (void)reloadRecipes {
    self.recipes = [[LoginRecipeStore sharedStore] allRecipes];
    [self.tableView reloadData];
}

- (void)revealCompanionSection {
    [self refreshCompanionUI];
    NSView *card = self.companionStatusCard;
    if (!card) {
        return;
    }
    [self.window layoutIfNeeded];
    [card scrollRectToVisible:NSInsetRect(card.bounds, 0, -8)];

    CALayer *layer = card.layer;
    if (!layer) {
        return;
    }
    CGColorRef previous = layer.borderColor;
    CGFloat previousWidth = layer.borderWidth;
    if (@available(macOS 10.14, *)) {
        layer.borderColor = [NSColor controlAccentColor].CGColor;
    } else {
        layer.borderColor = [NSColor selectedControlColor].CGColor;
    }
    layer.borderWidth = 2.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        layer.borderColor = previous;
        layer.borderWidth = previousWidth;
    });
}

- (NSView *)makeSettingsCardWithTitle:(NSString *)title arrangedSubviews:(NSArray<NSView *> *)views {
    NSMutableArray<NSView *> *parts = [NSMutableArray array];
    if (title.length > 0) {
        NSTextField *titleLabel = [NSTextField labelWithString:title];
        titleLabel.font = [NSFont boldSystemFontOfSize:13];
        [parts addObject:titleLabel];
    }
    if (views.count > 0) {
        [parts addObjectsFromArray:views];
    }
    NSStackView *inner = [NSStackView stackViewWithViews:parts];
    inner.orientation = NSUserInterfaceLayoutOrientationVertical;
    inner.alignment = NSLayoutAttributeLeading;
    inner.spacing = 8;
    inner.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    inner.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *row in inner.arrangedSubviews) {
        if ([row isKindOfClass:[NSStackView class]] || [row isKindOfClass:[NSTextField class]]) {
            [row setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                            forOrientation:NSLayoutConstraintOrientationVertical];
        }
    }

    NSView *card = [[NSView alloc] initWithFrame:NSZeroRect];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 10.0;
    if (@available(macOS 10.14, *)) {
        card.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        card.layer.borderColor = [[NSColor separatorColor] colorWithAlphaComponent:0.35].CGColor;
    } else {
        card.layer.backgroundColor = [NSColor whiteColor].CGColor;
        card.layer.borderColor = [[NSColor blackColor] colorWithAlphaComponent:0.08].CGColor;
    }
    card.layer.borderWidth = 1.0;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor],
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];
    return card;
}

- (void)selectRecipeID:(NSString *)recipeID {
    [self reloadRecipes];
    for (NSInteger i = 0; i < (NSInteger)self.recipes.count; i++) {
        if ([self.recipes[i].recipeID isEqualToString:recipeID]) {
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self loadRecipeIntoForm:self.recipes[i]];
            return;
        }
    }
}

- (void)clearForm {
    self.editingRecipeID = nil;
    self.titleField.stringValue = @"";
    self.hostField.stringValue = @"";
    self.pathPrefixField.stringValue = @"";
    [self.modePopup selectItemAtIndex:0];
    self.usernameField.stringValue = @"";
    self.passwordField.stringValue = @"";
    self.phoneField.stringValue = @"";
    self.usernameSelectorField.stringValue = @"input[type=\"text\"], input[type=\"email\"], input[name=\"username\"]";
    self.passwordSelectorField.stringValue = @"input[type=\"password\"]";
    self.phoneSelectorField.stringValue = @"input[type=\"tel\"], input[name*=\"phone\"], input[autocomplete=\"tel\"]";
    self.otpSelectorField.stringValue = @"input[autocomplete=\"one-time-code\"], input[name*=\"otp\"], input[name*=\"code\"]";
    self.sendCodeSelectorField.stringValue = @"";
    self.submitSelectorField.stringValue = @"button[type=\"submit\"], input[type=\"submit\"]";
    self.submitByEnterCheck.state = NSControlStateValueOn;
    self.autoLoginCheck.state = NSControlStateValueOff;
    self.defaultCheck.state = NSControlStateValueOff;
    self.submitSelectorField.enabled = NO;
    self.statusLabel.stringValue = @"凭证保存在本地钥匙串；清除「网站数据」不会删除登录配置。";
    [self updateSMSFieldsEnabled];
}

- (LoginRecipeMode)selectedMode {
    switch (self.modePopup.indexOfSelectedItem) {
        case 1: return LoginRecipeModeSMSOTP;
        case 2: return LoginRecipeModeHybrid;
        default: return LoginRecipeModePassword;
    }
}

- (void)selectMode:(LoginRecipeMode)mode {
    if ([mode isEqualToString:LoginRecipeModeSMSOTP]) {
        [self.modePopup selectItemAtIndex:1];
    } else if ([mode isEqualToString:LoginRecipeModeHybrid]) {
        [self.modePopup selectItemAtIndex:2];
    } else {
        [self.modePopup selectItemAtIndex:0];
    }
    [self updateSMSFieldsEnabled];
}

- (void)modeChanged:(id)sender {
    (void)sender;
    [self updateSMSFieldsEnabled];
    // 纯短信登录页没有账密框：清空默认密码选择器，避免 waitFor 超时。
    if ([[self selectedMode] isEqualToString:LoginRecipeModeSMSOTP]) {
        self.usernameSelectorField.stringValue = @"";
        self.passwordSelectorField.stringValue = @"";
        self.usernameField.stringValue = @"";
        self.passwordField.stringValue = @"";
        if (self.phoneSelectorField.stringValue.length == 0) {
            self.phoneSelectorField.stringValue = @"input[type=\"tel\"], input[name*=\"phone\"], input[autocomplete=\"tel\"]";
        }
        if (self.otpSelectorField.stringValue.length == 0) {
            self.otpSelectorField.stringValue = @"input[autocomplete=\"one-time-code\"], input[name*=\"otp\"], input[name*=\"code\"], input[placeholder*=\"验证码\"]";
        }
        self.statusLabel.stringValue = @"已切换为「短信验证码」：请拾取手机号、验证码、发码按钮；可不填用户名密码。";
    }
}

- (void)updateSMSFieldsEnabled {
    BOOL sms = ![self.selectedMode isEqualToString:LoginRecipeModePassword];
    self.phoneField.enabled = sms;
    self.phoneSelectorField.enabled = sms;
    self.otpSelectorField.enabled = sms;
    self.sendCodeSelectorField.enabled = sms;
}

- (void)loadRecipeIntoForm:(LoginRecipe *)recipe {
    self.editingRecipeID = recipe.recipeID;
    self.titleField.stringValue = recipe.title ?: @"";
    self.hostField.stringValue = recipe.host ?: @"";
    self.pathPrefixField.stringValue = recipe.pathPrefix ?: @"";
    [self selectMode:recipe.mode ?: LoginRecipeModePassword];
    self.usernameSelectorField.stringValue = recipe.usernameSelector ?: @"";
    self.passwordSelectorField.stringValue = recipe.passwordSelector ?: @"";
    self.phoneSelectorField.stringValue = recipe.phoneSelector ?: @"";
    self.otpSelectorField.stringValue = recipe.otpSelector ?: @"";
    self.sendCodeSelectorField.stringValue = recipe.sendCodeSelector ?: @"";
    self.submitSelectorField.stringValue = recipe.submitSelector ?: @"";
    self.submitByEnterCheck.state = recipe.submitByEnter ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoLoginCheck.state = recipe.autoLogin ? NSControlStateValueOn : NSControlStateValueOff;
    self.defaultCheck.state = recipe.isDefault ? NSControlStateValueOn : NSControlStateValueOff;
    self.submitSelectorField.enabled = !recipe.submitByEnter;

    LoginCredentials *credentials = [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID error:nil];
    self.usernameField.stringValue = credentials.username ?: @"";
    self.passwordField.stringValue = credentials.password ?: @"";
    self.phoneField.stringValue = credentials.phone ?: @"";
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.recipes.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    NSString *identifier = @"LoginAssistCell";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;
        NSTextField *text = [NSTextField labelWithString:@""];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:text];
        cell.textField = text;
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    if (row >= 0 && row < (NSInteger)self.recipes.count) {
        LoginRecipe *recipe = self.recipes[row];
        NSString *title = recipe.title.length > 0 ? recipe.title : recipe.host;
        if (recipe.autoLogin) {
            title = [title stringByAppendingString:@" ⚡"];
        }
        cell.textField.stringValue = title;
    }
    return cell;
}

- (void)tableSelectionChanged:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.recipes.count) {
        return;
    }
    [self loadRecipeIntoForm:self.recipes[row]];
}

- (void)submitModeChanged:(id)sender {
    (void)sender;
    self.submitSelectorField.enabled = (self.submitByEnterCheck.state != NSControlStateValueOn);
}

- (void)prefsChanged:(id)sender {
    (void)sender;
    [LoginAssistPreferences setInlineAssistEnabled:(self.inlineAssistCheck.state == NSControlStateValueOn)];
    [LoginAssistPreferences setPromptSaveOnSuccess:(self.promptSaveCheck.state == NSControlStateValueOn)];
    self.statusLabel.stringValue = @"偏好已保存。内联图标开关对新建标签 / 新导航后的页面生效。";
}

- (void)addRecipe:(id)sender {
    (void)sender;
    [self.tableView deselectAll:nil];
    [self clearForm];
    NSURL *url = self.pickerHost.activeWebViewForPicking.URL;
    if (url.isFileURL) {
        self.hostField.stringValue = @"file";
        self.titleField.stringValue = @"本地测试页";
        if ([url.path.lastPathComponent length] > 0) {
            self.pathPrefixField.stringValue = url.path.lastPathComponent;
        }
    } else if (url.host.length > 0) {
        self.hostField.stringValue = url.host.lowercaseString;
        self.titleField.stringValue = url.host;
    }
    self.statusLabel.stringValue = @"填写后点击保存以创建配置。";
}

- (void)deleteRecipe:(id)sender {
    (void)sender;
    NSString *recipeID = self.editingRecipeID;
    if (recipeID.length == 0) {
        NSInteger row = self.tableView.selectedRow;
        if (row >= 0 && row < (NSInteger)self.recipes.count) {
            recipeID = self.recipes[row].recipeID;
        }
    }
    if (recipeID.length == 0) {
        return;
    }
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"删除此登录配置？";
    confirm.informativeText = @"将同时删除钥匙串中的账号密码。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"删除"];
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertFirstButtonReturn) {
            return;
        }
        [[LoginRecipeStore sharedStore] deleteRecipeWithID:recipeID error:nil];
        [weakSelf clearForm];
        [weakSelf reloadRecipes];
    }];
}

- (void)saveRecipe:(id)sender {
    (void)sender;
    NSString *host = [self.hostField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (host.length == 0) {
        self.statusLabel.stringValue = @"请填写主机名（如 example.com）。";
        return;
    }
    LoginRecipe *recipe = nil;
    if (self.editingRecipeID.length > 0) {
        recipe = [[[LoginRecipeStore sharedStore] recipeWithID:self.editingRecipeID] copy];
    }
    if (!recipe) {
        recipe = [LoginRecipe recipeWithHost:host title:self.titleField.stringValue];
    }
    recipe.title = self.titleField.stringValue.length > 0 ? self.titleField.stringValue : host;
    recipe.host = host;
    NSString *path = [self.pathPrefixField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    recipe.pathPrefix = path.length > 0 ? path : nil;
    recipe.usernameSelector = self.usernameSelectorField.stringValue;
    recipe.passwordSelector = self.passwordSelectorField.stringValue;
    recipe.submitSelector = self.submitSelectorField.stringValue;
    recipe.submitByEnter = (self.submitByEnterCheck.state == NSControlStateValueOn);
    recipe.autoLogin = (self.autoLoginCheck.state == NSControlStateValueOn);
    recipe.isDefault = (self.defaultCheck.state == NSControlStateValueOn);
    recipe.mode = [self selectedMode];
    recipe.phoneSelector = self.phoneSelectorField.stringValue;
    recipe.otpSelector = self.otpSelectorField.stringValue;
    recipe.sendCodeSelector = self.sendCodeSelectorField.stringValue;
    if ([recipe requiresOTPWait] && recipe.otpSelector.length == 0) {
        self.statusLabel.stringValue = @"短信/混合模式请配置验证码选择器。";
        return;
    }
    if ([recipe.mode isEqualToString:LoginRecipeModeSMSOTP]) {
        if (recipe.phoneSelector.length == 0) {
            self.statusLabel.stringValue = @"短信登录请配置手机号选择器，并填写手机号。";
            return;
        }
        if (self.phoneField.stringValue.length == 0) {
            self.statusLabel.stringValue = @"请填写要登录的手机号。";
            return;
        }
        // 避免残留默认密码选择器拖垮执行
        recipe.usernameSelector = @"";
        recipe.passwordSelector = @"";
    }

    NSError *error = nil;
    if (![[LoginRecipeStore sharedStore] upsertRecipe:recipe error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存失败";
        return;
    }
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = self.usernameField.stringValue;
    credentials.password = self.passwordField.stringValue;
    credentials.phone = self.phoneField.stringValue;
    if (![[LoginCredentialStore sharedStore] saveCredentials:credentials
                                                 forRecipeID:recipe.recipeID
                                                       error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"凭证保存失败";
        return;
    }
    self.editingRecipeID = recipe.recipeID;
    [self reloadRecipes];
    [self selectRecipeID:recipe.recipeID];
    self.statusLabel.stringValue = @"已保存。";
}

- (void)pickUsernameSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"username"];
}

- (void)pickPasswordSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"password"];
}

- (void)pickPhoneSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"phone"];
}

- (void)pickOTPSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"otp"];
}

- (void)pickSendCodeSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"send"];
}

- (void)pickSubmitSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"submit"];
}

- (void)beginPickForTarget:(NSString *)target {
    WKWebView *webView = [self.pickerHost activeWebViewForPicking];
    if (!webView) {
        self.statusLabel.stringValue = @"请先在浏览器中打开要配置的登录页。";
        return;
    }
    self.pickingTarget = target;
    self.statusLabel.stringValue = @"在页面上点击目标元素；按 Esc 取消。";
    [self.window orderBack:nil];
    __weak typeof(self) weakSelf = self;
    [LoginElementPicker startPickingInWebView:webView completion:^(NSString *cssSelector, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.window makeKeyAndOrderFront:nil];
        if (cancelled || cssSelector.length == 0) {
            strongSelf.statusLabel.stringValue = @"已取消拾取。";
            return;
        }
        if ([strongSelf.pickingTarget isEqualToString:@"username"]) {
            strongSelf.usernameSelectorField.stringValue = cssSelector;
        } else if ([strongSelf.pickingTarget isEqualToString:@"password"]) {
            strongSelf.passwordSelectorField.stringValue = cssSelector;
        } else if ([strongSelf.pickingTarget isEqualToString:@"phone"]) {
            strongSelf.phoneSelectorField.stringValue = cssSelector;
        } else if ([strongSelf.pickingTarget isEqualToString:@"otp"]) {
            strongSelf.otpSelectorField.stringValue = cssSelector;
        } else if ([strongSelf.pickingTarget isEqualToString:@"send"]) {
            strongSelf.sendCodeSelectorField.stringValue = cssSelector;
        } else if ([strongSelf.pickingTarget isEqualToString:@"submit"]) {
            strongSelf.submitSelectorField.stringValue = cssSelector;
        }
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
        strongSelf.pickingTarget = nil;
    }];
}

- (void)showWindow:(id)sender {
    [self reloadRecipes];
    [self refreshCompanionUI];
    [super showWindow:sender];
}

- (void)companionStateDidChange:(NSNotification *)note {
    (void)note;
    [self refreshCompanionUI];
}

- (void)refreshCompanionUI {
    CompanionChannel *channel = [CompanionChannel sharedChannel];
    if (channel.state == CompanionChannelStateStopped) {
        [channel start];
    }

    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    BOOL securityMode = (store.authMode == CompanionAuthModeSecurityCode);
    self.companionAuthModeControl.selectedSegment = securityMode ? 1 : 0;
    self.pairingModeStack.hidden = securityMode;
    self.securityModeStack.hidden = !securityMode;
    if (securityMode && store.securityCode.length > 0 && self.securityCodeField.stringValue.length == 0) {
        self.securityCodeField.stringValue = store.securityCode;
    }

    BOOL connected = (channel.state == CompanionChannelStateConnected);
    NSUInteger paired = store.pairedDevices.count;
    CompanionLinkUIState uiState = [CompanionLinkUI stateFromChannel:channel];
    self.companionConnectionLabel.stringValue = [CompanionLinkUI titleForState:uiState];
    self.companionConnectionLabel.textColor = [NSColor labelColor];
    NSColor *dotColor = [CompanionLinkUI dotColorForState:uiState];
    self.companionStatusDotView.layer.backgroundColor = dotColor.CGColor;
    if (@available(macOS 10.14, *)) {
        self.companionStatusDotView.layer.borderWidth = 1.5;
        self.companionStatusDotView.layer.borderColor = [NSColor controlBackgroundColor].CGColor;
    }
    self.companionStatusIconBg.layer.backgroundColor = [CompanionLinkUI iconBackgroundColorForState:uiState].CGColor;

    if (connected) {
        self.companionHintLabel.stringValue = paired > 1
            ? [NSString stringWithFormat:@"手机已在线推码。另有 %lu 台曾配对设备。", (unsigned long)paired]
            : @"手机已在线，验证码会自动推送到本浏览器。";
    } else if (channel.usingTemporaryPort) {
        self.companionHintLabel.stringValue =
            [NSString stringWithFormat:@"固定端口被占用，当前临时使用 %ld。点「更换端口…」确认采用新端口，或关闭占用后重启浏览器。",
             (long)channel.listeningPort];
    } else if (securityMode) {
        self.companionHintLabel.stringValue = store.securityCode.length > 0
            ? @"安全码模式：手机 Companion 选「固定安全码」并保存后，打开即可自动连接。"
            : @"请先设定并保存固定安全码，再在手机 Companion 选择相同模式。";
    } else {
        self.companionHintLabel.stringValue = paired > 0
            ? @"等待手机连接。可点配对码复制，或点「刷新配对码」给新设备。"
            : @"请在手机 Companion 输入下方配对码，或填写主机地址手动连接。";
    }

    NSString *endpoint = [channel preferredLANEndpoint] ?: @"—";
    self.displayedEndpoint = ([endpoint isEqualToString:@"—"] || [endpoint containsString:@"未检测到"]) ? nil : endpoint;
    NSString *portNote = channel.usingTemporaryPort ? @"（临时）" : @"（固定）";
    self.companionEndpointButton.title = [NSString stringWithFormat:@"主机：%@%@", endpoint, portNote];

    if (securityMode) {
        self.displayedPairingCode = store.securityCode;
        return;
    }

    // 未连接：显著显示配对码；已连接：不显示「已配对」占位，仅在有有效码时展示，并保留刷新
    NSString *code = [channel ensurePairingCode];
    BOOL hasUsableCode = (code.length > 0 && ![code isEqualToString:@"------"]);
    if (!connected && !hasUsableCode) {
        code = [channel refreshPairingCodeForNewDevice];
        hasUsableCode = code.length > 0;
    }
    self.displayedPairingCode = hasUsableCode ? code : nil;

    if (!connected) {
        self.pairingCodeCaption.stringValue = @"配对码（点击可复制）";
        self.pairingCodeCaption.hidden = NO;
        self.pairingRow.hidden = NO;
        self.pairingCodeButton.hidden = NO;
        self.pairingCodeButton.title = hasUsableCode ? code : @"----";
        self.refreshPairingButton.hidden = NO;
    } else {
        self.pairingCodeCaption.stringValue = hasUsableCode
            ? @"当前配对码（点击可复制；新设备请刷新）"
            : @"新手机配对时，点「刷新配对码」";
        self.pairingCodeCaption.hidden = NO;
        self.pairingRow.hidden = NO;
        self.pairingCodeButton.hidden = !hasUsableCode;
        if (hasUsableCode) {
            self.pairingCodeButton.title = code;
        }
        self.refreshPairingButton.hidden = NO;
    }

    PhoneNotificationSettings *mirrorSettings = [PhoneNotificationSettings sharedSettings];
    self.mirrorEnabledCheck.state = mirrorSettings.mirrorEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.otpBannerEnabledCheck.state = mirrorSettings.otpBannerEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    CompanionSyncSettings *syncSettings = [CompanionSyncSettings sharedSettings];
    self.syncEnabledCheck.state = syncSettings.syncEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncShortcutsCheck.state = syncSettings.syncShortcuts ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncHistoryCheck.state = syncSettings.syncHistory ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncBookmarksCheck.state = syncSettings.syncBookmarks ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshNotificationPermissionHint];
}

- (void)mirrorSettingsChanged:(id)sender {
    (void)sender;
    PhoneNotificationSettings *settings = [PhoneNotificationSettings sharedSettings];
    settings.mirrorEnabled = (self.mirrorEnabledCheck.state == NSControlStateValueOn);
    settings.otpBannerEnabled = (self.otpBannerEnabledCheck.state == NSControlStateValueOn);
    [[PhoneNotificationPresenter sharedPresenter] requestAuthorizationIfNeeded];
    [self refreshNotificationPermissionHint];
}

- (void)syncSettingsChanged:(id)sender {
    (void)sender;
    CompanionSyncSettings *settings = [CompanionSyncSettings sharedSettings];
    settings.syncEnabled = (self.syncEnabledCheck.state == NSControlStateValueOn);
    settings.syncShortcuts = (self.syncShortcutsCheck.state == NSControlStateValueOn);
    settings.syncHistory = (self.syncHistoryCheck.state == NSControlStateValueOn);
    settings.syncBookmarks = (self.syncBookmarksCheck.state == NSControlStateValueOn);
}

- (void)refreshNotificationPermissionHint {
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            dispatch_async(dispatch_get_main_queue(), ^{
                switch (settings.authorizationStatus) {
                    case UNAuthorizationStatusAuthorized:
                    case UNAuthorizationStatusProvisional:
                        self.mirrorHintLabel.stringValue =
                            @"系统通知已授权。左侧图标为本应用；来源看标题前缀。手机端需选择「全部通知」。";
                        break;
                    case UNAuthorizationStatusDenied:
                        self.mirrorHintLabel.stringValue =
                            @"系统通知权限已关闭：镜像不会弹出，验证码填入仍可用。请点「打开系统通知设置…」开启。";
                        break;
                    default:
                        self.mirrorHintLabel.stringValue =
                            @"尚未授权系统通知。勾选上方选项或点「打开系统通知设置…」后，首次镜像时会弹出授权。";
                        break;
                }
            });
        }];
    }
}

- (void)openSystemNotificationSettings:(id)sender {
    (void)sender;
    NSURL *url = nil;
    if (@available(macOS 13.0, *)) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Notifications-Settings.extension"];
    }
    if (!url) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
    }
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)companionAuthModeChanged:(id)sender {
    (void)sender;
    CompanionAuthMode mode = (self.companionAuthModeControl.selectedSegment == 1)
        ? CompanionAuthModeSecurityCode
        : CompanionAuthModePairingCode;
    [CompanionPairingStore sharedStore].authMode = mode;
    if (mode == CompanionAuthModeSecurityCode) {
        self.statusLabel.stringValue = @"已切换为固定安全码模式。请设定安全码，手机端同步选择该模式。";
    } else {
        self.statusLabel.stringValue = @"已切换为临时配对码模式。";
        (void)[[CompanionChannel sharedChannel] ensurePairingCode];
    }
    [self refreshCompanionUI];
}

- (void)saveSecurityCode:(id)sender {
    (void)sender;
    NSError *error = nil;
    NSString *code = self.securityCodeField.stringValue;
    if (![[CompanionPairingStore sharedStore] setSecurityCode:code error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存安全码失败";
        return;
    }
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    store.authMode = CompanionAuthModeSecurityCode;
    self.companionAuthModeControl.selectedSegment = 1;
    if (store.securityCode.length == 0) {
        self.statusLabel.stringValue = @"已清除安全码。";
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已保存固定安全码（%lu 位）。手机 Companion 选「固定安全码」后可自动连接。",
                                        (unsigned long)store.securityCode.length];
    }
    [self refreshCompanionUI];
}

- (void)changeCompanionPort:(id)sender {
    (void)sender;
    CompanionChannel *channel = [CompanionChannel sharedChannel];
    NSInteger sticky = [CompanionPairingStore sharedStore].stickyListeningPort;
    NSString *message = sticky > 0
        ? [NSString stringWithFormat:
           @"当前固定端口为 %ld。\n\n更换后将重新分配端口并固定下来，手机需更新「主机 IP:端口」。确定更换？",
           (long)sticky]
        : @"将重新分配并固定监听端口。手机需使用新的「主机 IP:端口」。确定？";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"更换 Companion 端口";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"更换"];
    [alert addButtonWithTitle:@"取消"];
    if (channel.usingTemporaryPort && channel.listeningPort > 0) {
        [alert addButtonWithTitle:@"采用当前临时端口"];
    }
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [[CompanionChannel sharedChannel] restartListeningClearingStickyPort:YES];
        self.statusLabel.stringValue = @"正在更换端口…完成后请复制新主机地址到手机。";
    } else if (response == NSAlertThirdButtonReturn) {
        // 将当前临时端口确认为固定端口
        NSInteger temp = channel.listeningPort;
        if (temp > 0) {
            [CompanionPairingStore sharedStore].stickyListeningPort = temp;
            [[CompanionChannel sharedChannel] restartListeningClearingStickyPort:NO];
            self.statusLabel.stringValue = [NSString stringWithFormat:@"已将端口 %ld 设为固定端口。", (long)temp];
        }
    }
    [self refreshCompanionUI];
}

- (void)copyPairingCode:(id)sender {
    (void)sender;
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    if (store.authMode == CompanionAuthModeSecurityCode) {
        NSString *code = store.securityCode;
        if (code.length == 0) {
            self.statusLabel.stringValue = @"尚未设定安全码。";
            return;
        }
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb setString:code forType:NSPasteboardTypeString];
        self.statusLabel.stringValue = @"已复制安全码到剪贴板";
        return;
    }
    NSString *code = self.displayedPairingCode;
    if (code.length == 0) {
        code = [[CompanionChannel sharedChannel] ensurePairingCode];
    }
    if (code.length == 0 || [code isEqualToString:@"------"]) {
        self.statusLabel.stringValue = @"暂无配对码，请先点「刷新配对码」。";
        return;
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:code forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已复制配对码 %@ 到剪贴板", code];
}

- (void)copyCompanionEndpoint:(id)sender {
    (void)sender;
    NSString *endpoint = self.displayedEndpoint;
    if (endpoint.length == 0) {
        endpoint = [[CompanionChannel sharedChannel] preferredLANEndpoint];
    }
    if (endpoint.length == 0) {
        self.statusLabel.stringValue = @"暂无可用主机地址。";
        return;
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:endpoint forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已复制主机地址 %@ 到剪贴板", endpoint];
}

- (void)refreshPairingCode:(id)sender {
    (void)sender;
    if ([CompanionPairingStore sharedStore].authMode == CompanionAuthModeSecurityCode) {
        self.statusLabel.stringValue = @"当前为安全码模式，请直接修改并保存安全码。";
        return;
    }
    NSString *code = [[CompanionChannel sharedChannel] refreshPairingCodeForNewDevice];
    self.displayedPairingCode = code;
    self.pairingCodeButton.hidden = NO;
    self.pairingCodeButton.title = code.length > 0 ? code : @"----";
    self.pairingRow.hidden = NO;
    // 刷新后直接复制，方便贴到手机
    if (code.length > 0) {
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb setString:code forType:NSPasteboardTypeString];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已刷新并复制配对码 %@（5 分钟内有效）", code];
    } else {
        self.statusLabel.stringValue = @"刷新配对码失败。";
    }
    [self refreshCompanionUI];
}

- (void)revokeCompanionDevices:(id)sender {
    (void)sender;
    [[CompanionPairingStore sharedStore] revokeAllDevices];
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    if (store.authMode == CompanionAuthModeSecurityCode) {
        self.statusLabel.stringValue = store.securityCode.length > 0
            ? @"已注销设备。安全码仍有效，手机可再次用安全码连接。"
            : @"已注销全部配对设备。";
        [self refreshCompanionUI];
        return;
    }
    NSString *code = [[CompanionChannel sharedChannel] refreshPairingCodeForNewDevice];
    if (code.length > 0) {
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb setString:code forType:NSPasteboardTypeString];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已注销设备，新配对码 %@ 已复制", code];
    } else {
        self.statusLabel.stringValue = @"已注销全部配对设备，请刷新配对码。";
    }
    [self refreshCompanionUI];
}

@end
