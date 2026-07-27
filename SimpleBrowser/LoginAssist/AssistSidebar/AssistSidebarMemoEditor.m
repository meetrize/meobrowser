#import "AssistSidebarMemoEditor.h"
#import "FormMemo.h"
#import "FormMemoStore.h"
#import "LoginElementPicker.h"
#import "SBTextField.h"
#import "SBTextView.h"
#import <WebKit/WebKit.h>

@interface AssistSidebarMemoEditor () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, copy, readwrite, nullable) NSString *editingMemoID;
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *hostField;
@property (nonatomic, strong) SBTextField *pathPrefixField;
@property (nonatomic, strong) NSButton *defaultCheck;
@property (nonatomic, strong) NSTableView *fieldsTable;
@property (nonatomic, strong) NSMutableArray<FormMemoField *> *editingFields;
@property (nonatomic, strong) SBTextField *fieldLabelField;
@property (nonatomic, strong) SBTextField *fieldSelectorField;
@property (nonatomic, strong) SBTextView *fieldValueView;
@property (nonatomic, strong) NSScrollView *fieldValueScroll;
@property (nonatomic, strong) NSButton *fieldEnabledCheck;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, assign) BOOL isNewMemo;
@end

@implementation AssistSidebarMemoEditor

- (instancetype)init {
    self = [super init];
    if (self) {
        _editingFields = [NSMutableArray array];
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

- (NSTextField *)caption:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:52].active = YES;
    return label;
}

- (NSStackView *)rowWithCaption:(NSString *)caption field:(NSView *)field {
    NSStackView *row = [NSStackView stackViewWithViews:@[[self caption:caption], field]];
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

    NSTextField *heading = [NSTextField labelWithString:@"编辑站点备忘"];
    heading.font = [NSFont boldSystemFontOfSize:12];
    heading.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleField = [self makeField];
    self.hostField = [self makeField];
    self.pathPrefixField = [self makeField];
    self.defaultCheck = [NSButton checkboxWithTitle:@"设为默认"
                                             target:nil
                                             action:nil];
    self.defaultCheck.font = [NSFont systemFontOfSize:11];
    self.defaultCheck.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *fieldsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    fieldsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    fieldsScroll.hasVerticalScroller = YES;
    fieldsScroll.borderType = NSBezelBorder;
    self.fieldsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"field"];
    col.width = 280;
    [self.fieldsTable addTableColumn:col];
    self.fieldsTable.headerView = nil;
    self.fieldsTable.delegate = self;
    self.fieldsTable.dataSource = self;
    self.fieldsTable.target = self;
    self.fieldsTable.action = @selector(fieldSelectionChanged:);
    fieldsScroll.documentView = self.fieldsTable;
    [fieldsScroll.heightAnchor constraintEqualToConstant:72].active = YES;

    NSButton *addField = [NSButton buttonWithTitle:@"＋"
                                            target:self
                                            action:@selector(addField:)];
    addField.bezelStyle = NSBezelStyleRounded;
    addField.controlSize = NSControlSizeMini;
    NSButton *removeField = [NSButton buttonWithTitle:@"－"
                                               target:self
                                               action:@selector(removeField:)];
    removeField.bezelStyle = NSBezelStyleRounded;
    removeField.controlSize = NSControlSizeMini;
    NSButton *moveUp = [NSButton buttonWithTitle:@"↑"
                                          target:self
                                          action:@selector(moveFieldUp:)];
    moveUp.bezelStyle = NSBezelStyleRounded;
    moveUp.controlSize = NSControlSizeMini;
    NSButton *moveDown = [NSButton buttonWithTitle:@"↓"
                                            target:self
                                            action:@selector(moveFieldDown:)];
    moveDown.bezelStyle = NSBezelStyleRounded;
    moveDown.controlSize = NSControlSizeMini;
    NSStackView *fieldButtons = [NSStackView stackViewWithViews:@[addField, removeField, moveUp, moveDown]];
    fieldButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fieldButtons.spacing = 4;
    fieldButtons.translatesAutoresizingMaskIntoConstraints = NO;

    self.fieldLabelField = [self makeField];
    self.fieldSelectorField = [self makeField];
    self.fieldEnabledCheck = [NSButton checkboxWithTitle:@"启用"
                                                  target:self
                                                  action:@selector(applyFieldEditor:)];
    self.fieldEnabledCheck.font = [NSFont systemFontOfSize:11];
    self.fieldEnabledCheck.translatesAutoresizingMaskIntoConstraints = NO;

    self.fieldValueView = [SBTextView standardTextView];
    self.fieldValueView.delegate = self;
    self.fieldValueView.font = [NSFont systemFontOfSize:12];
    self.fieldValueScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.fieldValueScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.fieldValueScroll.hasVerticalScroller = YES;
    self.fieldValueScroll.borderType = NSBezelBorder;
    self.fieldValueScroll.documentView = self.fieldValueView;
    [self.fieldValueScroll.heightAnchor constraintEqualToConstant:48].active = YES;

    NSButton *pick = [NSButton buttonWithTitle:@"点选"
                                        target:self
                                        action:@selector(pickSelector:)];
    pick.bezelStyle = NSBezelStyleRounded;
    pick.controlSize = NSControlSizeMini;
    NSButton *applyField = [NSButton buttonWithTitle:@"应用字段"
                                              target:self
                                              action:@selector(applyFieldEditor:)];
    applyField.bezelStyle = NSBezelStyleRounded;
    applyField.controlSize = NSControlSizeMini;
    NSStackView *pickRow = [NSStackView stackViewWithViews:@[applyField, pick]];
    pickRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pickRow.spacing = 6;
    pickRow.translatesAutoresizingMaskIntoConstraints = NO;

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

    self.statusLabel = [NSTextField wrappingLabelWithString:@"勿存放密码；密码请用登录配置。"];
    self.statusLabel.font = [NSFont systemFontOfSize:10];
    self.statusLabel.textColor = [NSColor tertiaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        heading,
        [self rowWithCaption:@"名称" field:self.titleField],
        [self rowWithCaption:@"主机" field:self.hostField],
        [self rowWithCaption:@"路径" field:self.pathPrefixField],
        self.defaultCheck,
        fieldsScroll,
        fieldButtons,
        [self rowWithCaption:@"标签" field:self.fieldLabelField],
        [self rowWithCaption:@"选择器" field:self.fieldSelectorField],
        [self rowWithCaption:@"内容" field:self.fieldValueScroll],
        self.fieldEnabledCheck,
        pickRow,
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

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
}

