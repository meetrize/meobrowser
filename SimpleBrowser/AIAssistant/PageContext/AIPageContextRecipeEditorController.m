#import "AIPageContextRecipeEditorController.h"
#import "AIPageContextRecipe.h"
#import "AIPageContextRecipeStore.h"
#import "SBTextField.h"
#import "SBTextView.h"

@interface AIPageContextRecipeEditorController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<AIPageContextRecipe *> *recipes;
@property (nonatomic, copy, nullable) NSString *selectedId;
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *sortOrderField;
@property (nonatomic, strong) SBTextView *promptView;
@property (nonatomic, strong) SBTextView *hintView;
@property (nonatomic, strong) NSButton *sidebarCheck;
@property (nonatomic, strong) NSButton *contextCheck;
@property (nonatomic, strong) NSButton *topLevelCheck;
@property (nonatomic, strong) NSButton *autoSendCheck;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, assign) BOOL loadingForm;
@end

@implementation AIPageContextRecipeEditorController

+ (instancetype)sharedController {
    static AIPageContextRecipeEditorController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[AIPageContextRecipeEditorController alloc] init];
    });
    return c;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 520)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"管理 AI 配方";
    win.minSize = NSMakeSize(680, 420);
    self = [super initWithWindow:win];
    if (self) {
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeChanged:)
                                                     name:AIPageContextRecipeStoreDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)showEditor {
    [self reloadListKeepingSelection:YES];
    [self.window center];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)storeChanged:(NSNotification *)n {
    (void)n;
    if (self.window.isVisible) {
        [self reloadListKeepingSelection:YES];
    }
}

