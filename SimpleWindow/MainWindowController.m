#import "MainWindowController.h"

@interface MainWindowController ()
@property (nonatomic, copy) NSArray<NSString *> *sidebarItems;
@property (nonatomic, copy) NSArray<NSString *> *filteredItems;
@end

@implementation MainWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"MainWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    self.sidebarItems = @[@"表单控件", @"展示组件", @"交互按钮", @"关于"];
    self.filteredItems = self.sidebarItems;

    [self.sidebarTableView setDataSource:self];
    [self.sidebarTableView setDelegate:self];
    [self.sidebarTableView reloadData];
    [self.sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    [self.themePopUp removeAllItems];
    [self.themePopUp addItemsWithTitles:@[@"系统默认", @"浅色", @"深色"]];
    [self.themePopUp selectItemAtIndex:0];

    [self.volumeSlider setDoubleValue:50];
    [self.levelIndicator setDoubleValue:7];
    [self.progressBar setIndeterminate:NO];
    [self.progressBar setDoubleValue:0.65];
    [self.progressSpinner startAnimation:nil];

    [self.previewImageView setImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
    [self.outputTextView setString:@"这是 NSTextView 演示区域。\n\n可在「表单控件」页填写内容，点击「执行操作」查看联动效果。"];

    [self.segmentControl setLabel:@"列表" forSegment:0];
    [self.segmentControl setLabel:@"网格" forSegment:1];
    [self.segmentControl setLabel:@"详情" forSegment:2];
    [self.segmentControl setSelectedSegment:0];

    [self.searchField setPlaceholderString:@"搜索侧边栏..."];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSearchTextChanged:)
                                                 name:NSControlTextDidChangeNotification
                                               object:self.searchField];
    [self updateStatus:@"XIB 演示已加载 — 所有控件来自 Interface Builder"];
}

- (void)onSearchTextChanged:(NSNotification *)notification {
    (void)notification;
    NSString *query = self.searchField.stringValue;
    if (query.length == 0) {
        self.filteredItems = self.sidebarItems;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *item, NSDictionary *bindings) {
            (void)bindings;
            return [item localizedCaseInsensitiveContainsString:query];
        }];
        self.filteredItems = [self.sidebarItems filteredArrayUsingPredicate:predicate];
    }
    [self.sidebarTableView reloadData];
}

#pragma mark - Sidebar

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.filteredItems.count;
}

- (nullable id)tableView:(NSTableView *)tableView
   objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                         row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    return self.filteredItems[(NSUInteger)row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = self.sidebarTableView.selectedRow;
    if (row >= 0 && row < (NSInteger)self.filteredItems.count) {
        [self.mainTabView selectTabViewItemAtIndex:(NSInteger)row];
        [self updateStatus:[NSString stringWithFormat:@"已切换到：%@", self.filteredItems[(NSUInteger)row]]];
    }
}

#pragma mark - Actions

- (IBAction)onActionButton:(id)sender {
    (void)sender;
    NSString *name = self.nameField.stringValue.length ? self.nameField.stringValue : @"(未填写)";
    NSString *theme = self.themePopUp.titleOfSelectedItem ?: @"系统默认";
    BOOL notify = (self.notifyCheckbox.state == NSControlStateValueOn);
    NSInteger volume = (NSInteger)self.volumeSlider.doubleValue;

    NSString *message = [NSString stringWithFormat:
                         @"姓名：%@\n主题：%@\n通知：%@\n音量：%ld",
                         name, theme, notify ? @"开启" : @"关闭", (long)volume];
    [self.outputTextView setString:message];
    [self.progressBar setDoubleValue:(double)volume / 100.0];
    [self.levelIndicator setDoubleValue:(double)volume / 10.0];
    [self updateStatus:@"操作完成 — 输出已更新"];
}

- (IBAction)onShowAlert:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"NSAlert 演示";
    alert.informativeText = @"这是 AppKit 原生对话框，由代码弹出（非 XIB）。";
    [alert addButtonWithTitle:@"确定"];
    [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        NSString *result = (returnCode == NSAlertFirstButtonReturn) ? @"用户点击了确定" : @"用户点击了取消";
        [self updateStatus:result];
    }];
}

- (IBAction)onSliderChanged:(id)sender {
    NSSlider *slider = (NSSlider *)sender;
    [self.progressBar setDoubleValue:slider.doubleValue / 100.0];
    [self.levelIndicator setDoubleValue:slider.doubleValue / 10.0];
    [self updateStatus:[NSString stringWithFormat:@"滑块值：%.0f", slider.doubleValue]];
}

- (IBAction)onCheckboxChanged:(id)sender {
    NSButton *checkbox = (NSButton *)sender;
    BOOL on = (checkbox.state == NSControlStateValueOn);
    [self updateStatus:on ? @"通知已开启" : @"通知已关闭"];
}

- (IBAction)onSegmentChanged:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    [self updateStatus:[NSString stringWithFormat:@"分段控件选中：%ld", (long)control.selectedSegment]];
}

- (IBAction)onStepperChanged:(id)sender {
    NSStepper *stepper = (NSStepper *)sender;
    [self.volumeSlider setDoubleValue:stepper.doubleValue];
    [self onSliderChanged:self.volumeSlider];
}

#pragma mark - Helpers

- (void)updateStatus:(NSString *)text {
    self.statusLabel.stringValue = text;
}

@end