#pragma mark - Public

- (void)clear {
    self.editingMemoID = nil;
    self.isNewMemo = NO;
    self.titleField.stringValue = @"";
    self.hostField.stringValue = @"";
    self.pathPrefixField.stringValue = @"";
    self.defaultCheck.state = NSControlStateValueOff;
    [self.editingFields removeAllObjects];
    [self.fieldsTable reloadData];
    self.fieldLabelField.stringValue = @"";
    self.fieldSelectorField.stringValue = @"";
    self.fieldValueView.string = @"";
    self.fieldEnabledCheck.state = NSControlStateValueOn;
    self.deleteButton.enabled = NO;
    self.statusLabel.stringValue = @"勿存放密码；密码请用登录配置。";
}

- (void)loadMemo:(FormMemo *)memo {
    if (!memo) {
        [self clear];
        return;
    }
    self.isNewMemo = NO;
    self.editingMemoID = memo.memoID;
    self.titleField.stringValue = memo.title ?: @"";
    self.hostField.stringValue = memo.host ?: @"";
    self.pathPrefixField.stringValue = memo.pathPrefix ?: @"";
    self.defaultCheck.state = memo.isDefault ? NSControlStateValueOn : NSControlStateValueOff;
    [self.editingFields removeAllObjects];
    for (FormMemoField *field in memo.fields) {
        [self.editingFields addObject:[field copy]];
    }
    [self.fieldsTable reloadData];
    self.deleteButton.enabled = YES;
    if (self.editingFields.count > 0) {
        [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self loadFieldEditorFromIndex:0];
    } else {
        self.fieldLabelField.stringValue = @"";
        self.fieldSelectorField.stringValue = @"";
        self.fieldValueView.string = @"";
        self.fieldEnabledCheck.state = NSControlStateValueOn;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"编辑「%@」· %lu 字段",
                                    memo.title.length > 0 ? memo.title : memo.host,
                                    (unsigned long)memo.fields.count];
}