- (NSTextField *)makeCaption:(NSString *)text {
    NSTextField *t = [NSTextField labelWithString:text];
    t.font = [NSFont systemFontOfSize:11];
    t.textColor = NSColor.secondaryLabelColor;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    return t;
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    NSScrollView *listScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    listScroll.translatesAutoresizingMaskIntoConstraints = NO;
    listScroll.hasVerticalScroller = YES;
    listScroll.borderType = NSBezelBorder;
    listScroll.drawsBackground = YES;

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    col.title = @"配方";
    col.width = 200;
    [self.tableView addTableColumn:col];
    self.tableView.headerView = nil;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.allowsEmptySelection = NO;
    self.tableView.target = self;
    self.tableView.action = @selector(tableClicked:);
    listScroll.documentView = self.tableView;

    NSView *form = [[NSView alloc] initWithFrame:NSZeroRect];
    form.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleCap = [self makeCaption:@"标题"];
    self.titleField = [SBTextField standardField];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *sortCap = [self makeCaption:@"排序（越小越靠前）"];
    self.sortOrderField = [SBTextField standardField];
    self.sortOrderField.translatesAutoresizingMaskIntoConstraints = NO;

    self.sidebarCheck = [NSButton checkboxWithTitle:@"侧栏快捷" target:nil action:nil];
    self.sidebarCheck.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextCheck = [NSButton checkboxWithTitle:@"右键「问问 AI」" target:nil action:nil];
    self.contextCheck.translatesAutoresizingMaskIntoConstraints = NO;
    self.topLevelCheck = [NSButton checkboxWithTitle:@"右键顶层第一项" target:nil action:nil];
    self.topLevelCheck.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoSendCheck = [NSButton checkboxWithTitle:@"运行后自动发送" target:nil action:nil];
    self.autoSendCheck.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *checks = [NSStackView stackViewWithViews:@[
        self.sidebarCheck, self.contextCheck, self.topLevelCheck, self.autoSendCheck
    ]];
    checks.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    checks.spacing = 12;
    checks.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *promptCap = [self makeCaption:@"用户提示词（userPrompt）"];
    NSScrollView *promptScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    promptScroll.translatesAutoresizingMaskIntoConstraints = NO;
    promptScroll.hasVerticalScroller = YES;
    promptScroll.borderType = NSBezelBorder;
    self.promptView = [SBTextView standardTextView];
    self.promptView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    promptScroll.documentView = self.promptView;

    NSTextField *hintCap = [self makeCaption:@"系统提示（systemHint）"];
    NSScrollView *hintScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    hintScroll.translatesAutoresizingMaskIntoConstraints = NO;
    hintScroll.hasVerticalScroller = YES;
    hintScroll.borderType = NSBezelBorder;
    self.hintView = [SBTextView standardTextView];
    self.hintView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    hintScroll.documentView = self.hintView;

    for (NSView *v in @[titleCap, self.titleField, sortCap, self.sortOrderField, checks,
                        promptCap, promptScroll, hintCap, hintScroll]) {
        [form addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [titleCap.topAnchor constraintEqualToAnchor:form.topAnchor],
        [titleCap.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [self.titleField.topAnchor constraintEqualToAnchor:titleCap.bottomAnchor constant:4],
        [self.titleField.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [self.titleField.trailingAnchor constraintEqualToAnchor:form.trailingAnchor],

        [sortCap.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:8],
        [sortCap.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [self.sortOrderField.topAnchor constraintEqualToAnchor:sortCap.bottomAnchor constant:4],
        [self.sortOrderField.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [self.sortOrderField.widthAnchor constraintEqualToConstant:100],

        [checks.topAnchor constraintEqualToAnchor:self.sortOrderField.bottomAnchor constant:10],
        [checks.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],

        [promptCap.topAnchor constraintEqualToAnchor:checks.bottomAnchor constant:10],
        [promptCap.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [promptScroll.topAnchor constraintEqualToAnchor:promptCap.bottomAnchor constant:4],
        [promptScroll.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [promptScroll.trailingAnchor constraintEqualToAnchor:form.trailingAnchor],
        [promptScroll.heightAnchor constraintEqualToConstant:160],

        [hintCap.topAnchor constraintEqualToAnchor:promptScroll.bottomAnchor constant:8],
        [hintCap.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [hintScroll.topAnchor constraintEqualToAnchor:hintCap.bottomAnchor constant:4],
        [hintScroll.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
        [hintScroll.trailingAnchor constraintEqualToAnchor:form.trailingAnchor],
        [hintScroll.bottomAnchor constraintEqualToAnchor:form.bottomAnchor],
        [hintScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],
    ]];

    NSButton *newBtn = [NSButton buttonWithTitle:@"新建" target:self action:@selector(newClicked:)];
    NSButton *dupBtn = [NSButton buttonWithTitle:@"另存副本" target:self action:@selector(dupClicked:)];
    NSButton *saveBtn = [NSButton buttonWithTitle:@"保存" target:self action:@selector(saveClicked:)];
    saveBtn.keyEquivalent = @"\r";
    NSButton *resetBtn = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetClicked:)];
    NSButton *delBtn = [NSButton buttonWithTitle:@"删除" target:self action:@selector(deleteClicked:)];
    NSButton *importBtn = [NSButton buttonWithTitle:@"导入…" target:self action:@selector(importClicked:)];
    NSButton *exportBtn = [NSButton buttonWithTitle:@"导出…" target:self action:@selector(exportClicked:)];
    NSButton *doneBtn = [NSButton buttonWithTitle:@"完成" target:self action:@selector(doneClicked:)];
    for (NSButton *b in @[newBtn, dupBtn, saveBtn, resetBtn, delBtn, importBtn, exportBtn, doneBtn]) {
        b.bezelStyle = NSBezelStyleRounded;
        b.translatesAutoresizingMaskIntoConstraints = NO;
    }
    NSStackView *toolbar = [NSStackView stackViewWithViews:@[
        newBtn, dupBtn, saveBtn, resetBtn, delBtn, importBtn, exportBtn, doneBtn
    ]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    [content addSubview:listScroll];
    [content addSubview:form];
    [content addSubview:toolbar];
    [content addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [listScroll.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [listScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [listScroll.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-10],
        [listScroll.widthAnchor constraintEqualToConstant:220],

        [form.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [form.leadingAnchor constraintEqualToAnchor:listScroll.trailingAnchor constant:12],
        [form.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [form.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-10],

        [toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [toolbar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],

        [self.statusLabel.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-12],
    ]];
}

- (void)reloadListKeepingSelection:(BOOL)keep {
    NSString *sel = keep ? self.selectedId : nil;
    self.recipes = [[AIPageContextRecipeStore sharedStore] allRecipesSorted];
    [self.tableView reloadData];
    NSInteger idx = 0;
    if (sel.length) {
        for (NSInteger i = 0; i < (NSInteger)self.recipes.count; i++) {
            if ([self.recipes[i].recipeId isEqualToString:sel]) {
                idx = i;
                break;
            }
        }
    }
    if (self.recipes.count) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
        self.selectedId = self.recipes[idx].recipeId;
        [self loadFormFromRecipe:self.recipes[idx]];
    }
}

- (NSString *)badgeForRecipe:(AIPageContextRecipe *)r {
    BOOL overridden = [[AIPageContextRecipeStore sharedStore] hasUserOverrideForId:r.recipeId];
    BOOL bundled = [AIPageContextRecipe isBundledRecipeId:r.recipeId];
    if (bundled && overridden) return [NSString stringWithFormat:@"%@ · 已覆盖", r.title];
    if (bundled) return [NSString stringWithFormat:@"%@ · 内置", r.title];
    return [NSString stringWithFormat:@"%@ · 用户", r.title];
}

- (void)loadFormFromRecipe:(AIPageContextRecipe *)r {
    self.loadingForm = YES;
    self.titleField.stringValue = r.title ?: @"";
    self.sortOrderField.stringValue = [NSString stringWithFormat:@"%ld", (long)r.sortOrder];
    self.promptView.string = r.userPrompt ?: @"";
    self.hintView.string = r.systemHint ?: @"";
    self.sidebarCheck.state = r.showInSidebar ? NSControlStateValueOn : NSControlStateValueOff;
    self.contextCheck.state = r.showInContextMenu ? NSControlStateValueOn : NSControlStateValueOff;
    self.topLevelCheck.state = r.contextMenuTopLevel ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoSendCheck.state = r.autoSend ? NSControlStateValueOn : NSControlStateValueOff;
    self.loadingForm = NO;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"id: %@", r.recipeId ?: @""];
}

- (AIPageContextRecipe *)recipeFromForm {
    if (!self.selectedId.length) return nil;
    AIPageContextRecipe *base = [[AIPageContextRecipeStore sharedStore] recipeWithId:self.selectedId];
    if (!base) return nil;
    AIPageContextRecipe *r = [base copyRecipe];
    r.recipeId = self.selectedId;
    r.title = self.titleField.stringValue ?: @"";
    r.userPrompt = self.promptView.string ?: @"";
    r.systemHint = self.hintView.string ?: @"";
    r.sortOrder = [self.sortOrderField.stringValue integerValue];
    r.showInSidebar = self.sidebarCheck.state == NSControlStateValueOn;
    r.showInContextMenu = self.contextCheck.state == NSControlStateValueOn;
    r.contextMenuTopLevel = self.topLevelCheck.state == NSControlStateValueOn;
    r.autoSend = self.autoSendCheck.state == NSControlStateValueOn;
    r.userDefined = YES;
    return r;
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.recipes.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)self.recipes.count) return @"";
    return [self badgeForRecipe:self.recipes[row]];
}

- (void)tableClicked:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.recipes.count) return;
    self.selectedId = self.recipes[row].recipeId;
    [self loadFormFromRecipe:self.recipes[row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self tableClicked:nil];
}

#pragma mark - Actions

- (void)newClicked:(id)sender {
    (void)sender;
    AIPageContextRecipe *r = [[AIPageContextRecipeStore sharedStore] createBlankRecipe];
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] saveUserRecipe:r error:&err]) {
        self.selectedId = r.recipeId;
        [self reloadListKeepingSelection:YES];
        self.statusLabel.stringValue = @"已新建配方";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"新建失败";
    }
}

- (void)dupClicked:(id)sender {
    (void)sender;
    AIPageContextRecipe *src = [[AIPageContextRecipeStore sharedStore] recipeWithId:self.selectedId];
    if (!src) return;
    AIPageContextRecipe *dup = [[AIPageContextRecipeStore sharedStore] duplicateRecipe:src
                                                                             withTitle:[NSString stringWithFormat:@"%@ 副本", src.title ?: @"配方"]];
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] saveUserRecipe:dup error:&err]) {
        self.selectedId = dup.recipeId;
        [self reloadListKeepingSelection:YES];
        self.statusLabel.stringValue = @"已另存副本";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"另存失败";
    }
}

