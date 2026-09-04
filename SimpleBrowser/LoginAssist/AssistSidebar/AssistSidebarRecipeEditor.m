#import "AssistSidebarRecipeEditor.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginElementPicker.h"
#import "MeoSiteMatch.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"

/// 翻转坐标系，便于表单自上而下排布。
@interface AssistSidebarRecipeEditorDocumentView : NSView
@end

@implementation AssistSidebarRecipeEditorDocumentView
- (BOOL)isFlipped {
    return YES;
}
@end

/// 内容矮于视口时贴顶，避免拖高详情后表单沉在底部。
@interface AssistSidebarRecipeEditorClipView : NSClipView
@end

@implementation AssistSidebarRecipeEditorClipView
- (BOOL)isFlipped {
    return YES;
}

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect constrained = [super constrainBoundsRect:proposedBounds];
    NSView *doc = self.documentView;
    if (!doc) {
        return constrained;
    }
    CGFloat docHeight = NSHeight(doc.frame);
    CGFloat clipHeight = NSHeight(self.bounds);
    if (docHeight < clipHeight) {
        constrained.origin.y = NSMinY(doc.frame);
    }
    return constrained;
}
@end

@interface AssistSidebarRecipeEditor ()
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, copy, readwrite, nullable) NSString *editingRecipeID;
@property (nonatomic, strong) SBTextField *sitePatternField;
@property (nonatomic, strong) NSTextField *pathHintLabel;
@property (nonatomic, strong) SBTextField *usernameField;
@property (nonatomic, strong) SBSecureTextField *passwordField;
@property (nonatomic, strong) SBTextField *usernameSelectorField;
@property (nonatomic, strong) SBTextField *passwordSelectorField;
@property (nonatomic, strong) SBTextField *submitSelectorField;
@property (nonatomic, strong) NSButton *submitByEnterCheck;
@property (nonatomic, strong) NSButton *autoLoginCheck;
@property (nonatomic, strong) NSButton *defaultCheck;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, assign) BOOL isNewRecipe;
@property (nonatomic, strong) NSStackView *formStack;
@property (nonatomic, strong) NSStackView *extraFieldsStack;
@property (nonatomic, strong) NSMutableArray<LoginRecipeExtraField *> *editingExtraFields;
@property (nonatomic, strong) NSView *usernameRow;
@property (nonatomic, strong) NSView *passwordRow;
@property (nonatomic, strong) NSView *submitSelectorRow;
@property (nonatomic, copy, nullable) NSString *baselineSnapshot;
@end

@implementation AssistSidebarRecipeEditor

