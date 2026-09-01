#import "BrowserLoginAssistSettingsWindowController.h"
#import "LoginAssistController.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginElementPicker.h"
#import "LoginAssistPreferences.h"
#import "FormMemo.h"
#import "FormMemoStore.h"
#import "FormMemoPreferences.h"
#import "CompanionChannel.h"
#import "CompanionPairingStore.h"
#import "CompanionLinkUI.h"
#import "PhoneNotificationSettings.h"
#import "PhoneNotificationInboxSettings.h"
#import "PhoneNotificationInboxStore.h"
#import "CallAlertSettings.h"
#import "CallAlertPresenter.h"
#import "CompanionSyncSettings.h"
#import "PhoneNotificationPresenter.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import "SBTextView.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>

typedef NS_ENUM(NSInteger, BrowserLoginAssistSettingsMode) {
    BrowserLoginAssistSettingsModeRecipes = 0,
    BrowserLoginAssistSettingsModeMemos = 1,
};

@interface BrowserLoginAssistSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong) NSSegmentedControl *sectionControl;
@property (nonatomic, assign) BrowserLoginAssistSettingsMode settingsMode;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<LoginRecipe *> *recipes;
@property (nonatomic, strong) NSArray<FormMemo *> *memos;
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
@property (nonatomic, strong) NSButton *perFieldInlineCheck;
@property (nonatomic, strong) NSButton *extraFieldInlineCheck;
@property (nonatomic, strong) NSButton *focusInlineCheck;
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
@property (nonatomic, strong) NSButton *invitePhoneButton;
@property (nonatomic, strong) NSTextField *companionHintLabel;
@property (nonatomic, strong) NSButton *mirrorEnabledCheck;
@property (nonatomic, strong) NSButton *otpBannerEnabledCheck;
@property (nonatomic, strong) NSButton *inboxEnabledCheck;
@property (nonatomic, strong) NSButton *otpToInboxCheck;
@property (nonatomic, strong) NSButton *autoMarkReadCheck;
@property (nonatomic, strong) NSButton *wechatReplyEnabledCheck;
@property (nonatomic, strong) NSPopUpButton *inboxRetentionPopup;
@property (nonatomic, strong) NSButton *purgeInboxButton;
@property (nonatomic, strong) NSButton *openNotificationSettingsButton;
@property (nonatomic, strong) NSTextField *mirrorHintLabel;
@property (nonatomic, strong) NSButton *callAlertEnabledCheck;
@property (nonatomic, strong) NSButton *callAlertBannerCheck;
@property (nonatomic, strong) NSButton *callAlertSystemNotifCheck;
@property (nonatomic, strong) NSTextField *callAlertHintLabel;
@property (nonatomic, strong) NSButton *syncEnabledCheck;
@property (nonatomic, strong) NSButton *syncShortcutsCheck;
@property (nonatomic, strong) NSButton *syncHistoryCheck;
@property (nonatomic, strong) NSButton *syncBookmarksCheck;
@property (nonatomic, strong) NSScrollView *formScrollView;
@property (nonatomic, strong) NSView *recipeCard;
@property (nonatomic, strong) NSView *memoCard;
@property (nonatomic, strong) NSTextField *recipeSectionTitle;
@property (nonatomic, strong) NSTextField *memoSectionTitle;
@property (nonatomic, strong) SBTextField *memoTitleField;
@property (nonatomic, strong) SBTextField *memoHostField;
@property (nonatomic, strong) SBTextField *memoPathPrefixField;
@property (nonatomic, strong) NSButton *memoDefaultCheck;
@property (nonatomic, strong) NSTableView *memoFieldsTable;
@property (nonatomic, strong) NSMutableArray<FormMemoField *> *editingMemoFields;
@property (nonatomic, strong) SBTextField *memoFieldLabelField;
@property (nonatomic, strong) SBTextField *memoFieldSelectorField;
@property (nonatomic, strong) SBTextView *memoFieldValueView;
@property (nonatomic, strong) NSScrollView *memoFieldValueScroll;
@property (nonatomic, strong) NSButton *memoFieldEnabledCheck;
@property (nonatomic, strong) NSTextField *memoStatusLabel;
@property (nonatomic, strong) NSButton *memoInlineSaveCheck;
@property (nonatomic, copy, nullable) NSString *editingRecipeID;
@property (nonatomic, copy, nullable) NSString *editingMemoID;
@property (nonatomic, copy, nullable) NSString *pickingTarget;
@property (nonatomic, copy, nullable) NSString *displayedPairingCode;
@property (nonatomic, copy, nullable) NSString *displayedEndpoint;
@property (nonatomic, strong, nullable) NSTimer *companionStatusTimer;
@property (nonatomic, assign) BOOL refreshingCompanionUI;
@end

@implementation BrowserLoginAssistSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 720)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"登录助手与互联（高级）";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(700, 600);
    self = [super initWithWindow:window];
    if (self) {
        _recipes = @[];
        _memos = @[];
        _editingMemoFields = [NSMutableArray array];
        _settingsMode = BrowserLoginAssistSettingsModeRecipes;
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recipesDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(memosDidChange:)
                                                     name:FormMemoStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(companionStateDidChange:)
                                                     name:CompanionChannelStateDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(settingsWindowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(settingsWindowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:window];
    }
    return self;
}

- (void)dealloc {
    [self stopCompanionStatusPolling];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)recipesDidChange:(NSNotification *)note {
    (void)note;
    NSString *keepID = self.editingRecipeID;
    [self reloadRecipes];
    if (self.settingsMode == BrowserLoginAssistSettingsModeRecipes && keepID.length > 0) {
        [self selectRecipeID:keepID];
    }
}

