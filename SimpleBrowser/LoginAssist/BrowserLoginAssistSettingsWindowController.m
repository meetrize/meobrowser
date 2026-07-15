#import "BrowserLoginAssistSettingsWindowController.h"
#import "LoginAssistController.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginElementPicker.h"
#import "LoginAssistPreferences.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import <WebKit/WebKit.h>

@interface BrowserLoginAssistSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<LoginRecipe *> *recipes;
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *hostField;
@property (nonatomic, strong) SBTextField *pathPrefixField;
@property (nonatomic, strong) SBTextField *usernameField;
@property (nonatomic, strong) SBSecureTextField *passwordField;
@property (nonatomic, strong) SBTextField *usernameSelectorField;
@property (nonatomic, strong) SBTextField *passwordSelectorField;
@property (nonatomic, strong) SBTextField *submitSelectorField;
@property (nonatomic, strong) NSButton *submitByEnterCheck;
@property (nonatomic, strong) NSButton *autoLoginCheck;
@property (nonatomic, strong) NSButton *defaultCheck;
@property (nonatomic, strong) NSButton *inlineAssistCheck;
@property (nonatomic, strong) NSButton *promptSaveCheck;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy, nullable) NSString *editingRecipeID;
@property (nonatomic, copy, nullable) NSString *pickingTarget;
@end

@implementation BrowserLoginAssistSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 580)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"登录助手";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(640, 520);
    self = [super initWithWindow:window];
    if (self) {
        _recipes = @[];
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recipesDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
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
    self.usernameField = [self makeField];
    self.passwordField = [self makeSecureField];
    self.usernameSelectorField = [self makeField];
    self.passwordSelectorField = [self makeField];
    self.submitSelectorField = [self makeField];

    self.submitByEnterCheck = [NSButton checkboxWithTitle:@"密码框回车提交（否则点击提交按钮）"
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
    self.statusLabel.preferredMaxLayoutWidth = 420;

    NSStackView *form = [NSStackView stackViewWithViews:@[
        [self labeledRow:@"名称" field:self.titleField pickAction:nil],
        [self labeledRow:@"主机" field:self.hostField pickAction:nil],
        [self labeledRow:@"路径前缀" field:self.pathPrefixField pickAction:nil],
        [self labeledRow:@"用户名" field:self.usernameField pickAction:nil],
        [self labeledRow:@"密码" field:self.passwordField pickAction:nil],
        [self labeledRow:@"用户名选择器" field:self.usernameSelectorField pickAction:@selector(pickUsernameSelector:)],
        [self labeledRow:@"密码选择器" field:self.passwordSelectorField pickAction:@selector(pickPasswordSelector:)],
        [self labeledRow:@"提交选择器" field:self.submitSelectorField pickAction:@selector(pickSubmitSelector:)],
        self.submitByEnterCheck,
        self.autoLoginCheck,
        self.defaultCheck,
        saveButton,
        self.inlineAssistCheck,
        self.promptSaveCheck,
        self.statusLabel,
    ]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 10;
    form.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *row in form.arrangedSubviews) {
        if ([row isKindOfClass:[NSStackView class]]) {
            [row.widthAnchor constraintEqualToAnchor:form.widthAnchor].active = YES;
        }
    }

    NSStackView *root = [NSStackView stackViewWithViews:@[listColumn, form]];
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
        [form.widthAnchor constraintGreaterThanOrEqualToConstant:420],
    ]];

    [self reloadRecipes];
    [self clearForm];
}

- (void)reloadRecipes {
    self.recipes = [[LoginRecipeStore sharedStore] allRecipes];
    [self.tableView reloadData];
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
    self.usernameField.stringValue = @"";
    self.passwordField.stringValue = @"";
    self.usernameSelectorField.stringValue = @"input[type=\"text\"], input[type=\"email\"], input[name=\"username\"]";
    self.passwordSelectorField.stringValue = @"input[type=\"password\"]";
    self.submitSelectorField.stringValue = @"button[type=\"submit\"], input[type=\"submit\"]";
    self.submitByEnterCheck.state = NSControlStateValueOff;
    self.autoLoginCheck.state = NSControlStateValueOff;
    self.defaultCheck.state = NSControlStateValueOff;
    self.submitSelectorField.enabled = YES;
    self.statusLabel.stringValue = @"凭证保存在本地钥匙串；清除「网站数据」不会删除登录配置。";
}

- (void)loadRecipeIntoForm:(LoginRecipe *)recipe {
    self.editingRecipeID = recipe.recipeID;
    self.titleField.stringValue = recipe.title ?: @"";
    self.hostField.stringValue = recipe.host ?: @"";
    self.pathPrefixField.stringValue = recipe.pathPrefix ?: @"";
    self.usernameSelectorField.stringValue = recipe.usernameSelector ?: @"";
    self.passwordSelectorField.stringValue = recipe.passwordSelector ?: @"";
    self.submitSelectorField.stringValue = recipe.submitSelector ?: @"";
    self.submitByEnterCheck.state = recipe.submitByEnter ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoLoginCheck.state = recipe.autoLogin ? NSControlStateValueOn : NSControlStateValueOff;
    self.defaultCheck.state = recipe.isDefault ? NSControlStateValueOn : NSControlStateValueOff;
    self.submitSelectorField.enabled = !recipe.submitByEnter;

    NSString *username = nil;
    NSString *password = nil;
    [[LoginCredentialStore sharedStore] loadUsername:&username password:&password forRecipeID:recipe.recipeID error:nil];
    self.usernameField.stringValue = username ?: @"";
    self.passwordField.stringValue = password ?: @"";
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
    recipe.mode = LoginRecipeModePassword;

    NSError *error = nil;
    if (![[LoginRecipeStore sharedStore] upsertRecipe:recipe error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存失败";
        return;
    }
    if (![[LoginCredentialStore sharedStore] saveUsername:self.usernameField.stringValue
                                                 password:self.passwordField.stringValue
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
        } else if ([strongSelf.pickingTarget isEqualToString:@"submit"]) {
            strongSelf.submitSelectorField.stringValue = cssSelector;
        }
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
        strongSelf.pickingTarget = nil;
    }];
}

- (void)showWindow:(id)sender {
    [self reloadRecipes];
    [super showWindow:sender];
}

@end