- (instancetype)init {
    self = [super init];
    if (self) {
        _editingExtraFields = [NSMutableArray array];
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
    [label.widthAnchor constraintEqualToConstant:44].active = YES;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
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
        [pick setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [views addObject:pick];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

/// 标签 | 选择器 | 点选 | 值（RE-2）
- (NSStackView *)pairedRowWithLabel:(NSString *)label
                      selectorField:(NSView *)selectorField
                         valueField:(NSView *)valueField
                         pickAction:(SEL)pickAction {
    NSTextField *caption = [self caption:label];
    NSButton *pick = [NSButton buttonWithTitle:@"点选"
                                        target:self
                                        action:pickAction];
    pick.bezelStyle = NSBezelStyleRounded;
    pick.controlSize = NSControlSizeMini;
    [pick setContentHuggingPriority:NSLayoutPriorityRequired
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [pick setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];

    if ([selectorField isKindOfClass:[NSTextField class]]) {
        ((NSTextField *)selectorField).placeholderString = @"选择器";
    }
    if ([valueField isKindOfClass:[NSSecureTextField class]]) {
        ((NSSecureTextField *)valueField).placeholderString = @"密码";
    } else if ([valueField isKindOfClass:[NSTextField class]]) {
        ((NSTextField *)valueField).placeholderString = @"填入值";
    }

    // 选择器可压缩；值区略保底宽，避免窄栏下完全挤没。
    [selectorField setContentHuggingPriority:1
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [selectorField setContentCompressionResistancePriority:250
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField setContentHuggingPriority:1
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField setContentCompressionResistancePriority:500
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
    [selectorField.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[caption, selectorField, pick, valueField]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    // 宽比约束须在入栈后激活，否则无共同祖先会抛 NSGenericException（启动无窗口）。
    [NSLayoutConstraint constraintWithItem:selectorField
                                 attribute:NSLayoutAttributeWidth
                                 relatedBy:NSLayoutRelationEqual
                                    toItem:valueField
                                 attribute:NSLayoutAttributeWidth
                                multiplier:1.2
                                  constant:0].active = YES;
    return row;
}

/// 自定义字段行：标签 | 选择器 | 点选 | 值 | −（RE-3）
- (NSStackView *)extraFieldRowForField:(LoginRecipeExtraField *)field {
    SBTextField *labelField = [self makeField];
    labelField.placeholderString = @"标签";
    labelField.stringValue = field.label ?: @"";
    [labelField.widthAnchor constraintEqualToConstant:52].active = YES;
    [labelField setContentHuggingPriority:NSLayoutPriorityRequired
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labelField setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];

    SBTextField *selectorField = [self makeField];
    selectorField.placeholderString = @"选择器";
    selectorField.stringValue = field.selector ?: @"";

    SBTextField *valueField = [self makeField];
    valueField.placeholderString = @"填入值";
    valueField.stringValue = field.value ?: @"";

    NSButton *pick = [NSButton buttonWithTitle:@"点选"
                                        target:self
                                        action:@selector(pickExtraField:)];
    pick.bezelStyle = NSBezelStyleRounded;
    pick.controlSize = NSControlSizeMini;
    pick.identifier = field.fieldID;
    [pick setContentHuggingPriority:NSLayoutPriorityRequired
                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *remove = [NSButton buttonWithTitle:@"−"
                                          target:self
                                          action:@selector(removeExtraField:)];
    remove.bezelStyle = NSBezelStyleRounded;
    remove.controlSize = NSControlSizeMini;
    remove.identifier = field.fieldID;
    [remove setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    [selectorField setContentHuggingPriority:1
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [selectorField setContentCompressionResistancePriority:250
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField setContentHuggingPriority:1
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField setContentCompressionResistancePriority:500
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    [valueField.widthAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
    [selectorField.widthAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[labelField, selectorField, pick, valueField, remove]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.identifier = field.fieldID;
    // 同 pairedRow：入栈后再激活宽比，避免无共同祖先异常。
    [NSLayoutConstraint constraintWithItem:selectorField
                                 attribute:NSLayoutAttributeWidth
                                 relatedBy:NSLayoutRelationEqual
                                    toItem:valueField
                                 attribute:NSLayoutAttributeWidth
                                multiplier:1.2
                                  constant:0].active = YES;
    return row;
}

- (nullable LoginRecipeExtraField *)extraFieldWithID:(NSString *)fieldID {
    if (fieldID.length == 0) {
        return nil;
    }
    for (LoginRecipeExtraField *field in self.editingExtraFields) {
        if ([field.fieldID isEqualToString:fieldID]) {
            return field;
        }
    }
    return nil;
}

- (void)syncExtraFieldsFromUI {
    for (NSView *view in self.extraFieldsStack.arrangedSubviews) {
        if (![view isKindOfClass:[NSStackView class]]) {
            continue;
        }
        NSStackView *row = (NSStackView *)view;
        LoginRecipeExtraField *field = [self extraFieldWithID:row.identifier];
        if (!field || row.arrangedSubviews.count < 4) {
            continue;
        }
        NSView *labelView = row.arrangedSubviews[0];
        NSView *selectorView = row.arrangedSubviews[1];
        NSView *valueView = row.arrangedSubviews[3];
        if ([labelView isKindOfClass:[NSTextField class]]) {
            field.label = ((NSTextField *)labelView).stringValue ?: @"";
        }
        if ([selectorView isKindOfClass:[NSTextField class]]) {
            field.selector = ((NSTextField *)selectorView).stringValue ?: @"";
        }
        if ([valueView isKindOfClass:[NSTextField class]]) {
            field.value = ((NSTextField *)valueView).stringValue ?: @"";
        }
    }
}

- (void)rebuildExtraFieldRows {
    NSArray<NSView *> *old = [self.extraFieldsStack.arrangedSubviews copy];
    for (NSView *v in old) {
        [self.extraFieldsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (LoginRecipeExtraField *field in self.editingExtraFields) {
        NSStackView *row = [self extraFieldRowForField:field];
        [self.extraFieldsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.extraFieldsStack.widthAnchor].active = YES;
    }
}

- (void)addExtraField:(id)sender {
    (void)sender;
    [self syncExtraFieldsFromUI];
    NSString *label = [NSString stringWithFormat:@"字段%lu",
                       (unsigned long)(self.editingExtraFields.count + 1)];
    LoginRecipeExtraField *field = [LoginRecipeExtraField fieldWithLabel:label selector:@"" value:@""];
    [self.editingExtraFields addObject:field];
    [self rebuildExtraFieldRows];
}

- (void)removeExtraField:(id)sender {
    NSButton *button = [sender isKindOfClass:[NSButton class]] ? (NSButton *)sender : nil;
    NSString *fieldID = button.identifier;
    if (fieldID.length == 0) {
        return;
    }
    [self syncExtraFieldsFromUI];
    LoginRecipeExtraField *field = [self extraFieldWithID:fieldID];
    if (field) {
        [self.editingExtraFields removeObject:field];
    }
    [self rebuildExtraFieldRows];
}

- (void)pickExtraField:(id)sender {
    NSButton *button = [sender isKindOfClass:[NSButton class]] ? (NSButton *)sender : nil;
    NSString *fieldID = button.identifier;
    if (fieldID.length == 0) {
        return;
    }
    [self beginPickForTarget:[NSString stringWithFormat:@"extra:%@", fieldID]];
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
    AssistSidebarRecipeEditorClipView *clip = [[AssistSidebarRecipeEditorClipView alloc] initWithFrame:NSZeroRect];
    clip.drawsBackground = NO;
    scroll.contentView = clip;

    NSTextField *heading = [NSTextField labelWithString:@"编辑登录配置"];
    heading.font = [NSFont boldSystemFontOfSize:12];
    heading.translatesAutoresizingMaskIntoConstraints = NO;

    self.sitePatternField = [self makeField];
    self.sitePatternField.placeholderString = @"host:port/login.html 或 host/login/*";
    self.pathHintLabel = [NSTextField wrappingLabelWithString:
        @"完整匹配：主机[:端口][/路径]。路径支持 * / ?；仅写主机（及端口）表示该范围全部路径。"];
    self.pathHintLabel.font = [NSFont systemFontOfSize:10];
    self.pathHintLabel.textColor = [NSColor tertiaryLabelColor];
    self.pathHintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.usernameField = [self makeField];
    self.passwordField = [self makeSecureField];
    self.usernameSelectorField = [self makeField];
    self.passwordSelectorField = [self makeField];
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

    self.statusLabel = [NSTextField wrappingLabelWithString:@"凭证保存在应用内部存储。"];
    self.statusLabel.font = [NSFont systemFontOfSize:10];
    self.statusLabel.textColor = [NSColor tertiaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *extraHeading = [NSTextField labelWithString:@"自定义字段"];
    extraHeading.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    extraHeading.textColor = [NSColor secondaryLabelColor];
    extraHeading.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *addExtra = [NSButton buttonWithTitle:@"＋ 添加字段"
                                            target:self
                                            action:@selector(addExtraField:)];
    addExtra.bezelStyle = NSBezelStyleRounded;
    addExtra.controlSize = NSControlSizeMini;
    [addExtra setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *extraHeaderRow = [NSStackView stackViewWithViews:@[extraHeading, addExtra]];
    extraHeaderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    extraHeaderRow.alignment = NSLayoutAttributeCenterY;
    extraHeaderRow.spacing = 8;
    extraHeaderRow.translatesAutoresizingMaskIntoConstraints = NO;
    [extraHeading setContentHuggingPriority:1
                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.extraFieldsStack = [NSStackView stackViewWithViews:@[]];
    self.extraFieldsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.extraFieldsStack.alignment = NSLayoutAttributeLeading;
    self.extraFieldsStack.spacing = 4;
    self.extraFieldsStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.usernameRow = [self pairedRowWithLabel:@"用户名"
                                 selectorField:self.usernameSelectorField
                                    valueField:self.usernameField
                                    pickAction:@selector(pickUsername:)];
    self.passwordRow = [self pairedRowWithLabel:@"密码"
                                 selectorField:self.passwordSelectorField
                                    valueField:self.passwordField
                                    pickAction:@selector(pickPassword:)];
    self.submitSelectorRow = [self rowWithCaption:@"提交" field:self.submitSelectorField pickAction:@selector(pickSubmit:)];

    // 顺序：匹配路径 → 帐密 → 自定义字段 → 提交方式 → 选项
    self.formStack = [NSStackView stackViewWithViews:@[
        heading,
        [self rowWithCaption:@"匹配" field:self.sitePatternField pickAction:nil],
        self.pathHintLabel,
        self.usernameRow,
        self.passwordRow,
        extraHeaderRow,
        self.extraFieldsStack,
        self.submitSelectorRow,
        self.submitByEnterCheck,
        self.autoLoginCheck,
        self.defaultCheck,
        actionRow,
        self.statusLabel,
    ]];
    NSStackView *stack = self.formStack;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    // 左右内边距改由相对 doc 的约束实现；勿用 edgeInsets+width=stack，会被行宽约束冲掉。
    static const CGFloat kFormHorizontalInset = 20.0;
    stack.edgeInsets = NSEdgeInsetsMake(10, 0, 12, 0);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *row in stack.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    NSView *doc = [[AssistSidebarRecipeEditorDocumentView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:kFormHorizontalInset],
        [stack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-kFormHorizontalInset],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
    ]];
    scroll.documentView = doc;
    // 跟随侧栏内容宽，避免并排行在固定 300pt 下过度挤压。
    [doc.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;

    [root addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
    [self updateSubmitSelectorEnabled];
    self.submitSelectorField.enabled = NO;
}

#pragma mark - Public

- (NSString *)formSnapshotString {
    [self syncExtraFieldsFromUI];
    NSMutableArray *extras = [NSMutableArray array];
    for (LoginRecipeExtraField *field in self.editingExtraFields) {
        [extras addObject:@{
            @"id": field.fieldID ?: @"",
            @"label": field.label ?: @"",
            @"selector": field.selector ?: @"",
            @"value": field.value ?: @"",
            @"enabled": @(field.enabled),
        }];
    }
    NSDictionary *payload = @{
        @"site": self.sitePatternField.stringValue ?: @"",
        @"user": self.usernameField.stringValue ?: @"",
        @"pass": self.passwordField.stringValue ?: @"",
        @"userSel": self.usernameSelectorField.stringValue ?: @"",
        @"passSel": self.passwordSelectorField.stringValue ?: @"",
        @"submitSel": self.submitSelectorField.stringValue ?: @"",
        @"submitByEnter": @(self.submitByEnterCheck.state == NSControlStateValueOn),
        @"autoLogin": @(self.autoLoginCheck.state == NSControlStateValueOn),
        @"isDefault": @(self.defaultCheck.state == NSControlStateValueOn),
        @"extras": extras,
        @"isNew": @(self.isNewRecipe),
        @"recipeID": self.editingRecipeID ?: @"",
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

- (void)captureBaselineSnapshot {
    self.baselineSnapshot = [self formSnapshotString];
}

- (BOOL)hasUnsavedChanges {
    if (self.view.hidden) {
        return NO;
    }
    NSString *baseline = self.baselineSnapshot ?: @"";
    return ![[self formSnapshotString] isEqualToString:baseline];
}

- (void)setSitePatternHost:(NSString *)host port:(NSNumber *)port path:(NSString *)path {
    self.sitePatternField.stringValue =
        [MeoSiteMatch sitePatternForHost:host ?: @"" port:port pathPattern:path] ?: @"";
}

- (void)clear {
    self.editingRecipeID = nil;
    self.isNewRecipe = NO;
    self.sitePatternField.stringValue = @"";
    self.usernameField.stringValue = @"";
    self.passwordField.stringValue = @"";
    self.usernameSelectorField.stringValue = @"input[type=\"text\"], input[type=\"email\"], input[name=\"username\"]";
    self.passwordSelectorField.stringValue = @"input[type=\"password\"]";
    self.submitSelectorField.stringValue = @"button[type=\"submit\"], input[type=\"submit\"]";
    self.submitByEnterCheck.state = NSControlStateValueOn;
    self.autoLoginCheck.state = NSControlStateValueOff;
    self.defaultCheck.state = NSControlStateValueOff;
    self.submitSelectorField.enabled = NO;
    self.deleteButton.enabled = NO;
    [self.editingExtraFields removeAllObjects];
    [self rebuildExtraFieldRows];
    [self updateSubmitSelectorEnabled];
    self.statusLabel.stringValue = @"凭证保存在应用内部存储。";
    [self captureBaselineSnapshot];
}

- (void)loadRecipe:(LoginRecipe *)recipe {
    if (!recipe) {
        [self clear];
        return;
    }
    self.isNewRecipe = NO;
    self.editingRecipeID = recipe.recipeID;
    [self setSitePatternHost:recipe.host port:recipe.port path:recipe.pathPrefix];
    self.usernameSelectorField.stringValue = recipe.usernameSelector ?: @"";
    self.passwordSelectorField.stringValue = recipe.passwordSelector ?: @"";
    self.submitSelectorField.stringValue = recipe.submitSelector ?: @"";
    self.submitByEnterCheck.state = recipe.submitByEnter ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoLoginCheck.state = recipe.autoLogin ? NSControlStateValueOn : NSControlStateValueOff;
    self.defaultCheck.state = recipe.isDefault ? NSControlStateValueOn : NSControlStateValueOff;
    self.deleteButton.enabled = YES;
    [self updateSubmitSelectorEnabled];

    [self.editingExtraFields removeAllObjects];
    for (LoginRecipeExtraField *field in recipe.extraFields) {
        [self.editingExtraFields addObject:[field copy]];
    }
    [self rebuildExtraFieldRows];

    LoginCredentials *credentials = [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID error:nil];
    self.usernameField.stringValue = credentials.username ?: @"";
    self.passwordField.stringValue = credentials.password ?: @"";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"编辑「%@」", self.sitePatternField.stringValue];
    [self captureBaselineSnapshot];
}

- (void)beginNewRecipePrefillingFromCurrentURL {
    [self clear];
    self.isNewRecipe = YES;
    self.deleteButton.enabled = NO;
    NSURL *url = nil;
    if ([self.delegate respondsToSelector:@selector(recipeEditorCurrentURL:)]) {
        url = [self.delegate recipeEditorCurrentURL:self];
    }
    NSString *host = [MeoSiteMatch normalizedHostForURL:url];
    NSNumber *port = [MeoSiteMatch portNumberForURL:url];
    NSString *path = [MeoSiteMatch pathPatternForURL:url];
    [self setSitePatternHost:host port:port path:path];
    self.statusLabel.stringValue = @"已填入当前页完整匹配路径，可改主机/端口/通配后保存。";
    // 保留 clear 的基线，使预填后的新建稿视为未保存。
}

#pragma mark - Submit mode

- (void)updateSubmitSelectorEnabled {
    BOOL showSubmitSelector = (self.submitByEnterCheck.state != NSControlStateValueOn);
    self.submitSelectorRow.hidden = !showSubmitSelector;
    self.submitSelectorField.enabled = showSubmitSelector;
}

- (void)submitModeChanged:(id)sender {
    (void)sender;
    [self updateSubmitSelectorEnabled];
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
        } else if ([target isEqualToString:@"submit"]) {
            strongSelf.submitSelectorField.stringValue = cssSelector;
        } else if ([target hasPrefix:@"extra:"]) {
            NSString *fieldID = [target substringFromIndex:6];
            [strongSelf syncExtraFieldsFromUI];
            LoginRecipeExtraField *field = [strongSelf extraFieldWithID:fieldID];
            if (field) {
                field.selector = cssSelector;
            }
            for (NSView *view in strongSelf.extraFieldsStack.arrangedSubviews) {
                if (![view.identifier isEqualToString:fieldID] || ![view isKindOfClass:[NSStackView class]]) {
                    continue;
                }
                NSStackView *row = (NSStackView *)view;
                if (row.arrangedSubviews.count > 1 && [row.arrangedSubviews[1] isKindOfClass:[NSTextField class]]) {
                    ((NSTextField *)row.arrangedSubviews[1]).stringValue = cssSelector;
                }
                break;
            }
        }
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
    }];
}

- (void)pickUsername:(id)sender { (void)sender; [self beginPickForTarget:@"username"]; }
- (void)pickPassword:(id)sender { (void)sender; [self beginPickForTarget:@"password"]; }
- (void)pickSubmit:(id)sender { (void)sender; [self beginPickForTarget:@"submit"]; }

#pragma mark - Save / Delete

- (void)saveClicked:(id)sender {
    (void)sender;
    [self saveIfPossible];
}

- (BOOL)saveIfPossible {
    NSString *raw = self.sitePatternField.stringValue;
    NSString *host = nil;
    NSNumber *port = nil;
    NSString *path = nil;
    if (![MeoSiteMatch parseSitePattern:raw host:&host port:&port pathPattern:&path] || host.length == 0) {
        self.statusLabel.stringValue = @"请填写完整匹配，例如 host:56546/login.html";
        return NO;
    }
    LoginRecipe *recipe = nil;
    if (self.editingRecipeID.length > 0) {
        recipe = [[[LoginRecipeStore sharedStore] recipeWithID:self.editingRecipeID] copy];
    }
    NSString *autoTitle = [MeoSiteMatch sitePatternForHost:host port:port pathPattern:path];
    if (!recipe) {
        recipe = [LoginRecipe recipeWithHost:host title:autoTitle];
    }
    recipe.title = autoTitle;
    recipe.host = host;
    recipe.port = port;
    recipe.pathPrefix = path.length > 0 ? path : nil;
    recipe.pathMatchMode = [MeoSiteMatch inferredPathMatchModeForPattern:recipe.pathPrefix];
    recipe.usernameSelector = self.usernameSelectorField.stringValue;
    recipe.passwordSelector = self.passwordSelectorField.stringValue;
    recipe.submitSelector = self.submitSelectorField.stringValue;
    recipe.submitByEnter = (self.submitByEnterCheck.state == NSControlStateValueOn);
    recipe.autoLogin = (self.autoLoginCheck.state == NSControlStateValueOn);
    recipe.isDefault = (self.defaultCheck.state == NSControlStateValueOn);

    [self syncExtraFieldsFromUI];
    NSMutableArray<LoginRecipeExtraField *> *extras = [NSMutableArray arrayWithCapacity:self.editingExtraFields.count];
    for (LoginRecipeExtraField *field in self.editingExtraFields) {
        LoginRecipeExtraField *copy = [field copy];
        if (copy.label.length == 0) {
            copy.label = @"字段";
        }
        [extras addObject:copy];
    }
    recipe.extraFields = extras;

    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = self.usernameField.stringValue ?: @"";
    credentials.password = self.passwordField.stringValue ?: @"";
    credentials.phone = @"";

    NSError *error = nil;
    if (![[LoginCredentialStore sharedStore] saveCredentials:credentials
                                                 forRecipeID:recipe.recipeID
                                                       error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"凭证保存失败";
        return NO;
    }
    if (![[LoginRecipeStore sharedStore] upsertRecipe:recipe error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存失败";
        return NO;
    }
    self.isNewRecipe = NO;
    self.editingRecipeID = recipe.recipeID;
    self.deleteButton.enabled = YES;
    self.statusLabel.stringValue = @"已保存。";
    [self captureBaselineSnapshot];
    if ([self.delegate respondsToSelector:@selector(recipeEditor:didSaveRecipe:)]) {
        [self.delegate recipeEditor:self didSaveRecipe:recipe];
    }
    return YES;
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
    alert.informativeText = @"将同时删除本地保存的账号密码。";
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