- (void)memosDidChange:(NSNotification *)note {
    (void)note;
    NSString *keepID = self.editingMemoID;
    [self reloadMemos];
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos && keepID.length > 0) {
        [self selectMemoID:keepID];
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
    self.sectionControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.sectionControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionControl.segmentCount = 2;
    [self.sectionControl setLabel:@"登录配置" forSegment:0];
    [self.sectionControl setLabel:@"站点备忘" forSegment:1];
    self.sectionControl.selectedSegment = 0;
    self.sectionControl.segmentStyle = NSSegmentStyleRounded;
    self.sectionControl.target = self;
    self.sectionControl.action = @selector(sectionChanged:);
    [self.sectionControl.widthAnchor constraintEqualToConstant:200].active = YES;

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
                                             action:@selector(addListItem:)];
    addButton.bezelStyle = NSBezelStyleRounded;
    NSButton *deleteButton = [NSButton buttonWithTitle:@"删除"
                                                target:self
                                                action:@selector(deleteListItem:)];
    deleteButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *listButtons = [NSStackView stackViewWithViews:@[addButton, deleteButton]];
    listButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    listButtons.spacing = 8;

    NSStackView *listColumn = [NSStackView stackViewWithViews:@[self.sectionControl, scroll, listButtons]];
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
    self.perFieldInlineCheck = [NSButton checkboxWithTitle:@"逐字段显示「＋ / 填入」（关闭则回退为单钥匙菜单）"
                                                    target:self
                                                    action:@selector(prefsChanged:)];
    self.extraFieldInlineCheck = [NSButton checkboxWithTitle:@"登录表额外文本框也显示图标（默认关）"
                                                      target:self
                                                      action:@selector(prefsChanged:)];
    self.focusInlineCheck = [NSButton checkboxWithTitle:@"聚焦输入框时显示助手图标（手机/卡号/短信登录等，新标签生效）"
                                                 target:self
                                                 action:@selector(prefsChanged:)];
    self.inlineAssistCheck.state = [LoginAssistPreferences inlineAssistEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    self.promptSaveCheck.state = [LoginAssistPreferences promptSaveOnSuccess] ? NSControlStateValueOn : NSControlStateValueOff;
    self.perFieldInlineCheck.state = [[LoginAssistPreferences loginFieldInlineMode] isEqualToString:LoginFieldInlineModePerField]
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.extraFieldInlineCheck.state = [LoginAssistPreferences loginExtraFieldInlineEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    self.focusInlineCheck.state = [LoginAssistPreferences loginFocusInlineEnabled] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *saveButton = [NSButton buttonWithTitle:@"保存"
                                              target:self
                                              action:@selector(saveRecipe:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";

    self.statusLabel = [NSTextField wrappingLabelWithString:@"凭证保存在应用内部存储；清除「网站数据」不会删除登录配置。"];
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

    self.invitePhoneButton = [NSButton buttonWithTitle:@"邀请手机重连"
                                                target:self
                                                action:@selector(invitePhoneClicked:)];
    self.invitePhoneButton.bezelStyle = NSBezelStyleRounded;
    self.invitePhoneButton.toolTip = @"向局域网已配对手机发送 invite，促使其立即连接";

    NSStackView *endpointRow = [NSStackView stackViewWithViews:@[self.companionEndpointButton,
                                                                self.changePortButton,
                                                                self.invitePhoneButton]];
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
    self.mirrorEnabledCheck = [NSButton checkboxWithTitle:@"系统通知栏显示手机通知（横幅）"
                                                   target:self
                                                   action:@selector(mirrorSettingsChanged:)];
    self.mirrorEnabledCheck.state = mirrorSettings.mirrorEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    self.otpBannerEnabledCheck = [NSButton checkboxWithTitle:@"收到验证码时显示系统通知"
                                                      target:self
                                                      action:@selector(mirrorSettingsChanged:)];
    self.otpBannerEnabledCheck.state = mirrorSettings.otpBannerEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    PhoneNotificationInboxSettings *inboxSettings = [PhoneNotificationInboxSettings sharedSettings];
    self.inboxEnabledCheck = [NSButton checkboxWithTitle:@"将手机通知保存到收件箱侧栏"
                                                  target:self
                                                  action:@selector(inboxSettingsChanged:)];
    self.inboxEnabledCheck.state = inboxSettings.inboxEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    self.otpToInboxCheck = [NSButton checkboxWithTitle:@"验证码写入收件箱"
                                                target:self
                                                action:@selector(inboxSettingsChanged:)];
    self.otpToInboxCheck.state = inboxSettings.otpToInbox ? NSControlStateValueOn : NSControlStateValueOff;

    self.autoMarkReadCheck = [NSButton checkboxWithTitle:@"打开侧栏时自动标为已读"
                                                  target:self
                                                  action:@selector(inboxSettingsChanged:)];
    self.autoMarkReadCheck.state = inboxSettings.autoMarkReadOnVisible ? NSControlStateValueOn : NSControlStateValueOff;

    self.wechatReplyEnabledCheck = [NSButton checkboxWithTitle:@"微信回复（实验）：侧栏可回复微信通知"
                                                        target:self
                                                        action:@selector(inboxSettingsChanged:)];
    self.wechatReplyEnabledCheck.state = inboxSettings.wechatReplyEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    NSTextField *retentionLabel = [NSTextField labelWithString:@"保留期限"];
    retentionLabel.font = [NSFont systemFontOfSize:12];
    self.inboxRetentionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.inboxRetentionPopup addItemsWithTitles:@[@"1 天", @"7 天", @"30 天", @"永久"]];
    NSInteger days = inboxSettings.retentionDays;
    NSInteger retentionIndex = 1;
    if (days == 1) retentionIndex = 0;
    else if (days == 7) retentionIndex = 1;
    else if (days == 30) retentionIndex = 2;
    else if (days == 0) retentionIndex = 3;
    [self.inboxRetentionPopup selectItemAtIndex:retentionIndex];
    self.inboxRetentionPopup.target = self;
    self.inboxRetentionPopup.action = @selector(inboxSettingsChanged:);
    NSStackView *retentionRow = [NSStackView stackViewWithViews:@[retentionLabel, self.inboxRetentionPopup]];
    retentionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    retentionRow.spacing = 8;
    retentionRow.alignment = NSLayoutAttributeCenterY;

    self.purgeInboxButton = [NSButton buttonWithTitle:@"清空收件箱…"
                                               target:self
                                               action:@selector(purgeInboxClicked:)];
    self.purgeInboxButton.bezelStyle = NSBezelStyleRounded;

    self.openNotificationSettingsButton = [NSButton buttonWithTitle:@"打开系统通知设置…"
                                                             target:self
                                                             action:@selector(openSystemNotificationSettings:)];
    self.openNotificationSettingsButton.bezelStyle = NSBezelStyleRounded;

    self.mirrorHintLabel = [NSTextField wrappingLabelWithString:@"系统通知左侧图标为本应用（MeoBrowser）；来源看标题前缀。收件箱内容仅存本机。微信回复为实验能力：需手机 Companion 开启对应开关与无障碍；按通知标题匹配联系人。手机端选「全部通知」才会有普通微信通知。"];
    self.mirrorHintLabel.font = [NSFont systemFontOfSize:11];
    self.mirrorHintLabel.textColor = [NSColor secondaryLabelColor];
    self.mirrorHintLabel.preferredMaxLayoutWidth = 420;

    NSView *mirrorCard = [self makeSettingsCardWithTitle:@"通知镜像与收件箱"
                                        arrangedSubviews:@[
                                            self.mirrorEnabledCheck,
                                            self.otpBannerEnabledCheck,
                                            self.inboxEnabledCheck,
                                            self.otpToInboxCheck,
                                            self.autoMarkReadCheck,
                                            self.wechatReplyEnabledCheck,
                                            retentionRow,
                                            self.purgeInboxButton,
                                            self.openNotificationSettingsButton,
                                            self.mirrorHintLabel,
                                        ]];

    CallAlertSettings *callSettings = [CallAlertSettings sharedSettings];
    self.callAlertEnabledCheck = [NSButton checkboxWithTitle:@"接收手机来电提醒"
                                                      target:self
                                                      action:@selector(callAlertSettingsChanged:)];
    self.callAlertEnabledCheck.state = callSettings.alertEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.callAlertBannerCheck = [NSButton checkboxWithTitle:@"浏览器内显示跨标签来电条"
                                                     target:self
                                                     action:@selector(callAlertSettingsChanged:)];
    self.callAlertBannerCheck.state = callSettings.bannerEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.callAlertSystemNotifCheck = [NSButton checkboxWithTitle:@"系统通知栏显示来电"
                                                          target:self
                                                          action:@selector(callAlertSettingsChanged:)];
    self.callAlertSystemNotifCheck.state = callSettings.systemNotificationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.callAlertHintLabel = [NSTextField wrappingLabelWithString:@"手机 Companion 需开启来电提醒，并授予电话权限与「来电筛选」角色以获取号码。号码类型用轻量规则判断；备注在工具栏「号码策略」管理。本期无黑名单。"];
    self.callAlertHintLabel.font = [NSFont systemFontOfSize:11];
    self.callAlertHintLabel.textColor = [NSColor secondaryLabelColor];
    self.callAlertHintLabel.preferredMaxLayoutWidth = 420;

    NSView *callAlertCard = [self makeSettingsCardWithTitle:@"来电提醒"
                                           arrangedSubviews:@[
                                               self.callAlertEnabledCheck,
                                               self.callAlertBannerCheck,
                                               self.callAlertSystemNotifCheck,
                                               self.callAlertHintLabel,
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
    self.recipeSectionTitle = recipeSectionTitle;

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

    self.recipeCard = [self makeSettingsCardWithTitle:nil
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
                                         self.perFieldInlineCheck,
                                         self.extraFieldInlineCheck,
                                         self.focusInlineCheck,
                                         self.promptSaveCheck,
                                         self.statusLabel,
                                     ]];

    self.memoCard = [self buildMemoCard];
    NSTextField *memoSectionTitle = [NSTextField labelWithString:@"站点备忘"];
    memoSectionTitle.font = [NSFont boldSystemFontOfSize:13];
    self.memoSectionTitle = memoSectionTitle;

    NSStackView *form = [NSStackView stackViewWithViews:@[
        self.companionStatusCard,
        authCard,
        mirrorCard,
        callAlertCard,
        syncCard,
        self.recipeSectionTitle,
        self.recipeCard,
        self.memoSectionTitle,
        self.memoCard,
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
    [self reloadMemos];
    [self clearForm];
    [self clearMemoForm];
    [self refreshCompanionUI];
    [self applySettingsModeUI];
}

- (void)reloadRecipes {
    self.recipes = [[LoginRecipeStore sharedStore] allRecipes];
    if (self.settingsMode == BrowserLoginAssistSettingsModeRecipes) {
        [self.tableView reloadData];
    }
}

- (void)reloadMemos {
    self.memos = [[FormMemoStore sharedStore] allMemos];
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        [self.tableView reloadData];
    }
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
    // CALayer does not transfer ownership of borderColor; replacing it releases the old
    // color, so we must copy before the delayed restore (otherwise setBorderColor: crashes).
    CGColorRef previousBorder = layer.borderColor ? CGColorCreateCopy(layer.borderColor) : NULL;
    CGFloat previousWidth = layer.borderWidth;
    if (@available(macOS 10.14, *)) {
        layer.borderColor = [NSColor controlAccentColor].CGColor;
    } else {
        layer.borderColor = [NSColor selectedControlColor].CGColor;
    }
    layer.borderWidth = 2.0;
    __weak NSView *weakCard = card;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CALayer *restoreLayer = weakCard.layer;
        if (restoreLayer) {
            restoreLayer.borderColor = previousBorder;
            restoreLayer.borderWidth = previousWidth;
        }
        if (previousBorder) {
            CGColorRelease(previousBorder);
        }
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
    [self revealRecipeSection];
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
    self.statusLabel.stringValue = @"凭证保存在应用内部存储；清除「网站数据」不会删除登录配置。";
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
    if (tableView == self.memoFieldsTable) {
        return (NSInteger)self.editingMemoFields.count;
    }
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        return (NSInteger)self.memos.count;
    }
    return (NSInteger)self.recipes.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.memoFieldsTable) {
        NSString *identifier = @"MemoFieldCell";
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
        if (row >= 0 && row < (NSInteger)self.editingMemoFields.count) {
            FormMemoField *field = self.editingMemoFields[row];
            NSString *label = field.label.length > 0 ? field.label : @"未命名字段";
            NSString *sel = field.selector.length > 0 ? field.selector : @"（未设选择器）";
            cell.textField.stringValue = [NSString stringWithFormat:@"%@ · %@", label, sel];
            cell.textField.textColor = field.enabled ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
        }
        return cell;
    }

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
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        if (row >= 0 && row < (NSInteger)self.memos.count) {
            FormMemo *memo = self.memos[row];
            NSString *title = memo.title.length > 0 ? memo.title : memo.host;
            if (memo.isDefault) {
                title = [title stringByAppendingString:@" ★"];
            }
            NSUInteger count = memo.fields.count;
            cell.textField.stringValue = [NSString stringWithFormat:@"%@（%lu）", title, (unsigned long)count];
        }
    } else if (row >= 0 && row < (NSInteger)self.recipes.count) {
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
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        if (row < 0 || row >= (NSInteger)self.memos.count) {
            return;
        }
        [self loadMemoIntoForm:self.memos[row]];
        return;
    }
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
    [LoginAssistPreferences setLoginFieldInlineMode:(self.perFieldInlineCheck.state == NSControlStateValueOn)
     ? LoginFieldInlineModePerField
     : LoginFieldInlineModeLegacySingleKey];
    [LoginAssistPreferences setLoginExtraFieldInlineEnabled:(self.extraFieldInlineCheck.state == NSControlStateValueOn)];
    [LoginAssistPreferences setLoginFocusInlineEnabled:(self.focusInlineCheck.state == NSControlStateValueOn)];
    self.statusLabel.stringValue = @"偏好已保存。内联图标开关对新建标签 / 新导航后的页面生效。";
}

- (void)memoInlinePrefsChanged:(id)sender {
    (void)sender;
    [FormMemoPreferences setInlineSaveEnabled:(self.memoInlineSaveCheck.state == NSControlStateValueOn)];
    self.memoStatusLabel.stringValue = @"偏好已保存。「保存到站点备忘」图标对新建标签 / 新导航后的页面生效。";
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

- (void)addListItem:(id)sender {
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        [self addMemo:sender];
    } else {
        [self addRecipe:sender];
    }
}

- (void)deleteListItem:(id)sender {
    if (self.settingsMode == BrowserLoginAssistSettingsModeMemos) {
        [self deleteMemo:sender];
    } else {
        [self deleteRecipe:sender];
    }
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
    confirm.informativeText = @"将同时删除本地保存的账号密码。";
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
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = self.usernameField.stringValue ?: @"";
    credentials.password = self.passwordField.stringValue ?: @"";
    credentials.phone = self.phoneField.stringValue ?: @"";
    // 先写凭证再 upsert，避免 Store 通知触发的表单重载冲掉输入（与侧栏 RE-0 一致）。
    if (![[LoginCredentialStore sharedStore] saveCredentials:credentials
                                                 forRecipeID:recipe.recipeID
                                                       error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"凭证保存失败";
        return;
    }
    if (![[LoginRecipeStore sharedStore] upsertRecipe:recipe error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存失败";
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
        } else if ([strongSelf.pickingTarget isEqualToString:@"memoField"]) {
            strongSelf.memoFieldSelectorField.stringValue = cssSelector;
            [strongSelf applyMemoFieldEditorToSelection];
        }
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
        if (strongSelf.settingsMode == BrowserLoginAssistSettingsModeMemos) {
            strongSelf.memoStatusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
        }
        strongSelf.pickingTarget = nil;
    }];
}

- (void)showWindow:(id)sender {
    [self reloadRecipes];
    [self reloadMemos];
    [self refreshCompanionUI];
    [super showWindow:sender];
    [self startCompanionStatusPollingIfNeeded];
}

- (void)settingsWindowDidBecomeKey:(NSNotification *)note {
    (void)note;
    [self refreshCompanionUI];
    [self startCompanionStatusPollingIfNeeded];
}

- (void)settingsWindowWillClose:(NSNotification *)note {
    (void)note;
    [self stopCompanionStatusPolling];
}

- (void)startCompanionStatusPollingIfNeeded {
    if (self.companionStatusTimer) {
        return;
    }
    if (!self.window.isVisible) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:2.0
                                            repeats:YES
                                              block:^(NSTimer * _Nonnull t) {
        (void)t;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (!strongSelf.window.isVisible) {
            [strongSelf stopCompanionStatusPolling];
            return;
        }
        [strongSelf refreshCompanionUI];
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.companionStatusTimer = timer;
}

- (void)stopCompanionStatusPolling {
    [self.companionStatusTimer invalidate];
    self.companionStatusTimer = nil;
}

- (void)companionStateDidChange:(NSNotification *)note {
    (void)note;
    if (self.refreshingCompanionUI) {
        return;
    }
    [self refreshCompanionUI];
}

- (void)refreshCompanionUI {
    if (self.refreshingCompanionUI) {
        return;
    }
    self.refreshingCompanionUI = YES;

    CompanionChannel *channel = [CompanionChannel sharedChannel];
    if (channel.state == CompanionChannelStateStopped) {
        [channel start];
    }
    [channel reconcileConnectionState];

    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    BOOL securityMode = (store.authMode == CompanionAuthModeSecurityCode);
    self.companionAuthModeControl.selectedSegment = securityMode ? 1 : 0;
    self.pairingModeStack.hidden = securityMode;
    self.securityModeStack.hidden = !securityMode;
    if (securityMode && store.securityCode.length > 0 && self.securityCodeField.stringValue.length == 0) {
        self.securityCodeField.stringValue = store.securityCode;
    }

    BOOL connected = (channel.state == CompanionChannelStateConnected);
    NSUInteger paired = store.pairedDeviceCountHint;
    CompanionLinkUIState uiState = [CompanionLinkUI stateFromChannel:channel];
    self.companionConnectionLabel.stringValue = [CompanionLinkUI titleForChannel:channel];
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
            ? (paired > 0
               ? @"已配对，等待手机重连。也可点「邀请手机重连」主动唤醒。"
               : @"安全码模式：手机 Companion 选「固定安全码」并保存后，打开即可自动连接。")
            : @"请先设定并保存固定安全码，再在手机 Companion 选择相同模式。";
    } else {
        self.companionHintLabel.stringValue = paired > 0
            ? @"已配对，等待手机重连。也可点「邀请手机重连」主动唤醒；或「刷新配对码」给新设备。"
            : @"请在手机 Companion 输入下方配对码，或填写主机地址手动连接。";
    }

    self.invitePhoneButton.enabled = (!connected && paired > 0);

    NSString *endpoint = [channel preferredLANEndpoint] ?: @"—";
    self.displayedEndpoint = ([endpoint isEqualToString:@"—"] || [endpoint containsString:@"未检测到"]) ? nil : endpoint;
    NSString *portNote = channel.usingTemporaryPort ? @"（临时）" : @"（固定）";
    self.companionEndpointButton.title = [NSString stringWithFormat:@"主机：%@%@", endpoint, portNote];

    if (securityMode) {
        self.displayedPairingCode = store.securityCode;
        self.refreshingCompanionUI = NO;
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
    PhoneNotificationInboxSettings *inboxSettings = [PhoneNotificationInboxSettings sharedSettings];
    self.inboxEnabledCheck.state = inboxSettings.inboxEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.otpToInboxCheck.state = inboxSettings.otpToInbox ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoMarkReadCheck.state = inboxSettings.autoMarkReadOnVisible ? NSControlStateValueOn : NSControlStateValueOff;
    self.wechatReplyEnabledCheck.state = inboxSettings.wechatReplyEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSInteger days = inboxSettings.retentionDays;
    NSInteger retentionIndex = 1;
    if (days == 1) retentionIndex = 0;
    else if (days == 7) retentionIndex = 1;
    else if (days == 30) retentionIndex = 2;
    else if (days == 0) retentionIndex = 3;
    [self.inboxRetentionPopup selectItemAtIndex:retentionIndex];
    CallAlertSettings *callSettings = [CallAlertSettings sharedSettings];
    self.callAlertEnabledCheck.state = callSettings.alertEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.callAlertBannerCheck.state = callSettings.bannerEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.callAlertSystemNotifCheck.state = callSettings.systemNotificationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    CompanionSyncSettings *syncSettings = [CompanionSyncSettings sharedSettings];
    self.syncEnabledCheck.state = syncSettings.syncEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncShortcutsCheck.state = syncSettings.syncShortcuts ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncHistoryCheck.state = syncSettings.syncHistory ? NSControlStateValueOn : NSControlStateValueOff;
    self.syncBookmarksCheck.state = syncSettings.syncBookmarks ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshNotificationPermissionHint];
    self.refreshingCompanionUI = NO;
}

- (void)mirrorSettingsChanged:(id)sender {
    (void)sender;
    PhoneNotificationSettings *settings = [PhoneNotificationSettings sharedSettings];
    settings.mirrorEnabled = (self.mirrorEnabledCheck.state == NSControlStateValueOn);
    settings.otpBannerEnabled = (self.otpBannerEnabledCheck.state == NSControlStateValueOn);
    [[PhoneNotificationPresenter sharedPresenter] requestAuthorizationIfNeeded];
    [self refreshNotificationPermissionHint];
}

- (void)inboxSettingsChanged:(id)sender {
    (void)sender;
    PhoneNotificationInboxSettings *settings = [PhoneNotificationInboxSettings sharedSettings];
    settings.inboxEnabled = (self.inboxEnabledCheck.state == NSControlStateValueOn);
    settings.otpToInbox = (self.otpToInboxCheck.state == NSControlStateValueOn);
    settings.autoMarkReadOnVisible = (self.autoMarkReadCheck.state == NSControlStateValueOn);
    settings.wechatReplyEnabled = (self.wechatReplyEnabledCheck.state == NSControlStateValueOn);
    switch (self.inboxRetentionPopup.indexOfSelectedItem) {
        case 0: settings.retentionDays = 1; break;
        case 2: settings.retentionDays = 30; break;
        case 3: settings.retentionDays = 0; break;
        default: settings.retentionDays = 7; break;
    }
}

- (void)purgeInboxClicked:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"清空全部收件箱通知？";
    alert.informativeText = @"包括未读与已钉选条目。此操作不可撤销。";
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[PhoneNotificationInboxStore sharedStore] purgeAll];
    }
}