- (void)saveClicked:(id)sender {
    (void)sender;
    AIPageContextRecipe *r = [self recipeFromForm];
    if (!r) return;
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] saveUserRecipe:r error:&err]) {
        self.selectedId = r.recipeId;
        [self reloadListKeepingSelection:YES];
        self.statusLabel.stringValue = r.contextMenuTopLevel
            ? @"已保存（已设为右键顶层；其他顶层已取消）"
            : @"已保存";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"保存失败";
    }
}

- (void)resetClicked:(id)sender {
    (void)sender;
    if (!self.selectedId.length) return;
    if (![AIPageContextRecipe isBundledRecipeId:self.selectedId]) {
        self.statusLabel.stringValue = @"用户配方请用删除；恢复默认仅适用于内置覆盖";
        return;
    }
    if (![[AIPageContextRecipeStore sharedStore] hasUserOverrideForId:self.selectedId]) {
        self.statusLabel.stringValue = @"当前已是内置默认";
        return;
    }
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] resetRecipeId:self.selectedId error:&err]) {
        [self reloadListKeepingSelection:YES];
        self.statusLabel.stringValue = @"已恢复内置默认";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"恢复失败";
    }
}

- (void)deleteClicked:(id)sender {
    (void)sender;
    if (!self.selectedId.length) return;
    BOOL bundled = [AIPageContextRecipe isBundledRecipeId:self.selectedId];
    BOOL overridden = [[AIPageContextRecipeStore sharedStore] hasUserOverrideForId:self.selectedId];
    if (bundled && !overridden) {
        self.statusLabel.stringValue = @"内置配方不能删除，可取消侧栏/右键显示";
        return;
    }
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] deleteUserRecipeId:self.selectedId error:&err]) {
        self.selectedId = nil;
        [self reloadListKeepingSelection:NO];
        self.statusLabel.stringValue = bundled ? @"已清除覆盖，恢复内置" : @"已删除用户配方";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"删除失败";
    }
}

- (void)importClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"json" ];
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSError *err = nil;
    AIPageContextRecipe *r = [[AIPageContextRecipeStore sharedStore] importRecipeFromURL:panel.URL error:&err];
    if (r) {
        self.selectedId = r.recipeId;
        [self reloadListKeepingSelection:YES];
        self.statusLabel.stringValue = @"已导入";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"导入失败";
    }
}

- (void)exportClicked:(id)sender {
    (void)sender;
    AIPageContextRecipe *r = [[AIPageContextRecipeStore sharedStore] recipeWithId:self.selectedId];
    if (!r) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"json" ];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.json", r.recipeId ?: @"recipe"];
    if ([panel runModal] != NSModalResponseOK) return;
    NSError *err = nil;
    if ([[AIPageContextRecipeStore sharedStore] exportRecipe:r toURL:panel.URL error:&err]) {
        self.statusLabel.stringValue = @"已导出";
    } else {
        self.statusLabel.stringValue = err.localizedDescription ?: @"导出失败";
    }
}

- (void)doneClicked:(id)sender {
    (void)sender;
    [self.window close];
}

@end