- (void)beginNewMemoPrefillingFromCurrentURL {
    [self clear];
    self.isNewMemo = YES;
    self.deleteButton.enabled = NO;
    NSURL *url = nil;
    if ([self.delegate respondsToSelector:@selector(memoEditorCurrentURL:)]) {
        url = [self.delegate memoEditorCurrentURL:self];
    }
    if (url.isFileURL) {
        self.hostField.stringValue = @"file";
        self.titleField.stringValue = @"本地表单备忘";
        if (url.path.lastPathComponent.length > 0) {
            self.pathPrefixField.stringValue = url.path.lastPathComponent;
        }
    } else if (url.host.length > 0) {
        self.hostField.stringValue = url.host.lowercaseString;
        self.titleField.stringValue = url.host;
    }
    FormMemoField *seed = [FormMemoField fieldWithLabel:@"字段1" selector:@"" value:@""];
    [self.editingFields addObject:seed];
    [self.fieldsTable reloadData];
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self loadFieldEditorFromIndex:0];
    self.statusLabel.stringValue = @"新建备忘：填写后点「保存」。";
}

#pragma mark - Fields table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.editingFields.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    NSString *identifier = @"MemoFieldRow";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;
        NSTextField *text = [NSTextField labelWithString:@""];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.font = [NSFont systemFontOfSize:11];
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:text];
        cell.textField = text;
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    if (row >= 0 && row < (NSInteger)self.editingFields.count) {
        FormMemoField *field = self.editingFields[row];
        NSString *label = field.label.length > 0 ? field.label : @"未命名";
        NSString *sel = field.selector.length > 0 ? field.selector : @"（无选择器）";
        cell.textField.stringValue = [NSString stringWithFormat:@"%@ · %@", label, sel];
        cell.textField.textColor = field.enabled ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
    }
    return cell;
}

- (void)fieldSelectionChanged:(id)sender {
    (void)sender;
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingFields.count) {
        return;
    }
    [self loadFieldEditorFromIndex:row];
}

- (void)loadFieldEditorFromIndex:(NSInteger)index {
    FormMemoField *field = self.editingFields[index];
    self.fieldLabelField.stringValue = field.label ?: @"";
    self.fieldSelectorField.stringValue = field.selector ?: @"";
    self.fieldValueView.string = field.value ?: @"";
    self.fieldEnabledCheck.state = field.enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyFieldEditor:(id)sender {
    (void)sender;
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingFields.count) {
        return;
    }
    FormMemoField *field = self.editingFields[row];
    field.label = self.fieldLabelField.stringValue ?: @"";
    field.selector = self.fieldSelectorField.stringValue ?: @"";
    field.value = self.fieldValueView.string ?: @"";
    field.enabled = (self.fieldEnabledCheck.state == NSControlStateValueOn);
    [self.fieldsTable reloadData];
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.fieldValueView) {
        [self applyFieldEditor:nil];
    }
}

- (void)addField:(id)sender {
    (void)sender;
    [self applyFieldEditor:nil];
    FormMemoField *field = [FormMemoField fieldWithLabel:[NSString stringWithFormat:@"字段%lu",
                                                          (unsigned long)(self.editingFields.count + 1)]
                                                selector:@""
                                                   value:@""];
    [self.editingFields addObject:field];
    [self.fieldsTable reloadData];
    NSInteger row = (NSInteger)self.editingFields.count - 1;
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self loadFieldEditorFromIndex:row];
}

- (void)removeField:(id)sender {
    (void)sender;
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingFields.count) {
        return;
    }
    [self.editingFields removeObjectAtIndex:row];
    [self.fieldsTable reloadData];
    if (self.editingFields.count == 0) {
        self.fieldLabelField.stringValue = @"";
        self.fieldSelectorField.stringValue = @"";
        self.fieldValueView.string = @"";
        return;
    }
    NSInteger next = MIN(row, (NSInteger)self.editingFields.count - 1);
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
    [self loadFieldEditorFromIndex:next];
}