- (void)callAlertSettingsChanged:(id)sender {
    (void)sender;
    CallAlertSettings *settings = [CallAlertSettings sharedSettings];
    settings.alertEnabled = (self.callAlertEnabledCheck.state == NSControlStateValueOn);
    settings.bannerEnabled = (self.callAlertBannerCheck.state == NSControlStateValueOn);
    settings.systemNotificationEnabled = (self.callAlertSystemNotifCheck.state == NSControlStateValueOn);
    if (settings.alertEnabled) {
        [[CallAlertPresenter sharedPresenter] requestAuthorizationIfNeeded];
    }
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

- (void)invitePhoneClicked:(id)sender {
    (void)sender;
    CompanionChannel *channel = [CompanionChannel sharedChannel];
    if (channel.state == CompanionChannelStateConnected) {
        self.statusLabel.stringValue = @"手机已连接，无需邀请。";
        return;
    }
    if ([CompanionPairingStore sharedStore].pairedDeviceCountHint == 0) {
        self.statusLabel.stringValue = @"尚未配对设备，请先完成配对。";
        return;
    }
    if (channel.state == CompanionChannelStateStopped) {
        [channel start];
    }
    [channel invitePairedPhones];
    self.statusLabel.stringValue = @"已向局域网已配对手机发送邀请…";
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

#pragma mark - Site Form Memo

- (NSView *)buildMemoCard {
    self.memoTitleField = [self makeField];
    self.memoHostField = [self makeField];
    self.memoPathPrefixField = [self makeField];
    self.memoDefaultCheck = [NSButton checkboxWithTitle:@"设为该站点默认备忘"
                                                 target:nil
                                                 action:nil];
    self.memoInlineSaveCheck = [NSButton checkboxWithTitle:@"输入时显示「保存到站点备忘」（新标签生效）"
                                                    target:self
                                                    action:@selector(memoInlinePrefsChanged:)];
    self.memoInlineSaveCheck.state = [FormMemoPreferences inlineSaveEnabled] ? NSControlStateValueOn : NSControlStateValueOff;

    NSScrollView *fieldsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    fieldsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    fieldsScroll.hasVerticalScroller = YES;
    fieldsScroll.borderType = NSBezelBorder;
    self.memoFieldsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"field"];
    col.title = @"字段";
    col.width = 360;
    [self.memoFieldsTable addTableColumn:col];
    self.memoFieldsTable.headerView = nil;
    self.memoFieldsTable.delegate = self;
    self.memoFieldsTable.dataSource = self;
    self.memoFieldsTable.target = self;
    self.memoFieldsTable.action = @selector(memoFieldSelectionChanged:);
    fieldsScroll.documentView = self.memoFieldsTable;
    [fieldsScroll.heightAnchor constraintEqualToConstant:110].active = YES;

    NSButton *addField = [NSButton buttonWithTitle:@"添加字段"
                                            target:self
                                            action:@selector(addMemoField:)];
    addField.bezelStyle = NSBezelStyleRounded;
    addField.controlSize = NSControlSizeSmall;
    NSButton *removeField = [NSButton buttonWithTitle:@"删除字段"
                                               target:self
                                               action:@selector(removeMemoField:)];
    removeField.bezelStyle = NSBezelStyleRounded;
    removeField.controlSize = NSControlSizeSmall;
    NSButton *moveUp = [NSButton buttonWithTitle:@"上移"
                                          target:self
                                          action:@selector(moveMemoFieldUp:)];
    moveUp.bezelStyle = NSBezelStyleRounded;
    moveUp.controlSize = NSControlSizeSmall;
    NSButton *moveDown = [NSButton buttonWithTitle:@"下移"
                                            target:self
                                            action:@selector(moveMemoFieldDown:)];
    moveDown.bezelStyle = NSBezelStyleRounded;
    moveDown.controlSize = NSControlSizeSmall;
    NSStackView *fieldButtons = [NSStackView stackViewWithViews:@[addField, removeField, moveUp, moveDown]];
    fieldButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fieldButtons.spacing = 6;

    self.memoFieldLabelField = [self makeField];
    self.memoFieldSelectorField = [self makeField];
    self.memoFieldEnabledCheck = [NSButton checkboxWithTitle:@"启用该字段"
                                                      target:self
                                                      action:@selector(memoFieldEditorChanged:)];

    self.memoFieldValueView = [SBTextView standardTextView];
    self.memoFieldValueView.delegate = self;
    self.memoFieldValueView.font = [NSFont systemFontOfSize:13];
    self.memoFieldValueScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.memoFieldValueScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.memoFieldValueScroll.hasVerticalScroller = YES;
    self.memoFieldValueScroll.borderType = NSBezelBorder;
    self.memoFieldValueScroll.documentView = self.memoFieldValueView;
    [self.memoFieldValueScroll.heightAnchor constraintEqualToConstant:72].active = YES;

    NSButton *pickField = [NSButton buttonWithTitle:@"点选"
                                             target:self
                                             action:@selector(pickMemoFieldSelector:)];
    pickField.bezelStyle = NSBezelStyleRounded;
    pickField.controlSize = NSControlSizeSmall;
    NSButton *applyField = [NSButton buttonWithTitle:@"应用到选中字段"
                                              target:self
                                              action:@selector(applyMemoFieldEditorToSelection)];
    applyField.bezelStyle = NSBezelStyleRounded;
    applyField.controlSize = NSControlSizeSmall;

    NSButton *saveMemo = [NSButton buttonWithTitle:@"保存备忘"
                                            target:self
                                            action:@selector(saveMemo:)];
    saveMemo.bezelStyle = NSBezelStyleRounded;

    self.memoStatusLabel = [NSTextField wrappingLabelWithString:@"备忘为明文本地存储，请勿存放密码；密码请用「登录配置」。清除网站数据不会删除备忘。"];
    self.memoStatusLabel.font = [NSFont systemFontOfSize:11];
    self.memoStatusLabel.textColor = [NSColor secondaryLabelColor];

    NSTextField *valueCaption = [self caption:@"字段内容"];
    valueCaption.translatesAutoresizingMaskIntoConstraints = NO;
    [valueCaption.widthAnchor constraintEqualToConstant:88].active = YES;
    NSStackView *valueRow = [NSStackView stackViewWithViews:@[valueCaption, self.memoFieldValueScroll]];
    valueRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    valueRow.alignment = NSLayoutAttributeTop;
    valueRow.spacing = 8;
    [self.memoFieldValueScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *applyRow = [NSStackView stackViewWithViews:@[applyField, pickField]];
    applyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    applyRow.spacing = 8;

    return [self makeSettingsCardWithTitle:nil
                          arrangedSubviews:@[
                              [self labeledRow:@"名称" field:self.memoTitleField pickAction:nil],
                              [self labeledRow:@"主机" field:self.memoHostField pickAction:nil],
                              [self labeledRow:@"路径前缀" field:self.memoPathPrefixField pickAction:nil],
                              self.memoDefaultCheck,
                              self.memoInlineSaveCheck,
                              fieldsScroll,
                              fieldButtons,
                              [self labeledRow:@"字段标签" field:self.memoFieldLabelField pickAction:nil],
                              [self labeledRow:@"选择器" field:self.memoFieldSelectorField pickAction:nil],
                              valueRow,
                              self.memoFieldEnabledCheck,
                              applyRow,
                              saveMemo,
                              self.memoStatusLabel,
                          ]];
}

- (void)sectionChanged:(id)sender {
    (void)sender;
    self.settingsMode = (BrowserLoginAssistSettingsMode)self.sectionControl.selectedSegment;
    [self applySettingsModeUI];
    [self.tableView reloadData];
    [self.tableView deselectAll:nil];
}

- (void)applySettingsModeUI {
    BOOL memo = (self.settingsMode == BrowserLoginAssistSettingsModeMemos);
    self.recipeSectionTitle.hidden = memo;
    self.recipeCard.hidden = memo;
    self.memoSectionTitle.hidden = !memo;
    self.memoCard.hidden = !memo;
    self.sectionControl.selectedSegment = memo ? 1 : 0;
}

- (void)revealRecipeSection {
    self.settingsMode = BrowserLoginAssistSettingsModeRecipes;
    [self applySettingsModeUI];
    [self.tableView reloadData];
    [self.window layoutIfNeeded];
    [self.recipeCard scrollRectToVisible:NSInsetRect(self.recipeCard.bounds, 0, -8)];
}

- (void)revealMemoSection {
    self.settingsMode = BrowserLoginAssistSettingsModeMemos;
    [self applySettingsModeUI];
    [self.tableView reloadData];
    [self.window layoutIfNeeded];
    [self.memoCard scrollRectToVisible:NSInsetRect(self.memoCard.bounds, 0, -8)];
}

- (void)selectMemoID:(NSString *)memoID {
    [self revealMemoSection];
    [self reloadMemos];
    for (NSInteger i = 0; i < (NSInteger)self.memos.count; i++) {
        if ([self.memos[i].memoID isEqualToString:memoID]) {
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self loadMemoIntoForm:self.memos[i]];
            return;
        }
    }
}

- (void)clearMemoForm {
    self.editingMemoID = nil;
    self.memoTitleField.stringValue = @"";
    self.memoHostField.stringValue = @"";
    self.memoPathPrefixField.stringValue = @"";
    self.memoDefaultCheck.state = NSControlStateValueOff;
    [self.editingMemoFields removeAllObjects];
    [self.memoFieldsTable reloadData];
    self.memoFieldLabelField.stringValue = @"";
    self.memoFieldSelectorField.stringValue = @"";
    self.memoFieldValueView.string = @"";
    self.memoFieldEnabledCheck.state = NSControlStateValueOn;
    self.memoStatusLabel.stringValue = @"备忘为明文本地存储，请勿存放密码；密码请用「登录配置」。清除网站数据不会删除备忘。";
}

- (void)loadMemoIntoForm:(FormMemo *)memo {
    self.editingMemoID = memo.memoID;
    self.memoTitleField.stringValue = memo.title ?: @"";
    self.memoHostField.stringValue = memo.host ?: @"";
    self.memoPathPrefixField.stringValue = memo.pathPrefix ?: @"";
    self.memoDefaultCheck.state = memo.isDefault ? NSControlStateValueOn : NSControlStateValueOff;
    [self.editingMemoFields removeAllObjects];
    for (FormMemoField *field in memo.fields) {
        [self.editingMemoFields addObject:[field copy]];
    }
    [self.memoFieldsTable reloadData];
    if (self.editingMemoFields.count > 0) {
        [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self loadMemoFieldEditorFromIndex:0];
    } else {
        self.memoFieldLabelField.stringValue = @"";
        self.memoFieldSelectorField.stringValue = @"";
        self.memoFieldValueView.string = @"";
        self.memoFieldEnabledCheck.state = NSControlStateValueOn;
    }
    self.memoStatusLabel.stringValue = [NSString stringWithFormat:@"正在编辑「%@」· %lu 个字段",
                                        memo.title.length > 0 ? memo.title : memo.host,
                                        (unsigned long)memo.fields.count];
}

- (void)addMemo:(id)sender {
    (void)sender;
    [self.tableView deselectAll:nil];
    [self clearMemoForm];
    NSURL *url = self.pickerHost.activeWebViewForPicking.URL;
    if (url.isFileURL) {
        self.memoHostField.stringValue = @"file";
        self.memoTitleField.stringValue = @"本地表单备忘";
        if (url.path.lastPathComponent.length > 0) {
            self.memoPathPrefixField.stringValue = url.path.lastPathComponent;
        }
    } else if (url.host.length > 0) {
        self.memoHostField.stringValue = url.host.lowercaseString;
        self.memoTitleField.stringValue = url.host;
    }
    FormMemoField *seed = [FormMemoField fieldWithLabel:@"字段1" selector:@"" value:@""];
    [self.editingMemoFields addObject:seed];
    [self.memoFieldsTable reloadData];
    [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self loadMemoFieldEditorFromIndex:0];
    self.memoStatusLabel.stringValue = @"填写主机与字段后点击「保存备忘」。";
}

- (void)deleteMemo:(id)sender {
    (void)sender;
    NSString *memoID = self.editingMemoID;
    if (memoID.length == 0) {
        NSInteger row = self.tableView.selectedRow;
        if (row >= 0 && row < (NSInteger)self.memos.count) {
            memoID = self.memos[row].memoID;
        }
    }
    if (memoID.length == 0) {
        return;
    }
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"删除此站点备忘？";
    confirm.informativeText = @"将删除该备忘下的全部字段文本。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"删除"];
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertFirstButtonReturn) {
            return;
        }
        [[FormMemoStore sharedStore] deleteMemoWithID:memoID error:nil];
        [weakSelf clearMemoForm];
        [weakSelf reloadMemos];
    }];
}

