#import "AssistSidebarRecipeEditor.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginElementPicker.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"

@interface AssistSidebarRecipeEditor ()
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, copy, readwrite, nullable) NSString *editingRecipeID;
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
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, assign) BOOL isNewRecipe;
@end

@implementation AssistSidebarRecipeEditor

- (instancetype)init {
    self = [super init];
    if (self) {
        [self buildUI];
    }
    return self;
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
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:64].active = YES;
    return label;
}

- (NSStackView *)rowWithCaption:(NSString *)caption
                          field:(NSView *)field
                     pickAction:(nullable SEL)pickAction {
    NSMutableArray *views = [NSMutableArray arrayWithObjects:[self caption:caption], field, nil];
    if (pickAction) {
        NSButton *pick = [NSButton buttonWithTitle:@"点选"
                                            target:self
                                            action:pickAction];
        pick.bezelStyle = NSBezelStyleRounded;
        pick.controlSize = NSControlSizeMini;
        [views addObject:pick];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    if (@available(macOS 10.14, *)) {
        root.layer.backgroundColor = [[NSColor separatorColor] colorWithAlphaComponent:0.12].CGColor;
    }

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    NSTextField *heading = [NSTextField labelWithString:@"编辑登录配置"];
    heading.font = [NSFont boldSystemFontOfSize:12];
    heading.translatesAutoresizingMaskIntoConstraints = NO;

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
    self.modePopup.controlSize = NSControlSizeSmall;

    self.usernameField = [self makeField];
    self.passwordField = [self makeSecureField];
    self.phoneField = [self makeField];
    self.usernameSelectorField = [self makeField];
    self.passwordSelectorField = [self makeField];
    self.phoneSelectorField = [self makeField];
    self.otpSelectorField = [self makeField];
    self.sendCodeSelectorField = [self makeField];
    self.submitSelectorField = [self makeField];

    self.submitByEnterCheck = [NSButton checkboxWithTitle:@"回车提交（否则点提交选择器）"
                                                   target:self
                                                   action:@selector(submitModeChanged:)];
    self.submitByEnterCheck.font = [NSFont systemFontOfSize:11];
    self.autoLoginCheck = [NSButton checkboxWithTitle:@"自动登录"
                                               target:nil
                                               action:nil];
    self.autoLoginCheck.font = [NSFont systemFontOfSize:11];
    self.defaultCheck = [NSButton checkboxWithTitle:@"设为默认"
                                             target:nil
                                             action:nil];
    self.defaultCheck.font = [NSFont systemFontOfSize:11];

    NSTextField *modeCaption = [self caption:@"方式"];
    NSStackView *modeRow = [NSStackView stackViewWithViews:@[modeCaption, self.modePopup]];
    modeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    modeRow.alignment = NSLayoutAttributeCenterY;
    modeRow.spacing = 6;
    modeRow.translatesAutoresizingMaskIntoConstraints = NO;

    self.saveButton = [NSButton buttonWithTitle:@"保存"
                                         target:self
                                         action:@selector(saveClicked:)];
    self.saveButton.bezelStyle = NSBezelStyleRounded;
    self.saveButton.controlSize = NSControlSizeSmall;
    self.deleteButton = [NSButton buttonWithTitle:@"删除"
                                           target:self
                                           action:@selector(deleteClicked:)];
    self.deleteButton.bezelStyle = NSBezelStyleRounded;
    self.deleteButton.controlSize = NSControlSizeSmall;
    NSStackView *actionRow = [NSStackView stackViewWithViews:@[self.saveButton, self.deleteButton]];
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.spacing = 8;
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [NSTextField wrappingLabelWithString:@"凭证保存在本地钥匙串。"];
    self.statusLabel.font = [NSFont systemFontOfSize:10];
    self.statusLabel.textColor = [NSColor tertiaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        heading,
        [self rowWithCaption:@"名称" field:self.titleField pickAction:nil],
        [self rowWithCaption:@"主机" field:self.hostField pickAction:nil],
        [self rowWithCaption:@"路径" field:self.pathPrefixField pickAction:nil],
        modeRow,
        [self rowWithCaption:@"用户名" field:self.usernameField pickAction:nil],
        [self rowWithCaption:@"密码" field:self.passwordField pickAction:nil],
        [self rowWithCaption:@"手机号" field:self.phoneField pickAction:nil],
        [self rowWithCaption:@"用户选择器" field:self.usernameSelectorField pickAction:@selector(pickUsername:)],
        [self rowWithCaption:@"密码选择器" field:self.passwordSelectorField pickAction:@selector(pickPassword:)],
        [self rowWithCaption:@"手机选择器" field:self.phoneSelectorField pickAction:@selector(pickPhone:)],
        [self rowWithCaption:@"验证码" field:self.otpSelectorField pickAction:@selector(pickOTP:)],
        [self rowWithCaption:@"发码按钮" field:self.sendCodeSelectorField pickAction:@selector(pickSend:)],
        [self rowWithCaption:@"提交" field:self.submitSelectorField pickAction:@selector(pickSubmit:)],
        self.submitByEnterCheck,
        self.autoLoginCheck,
        self.defaultCheck,
        actionRow,
        self.statusLabel,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 5;
    stack.edgeInsets = NSEdgeInsetsMake(8, 10, 8, 10);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *row in stack.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    NSView *doc = [[NSView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
        [stack.widthAnchor constraintEqualToConstant:300],
    ]];
    scroll.documentView = doc;

    [root addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
    [self updateSMSFieldsEnabled];
    self.submitSelectorField.enabled = NO;
}

#pragma mark - Public

- (void)clear {
    self.editingRecipeID = nil;
    self.isNewRecipe = NO;
    self.titleField.stringValue = @"";
    self.hostField.stringValue = @"";
    self.pathPrefixField.stringValue = @"";
    [self.modePopup selectItemAtIndex:0];
    self.usernameField.stringValue = @"";
    self.passwordField.stringValue = @"";
    self.phoneField.stringValue = @"";
    self.usernameSelectorField.stringValue = @"input[type=\"text\"], input[type=\"email\"], input[name=\"username\"]";
    self.passwordSelectorField.stringValue = @"input[type=\"password\"]";
    self.phoneSelectorField.stringValue = @"input[type=\"tel\"], input[name*=\"phone\"]";
    self.otpSelectorField.stringValue = @"input[autocomplete=\"one-time-code\"]";
    self.sendCodeSelectorField.stringValue = @"";
    self.submitSelectorField.stringValue = @"button[type=\"submit\"], input[type=\"submit\"]";
    self.submitByEnterCheck.state = NSControlStateValueOn;
    self.autoLoginCheck.state = NSControlStateValueOff;
    self.defaultCheck.state = NSControlStateValueOff;
    self.submitSelectorField.enabled = NO;
    self.deleteButton.enabled = NO;
    [self updateSMSFieldsEnabled];
    self.statusLabel.stringValue = @"凭证保存在本地钥匙串。";
}

- (void)loadRecipe:(LoginRecipe *)recipe {
    if (!recipe) {
        [self clear];
        return;
    }
    self.isNewRecipe = NO;
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
    self.deleteButton.enabled = YES;

    LoginCredentials *credentials = [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID error:nil];
    self.usernameField.stringValue = credentials.username ?: @"";
    self.passwordField.stringValue = credentials.password ?: @"";
    self.phoneField.stringValue = credentials.phone ?: @"";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"编辑「%@」",
                                    recipe.title.length > 0 ? recipe.title : recipe.host];
}

- (void)beginNewRecipePrefillingFromCurrentURL {
    [self clear];
    self.isNewRecipe = YES;
    self.deleteButton.enabled = NO;
    NSURL *url = nil;
    if ([self.delegate respondsToSelector:@selector(recipeEditorCurrentURL:)]) {
        url = [self.delegate recipeEditorCurrentURL:self];
    }
    if (url.isFileURL) {
        self.hostField.stringValue = @"file";
        self.titleField.stringValue = @"本地测试页";
        if (url.path.lastPathComponent.length > 0) {
            self.pathPrefixField.stringValue = url.path.lastPathComponent;
        }
    } else if (url.host.length > 0) {
        self.hostField.stringValue = url.host.lowercaseString;
        self.titleField.stringValue = url.host;
    }
    self.statusLabel.stringValue = @"新建登录：填写后点「保存」。";
}

#pragma mark - Mode

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
    if ([[self selectedMode] isEqualToString:LoginRecipeModeSMSOTP]) {
        self.usernameSelectorField.stringValue = @"";
        self.passwordSelectorField.stringValue = @"";
        self.usernameField.stringValue = @"";
        self.passwordField.stringValue = @"";
        self.statusLabel.stringValue = @"短信模式：请配置手机号与验证码选择器。";
    }
}

- (void)updateSMSFieldsEnabled {
    BOOL sms = ![[self selectedMode] isEqualToString:LoginRecipeModePassword];
    self.phoneField.enabled = sms;
    self.phoneSelectorField.enabled = sms;
    self.otpSelectorField.enabled = sms;
    self.sendCodeSelectorField.enabled = sms;
}

- (void)submitModeChanged:(id)sender {
    (void)sender;
    self.submitSelectorField.enabled = (self.submitByEnterCheck.state != NSControlStateValueOn);
}

#pragma mark - Pick

- (void)beginPickForTarget:(NSString *)target {
    WKWebView *webView = nil;
    if ([self.delegate respondsToSelector:@selector(recipeEditorWebViewForPicking:)]) {
        webView = [self.delegate recipeEditorWebViewForPicking:self];
    }
    if (!webView) {
        self.statusLabel.stringValue = @"请先打开要拾取的页面。";
        return;
    }
    self.statusLabel.stringValue = @"在页面上点击目标元素；Esc 取消。";
    [self.view.window orderBack:nil];
    __weak typeof(self) weakSelf = self;
    [LoginElementPicker startPickingInWebView:webView completion:^(NSString *cssSelector, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.view.window makeKeyAndOrderFront:nil];
        if (cancelled || cssSelector.length == 0) {
            strongSelf.statusLabel.stringValue = @"已取消拾取。";
            return;
        }
        if ([target isEqualToString:@"username"]) {
            strongSelf.usernameSelectorField.stringValue = cssSelector;
        } else if ([target isEqualToString:@"password"]) {
            strongSelf.passwordSelectorField.stringValue = cssSelector;
        } else if ([target isEqualToString:@"phone"]) {
            strongSelf.phoneSelectorField.stringValue = cssSelector;
        } else if ([target isEqualToString:@"otp"]) {
            strongSelf.otpSelectorField.stringValue = cssSelector;
        } else if ([target isEqualToString:@"send"]) {
            strongSelf.sendCodeSelectorField.stringValue = cssSelector;
        } else if ([target isEqualToString:@"submit"]) {
            strongSelf.submitSelectorField.stringValue = cssSelector;
        }
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
    }];
}