- (void)moveFieldUp:(id)sender {
    (void)sender;
    [self applyFieldEditor:nil];
    NSInteger row = self.fieldsTable.selectedRow;
    if (row <= 0 || row >= (NSInteger)self.editingFields.count) {
        return;
    }
    [self.editingFields exchangeObjectAtIndex:row withObjectAtIndex:row - 1];
    [self.fieldsTable reloadData];
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
}

- (void)moveFieldDown:(id)sender {
    (void)sender;
    [self applyFieldEditor:nil];
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editingFields.count - 1) {
        return;
    }
    [self.editingFields exchangeObjectAtIndex:row withObjectAtIndex:row + 1];
    [self.fieldsTable reloadData];
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
}

- (void)pickSelector:(id)sender {
    (void)sender;
    WKWebView *webView = nil;
    if ([self.delegate respondsToSelector:@selector(memoEditorWebViewForPicking:)]) {
        webView = [self.delegate memoEditorWebViewForPicking:self];
    }
    if (!webView) {
        self.statusLabel.stringValue = @"请先打开要拾取的页面。";
        return;
    }
    [self applyFieldEditor:nil];
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
        strongSelf.fieldSelectorField.stringValue = cssSelector;
        [strongSelf applyFieldEditor:nil];
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已拾取：%@", cssSelector];
    }];
}

#pragma mark - Save / Delete

- (void)saveClicked:(id)sender {
    (void)sender;
    [self applyFieldEditor:nil];
    NSString *host = [self.hostField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (host.length == 0) {
        self.statusLabel.stringValue = @"请填写主机。";
        return;
    }

    FormMemo *memo = nil;
    if (self.editingMemoID.length > 0) {
        memo = [[[FormMemoStore sharedStore] memoWithID:self.editingMemoID] copy];
    }
    if (!memo) {
        memo = [FormMemo memoWithHost:host title:self.titleField.stringValue];
    }
    memo.host = host.lowercaseString;
    memo.title = self.titleField.stringValue.length > 0 ? self.titleField.stringValue : host;
    NSString *path = [self.pathPrefixField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    memo.pathPrefix = path.length > 0 ? path : nil;
    memo.isDefault = (self.defaultCheck.state == NSControlStateValueOn);
    NSMutableArray<FormMemoField *> *fields = [NSMutableArray array];
    for (FormMemoField *field in self.editingFields) {
        [fields addObject:[field copy]];
    }
    memo.fields = fields;

    NSError *error = nil;
    if (![[FormMemoStore sharedStore] upsertMemo:memo error:&error]) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"保存失败";
        return;
    }
    self.isNewMemo = NO;
    self.editingMemoID = memo.memoID;
    self.deleteButton.enabled = YES;
    self.statusLabel.stringValue = @"备忘已保存。";
    if ([self.delegate respondsToSelector:@selector(memoEditor:didSaveMemo:)]) {
        [self.delegate memoEditor:self didSaveMemo:memo];
    }
}

- (void)deleteClicked:(id)sender {
    (void)sender;
    if (self.isNewMemo || self.editingMemoID.length == 0) {
        [self clear];
        if ([self.delegate respondsToSelector:@selector(memoEditorDidCancelNew:)]) {
            [self.delegate memoEditorDidCancelNew:self];
        }
        return;
    }
    NSString *memoID = self.editingMemoID;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除此站点备忘？";
    alert.informativeText = @"将删除该备忘下的全部字段文本。";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertFirstButtonReturn) {
            return;
        }
        [[FormMemoStore sharedStore] deleteMemoWithID:memoID error:nil];
        [weakSelf clear];
        if ([weakSelf.delegate respondsToSelector:@selector(memoEditor:didDeleteMemoID:)]) {
            [weakSelf.delegate memoEditor:weakSelf didDeleteMemoID:memoID];
        }
    }];
}

@end