- (void)saveMemo:(id)sender {
    (void)sender;
    [self applyMemoFieldEditorToSelection];
    NSString *host = [self.memoHostField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (host.length == 0) {
        self.memoStatusLabel.stringValue = @"请填写主机。";
        return;
    }
    FormMemo *memo = nil;
    if (self.editingMemoID.length > 0) {
        memo = [[[FormMemoStore sharedStore] memoWithID:self.editingMemoID] copy];
    }
    if (!memo) {
        memo = [FormMemo memoWithHost:host title:self.memoTitleField.stringValue];
    }
    memo.host = host.lowercaseString;
    memo.title = self.memoTitleField.stringValue.length > 0 ? self.memoTitleField.stringValue : host;
    NSString *path = [self.memoPathPrefixField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    memo.pathPrefix = path.length > 0 ? path : nil;
    memo.isDefault = (self.memoDefaultCheck.state == NSControlStateValueOn);
    NSMutableArray<FormMemoField *> *fields = [NSMutableArray array];
    for (FormMemoField *field in self.editingMemoFields) {
        [fields addObject:[field copy]];
    }
    memo.fields = fields;

    NSError *error = nil;
    if (![[FormMemoStore sharedStore] upsertMemo:memo error:&error]) {
        self.memoStatusLabel.stringValue = error.localizedDescription ?: @"保存失败";
        return;
    }
    self.editingMemoID = memo.memoID;
    [self reloadMemos];
    [self selectMemoID:memo.memoID];
    self.memoStatusLabel.stringValue = @"备忘已保存。";
}

- (void)memoFieldSelectionChanged:(id)sender {
    (void)sender;
    NSInteger row = self.memoFieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingMemoFields.count) {
        return;
    }
    [self loadMemoFieldEditorFromIndex:row];
}

- (void)loadMemoFieldEditorFromIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.editingMemoFields.count) {
        return;
    }
    FormMemoField *field = self.editingMemoFields[index];
    self.memoFieldLabelField.stringValue = field.label ?: @"";
    self.memoFieldSelectorField.stringValue = field.selector ?: @"";
    self.memoFieldValueView.string = field.value ?: @"";
    self.memoFieldEnabledCheck.state = field.enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyMemoFieldEditorToSelection {
    [self applyMemoFieldEditorToSelectionKeepingSelection:YES];
}

