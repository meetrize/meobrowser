#import "PhonePolicyPanelController.h"
#import "PhonePolicyStore.h"
#import "SBTextField.h"

@interface PhonePolicyPanelController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<PhonePolicyEntry *> *rows;
@property (nonatomic, strong) SBTextField *numberField;
@property (nonatomic, strong) SBTextField *nameField;
@end

@implementation PhonePolicyPanelController

+ (instancetype)sharedController {
    static PhonePolicyPanelController *ctrl;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ctrl = [[self alloc] init];
    });
    return ctrl;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 360)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"号码策略";
    window.minSize = NSMakeSize(400, 280);
    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
        [self reload];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    self.numberField = [SBTextField standardField];
    self.numberField.placeholderString = @"号码";
    self.numberField.translatesAutoresizingMaskIntoConstraints = NO;

    self.nameField = [SBTextField standardField];
    self.nameField.placeholderString = @"备注名";
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *addButton = [NSButton buttonWithTitle:@"添加/更新"
                                             target:self
                                             action:@selector(addOrUpdate:)];
    addButton.bezelStyle = NSBezelStyleRounded;

    NSButton *deleteButton = [NSButton buttonWithTitle:@"删除选中"
                                                target:self
                                                action:@selector(deleteSelected:)];
    deleteButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *form = [NSStackView stackViewWithViews:@[
        self.numberField, self.nameField, addButton, deleteButton
    ]];
    form.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    form.spacing = 8;
    form.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *c1 = [[NSTableColumn alloc] initWithIdentifier:@"number"];
    c1.title = @"号码";
    c1.width = 160;
    NSTableColumn *c2 = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    c2.title = @"备注";
    c2.width = 140;
    NSTableColumn *c3 = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    c3.title = @"类型";
    c3.width = 100;
    [self.tableView addTableColumn:c1];
    [self.tableView addTableColumn:c2];
    [self.tableView addTableColumn:c3];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.allowsEmptySelection = YES;
    scroll.documentView = self.tableView;

    NSTextField *hint = [NSTextField wrappingLabelWithString:@"本地备注优先于规则类型。本期不同步手机、无黑名单。"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:form];
    [content addSubview:scroll];
    [content addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [form.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [form.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [form.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [self.numberField.widthAnchor constraintEqualToConstant:140],
        [self.nameField.widthAnchor constraintEqualToConstant:120],
        [scroll.topAnchor constraintEqualToAnchor:form.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:hint.topAnchor constant:-8],
        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [hint.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10],
    ]];
}

- (void)showPanel {
    [self reload];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)reload {
    [[PhonePolicyStore sharedStore] reload];
    self.rows = [[PhonePolicyStore sharedStore] allEntries];
    [self.tableView reloadData];
}

- (void)addOrUpdate:(id)sender {
    (void)sender;
    NSString *number = self.numberField.stringValue ?: @"";
    NSString *name = self.nameField.stringValue ?: @"";
    if (number.length == 0) {
        return;
    }
    [[PhonePolicyStore sharedStore] upsertDisplayName:name
                                             category:@"personal"
                                            forNumber:number];
    self.numberField.stringValue = @"";
    self.nameField.stringValue = @"";
    [self reload];
}

- (void)deleteSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    PhonePolicyEntry *e = self.rows[row];
    [[PhonePolicyStore sharedStore] removeEntryID:e.entryID];
    [self reload];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.rows.count;
}

- (nullable id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                     row:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) return nil;
    PhonePolicyEntry *e = self.rows[row];
    if ([tableColumn.identifier isEqualToString:@"number"]) return e.numberE164;
    if ([tableColumn.identifier isEqualToString:@"name"]) return e.displayName;
    if ([tableColumn.identifier isEqualToString:@"category"]) return e.category;
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    PhonePolicyEntry *e = self.rows[row];
    self.numberField.stringValue = e.numberE164 ?: @"";
    self.nameField.stringValue = e.displayName ?: @"";
}

@end