- (void)pickUsername:(id)sender { (void)sender; [self beginPickForTarget:@"username"]; }
- (void)pickPassword:(id)sender { (void)sender; [self beginPickForTarget:@"password"]; }
- (void)pickPhone:(id)sender { (void)sender; [self beginPickForTarget:@"phone"]; }
- (void)pickOTP:(id)sender { (void)sender; [self beginPickForTarget:@"otp"]; }
- (void)pickSend:(id)sender { (void)sender; [self beginPickForTarget:@"send"]; }
- (void)pickSubmit:(id)sender { (void)sender; [self beginPickForTarget:@"submit"]; }

#pragma mark - Save / Delete

- (void)saveClicked:(id)sender {
    (void)sender;
    NSString *host = [self.hostField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (host.length == 0) {
        self.statusLabel.stringValue = @"请填写主机名。";
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
            self.statusLabel.stringValue = @"短信登录请配置手机号选择器。";
            return;
        }
        if (self.phoneField.stringValue.length == 0) {
            self.statusLabel.stringValue = @"请填写手机号。";
            return;
        }
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
    self.isNewRecipe = NO;
    self.editingRecipeID = recipe.recipeID;
    self.deleteButton.enabled = YES;
    self.statusLabel.stringValue = @"已保存。";
    if ([self.delegate respondsToSelector:@selector(recipeEditor:didSaveRecipe:)]) {
        [self.delegate recipeEditor:self didSaveRecipe:recipe];
    }
}

- (void)deleteClicked:(id)sender {
    (void)sender;
    if (self.isNewRecipe || self.editingRecipeID.length == 0) {
        [self clear];
        if ([self.delegate respondsToSelector:@selector(recipeEditorDidCancelNew:)]) {
            [self.delegate recipeEditorDidCancelNew:self];
        }
        return;
    }
    NSString *recipeID = self.editingRecipeID;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除此登录配置？";
    alert.informativeText = @"将同时删除钥匙串中的账号密码。";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertFirstButtonReturn) {
            return;
        }
        [[LoginRecipeStore sharedStore] deleteRecipeWithID:recipeID error:nil];
        [weakSelf clear];
        if ([weakSelf.delegate respondsToSelector:@selector(recipeEditor:didDeleteRecipeID:)]) {
            [weakSelf.delegate recipeEditor:weakSelf didDeleteRecipeID:recipeID];
        }
    }];
}

@end
