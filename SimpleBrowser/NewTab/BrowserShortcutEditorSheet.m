#import "BrowserShortcutEditorSheet.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutStore.h"
#import "SBTextField.h"

@interface BrowserShortcutEditorPanelController : NSWindowController <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *urlField;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, copy, nullable) BrowserShortcutEditorCompletionHandler completion;
@property (nonatomic, strong, nullable) BrowserShortcutItem *editingShortcut;
/// 保持 controller 存活直至 sheet 结束（按钮 target 与 delegate 需要有效 self）
@property (nonatomic, strong, nullable) BrowserShortcutEditorPanelController *selfRetain;
@end

@implementation BrowserShortcutEditorPanelController

- (instancetype)initForAdding {
    self = [super initWithWindow:nil];
    if (self) {
        [self buildWindowWithTitle:@"添加快捷方式"];
    }
    return self;
}

- (instancetype)initForEditingShortcut:(BrowserShortcutItem *)shortcut {
    self = [super initWithWindow:nil];
    if (self) {
        _editingShortcut = shortcut;
        [self buildWindowWithTitle:@"编辑快捷方式"];
        self.titleField.stringValue = shortcut.title;
        self.urlField.stringValue = shortcut.urlString;
    }
    return self;
}

- (void)buildWindowWithTitle:(NSString *)title {
    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 220)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;

    NSTextField *titleCaption = [NSTextField labelWithString:@"名称"];
    NSTextField *urlCaption = [NSTextField labelWithString:@"网址"];

    self.titleField = [SBTextField standardField];
    self.urlField = [SBTextField standardField];
    self.urlField.placeholderString = @"https://example.com";
    self.titleField.delegate = self;
    self.urlField.delegate = self;

    self.errorLabel = [NSTextField labelWithString:@""];
    self.errorLabel.textColor = [NSColor systemRedColor];
    self.errorLabel.font = [NSFont systemFontOfSize:12];
    self.errorLabel.hidden = YES;

    NSButton *cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(onCancel:)];
    NSButton *saveButton = [NSButton buttonWithTitle:@"保存" target:self action:@selector(onSave:)];
    saveButton.keyEquivalent = @"\r";
    cancelButton.keyEquivalent = @"\033";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[titleCaption, self.titleField],
        @[urlCaption, self.urlField],
    ]];
    grid.columnSpacing = 12;
    grid.rowSpacing = 10;
    [grid columnAtIndex:0].width = 48;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSStackView *buttons = [NSStackView stackViewWithViews:@[cancelButton, saveButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8;

    NSStackView *root = [NSStackView stackViewWithViews:@[grid, self.errorLabel, buttons]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *contentView = panel.contentView;
    [contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    self.window = panel;
}

- (void)presentOnWindow:(NSWindow *)parentWindow {
    self.selfRetain = self;
    self.window.delegate = self;

    __weak typeof(self) weakSelf = self;
    [parentWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        BrowserShortcutEditorPanelController *controller = weakSelf;
        controller.window.delegate = nil;
        controller.selfRetain = nil;
        if (returnCode == NSModalResponseCancel && controller.completion) {
            controller.completion(nil);
        }
    }];
}

- (void)dismissSheetWithReturnCode:(NSModalResponse)returnCode {
    NSWindow *sheet = self.window;
    if (sheet.sheetParent) {
        [sheet.sheetParent endSheet:sheet returnCode:returnCode];
        return;
    }
    [NSApp endSheet:sheet returnCode:returnCode];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    [self dismissSheetWithReturnCode:NSModalResponseCancel];
    return NO;
}

#pragma mark - Actions

- (void)onCancel:(id)sender {
    (void)sender;
    [self dismissSheetWithReturnCode:NSModalResponseCancel];
}

- (void)onSave:(id)sender {
    (void)sender;
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *urlInput = self.urlField.stringValue;

    if (title.length == 0) {
        [self showError:@"请输入名称"];
        return;
    }

    NSString *normalizedURL = nil;
    if (![BrowserShortcutStore validateURLString:urlInput normalizedURL:&normalizedURL]) {
        [self showError:@"请输入有效的网址，需包含 http/https 与域名"];
        return;
    }

    BrowserShortcutItem *result = nil;
    if (self.editingShortcut) {
        result = self.editingShortcut;
        result.title = title;
        result.urlString = normalizedURL;
    } else {
        result = [BrowserShortcutItem itemWithTitle:title urlString:normalizedURL sortOrder:0];
    }

    if (self.completion) {
        self.completion(result);
    }
    [self dismissSheetWithReturnCode:NSModalResponseOK];
}

- (void)showError:(NSString *)message {
    self.errorLabel.stringValue = message;
    self.errorLabel.hidden = NO;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;
    if (commandSelector == @selector(insertNewline:)) {
        [self onSave:control];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self onCancel:control];
        return YES;
    }
    return NO;
}

@end

@implementation BrowserShortcutEditorSheet

+ (void)presentAddingShortcutOnWindow:(NSWindow *)parentWindow
                           completion:(BrowserShortcutEditorCompletionHandler)completion {
    BrowserShortcutEditorPanelController *controller = [[BrowserShortcutEditorPanelController alloc] initForAdding];
    controller.completion = completion;
    [controller presentOnWindow:parentWindow];
}

+ (void)presentEditingShortcut:(BrowserShortcutItem *)shortcut
                      onWindow:(NSWindow *)parentWindow
                    completion:(BrowserShortcutEditorCompletionHandler)completion {
    BrowserShortcutEditorPanelController *controller = [[BrowserShortcutEditorPanelController alloc] initForEditingShortcut:shortcut];
    controller.completion = completion;
    [controller presentOnWindow:parentWindow];
}

@end