- (void)applyMemoFieldEditorToSelectionKeepingSelection:(BOOL)keep {
    NSInteger row = self.memoFieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingMemoFields.count) {
        return;
    }
    FormMemoField *field = self.editingMemoFields[row];
    field.label = self.memoFieldLabelField.stringValue ?: @"";
    field.selector = self.memoFieldSelectorField.stringValue ?: @"";
    field.value = self.memoFieldValueView.string ?: @"";
    field.enabled = (self.memoFieldEnabledCheck.state == NSControlStateValueOn);
    [self.memoFieldsTable reloadData];
    if (keep) {
        [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
}

- (void)memoFieldEditorChanged:(id)sender {
    (void)sender;
    [self applyMemoFieldEditorToSelection];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.memoFieldValueView) {
        [self applyMemoFieldEditorToSelection];
    }
}

- (void)addMemoField:(id)sender {
    (void)sender;
    [self applyMemoFieldEditorToSelection];
    FormMemoField *field = [FormMemoField fieldWithLabel:[NSString stringWithFormat:@"字段%lu",
                                                          (unsigned long)(self.editingMemoFields.count + 1)]
                                                selector:@""
                                                   value:@""];
    [self.editingMemoFields addObject:field];
    [self.memoFieldsTable reloadData];
    NSInteger row = (NSInteger)self.editingMemoFields.count - 1;
    [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self loadMemoFieldEditorFromIndex:row];
}

- (void)removeMemoField:(id)sender {
    (void)sender;
    NSInteger row = self.memoFieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingMemoFields.count) {
        return;
    }
    [self.editingMemoFields removeObjectAtIndex:row];
    [self.memoFieldsTable reloadData];
    if (self.editingMemoFields.count == 0) {
        self.memoFieldLabelField.stringValue = @"";
        self.memoFieldSelectorField.stringValue = @"";
        self.memoFieldValueView.string = @"";
        return;
    }
    NSInteger next = MIN(row, (NSInteger)self.editingMemoFields.count - 1);
    [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
    [self loadMemoFieldEditorFromIndex:next];
}

- (void)moveMemoFieldUp:(id)sender {
    (void)sender;
    [self applyMemoFieldEditorToSelection];
    NSInteger row = self.memoFieldsTable.selectedRow;
    if (row <= 0 || row >= (NSInteger)self.editingMemoFields.count) {
        return;
    }
    [self.editingMemoFields exchangeObjectAtIndex:row withObjectAtIndex:row - 1];
    [self.memoFieldsTable reloadData];
    [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
}

- (void)moveMemoFieldDown:(id)sender {
    (void)sender;
    [self applyMemoFieldEditorToSelection];
    NSInteger row = self.memoFieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingMemoFields.count - 1) {
        return;
    }
    [self.editingMemoFields exchangeObjectAtIndex:row withObjectAtIndex:row + 1];
    [self.memoFieldsTable reloadData];
    [self.memoFieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
}

- (void)pickMemoFieldSelector:(id)sender {
    (void)sender;
    [self beginPickForTarget:@"memoField"];
}

@end
