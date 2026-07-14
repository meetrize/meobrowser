#import "BrowserShortcutEditorSheet.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutStore.h"
#import "BrowserFaviconService.h"
#import "BrowserFaviconUtil.h"
#import "SBTextField.h"

@interface BrowserShortcutEditorPanelController : NSWindowController <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *urlField;
@property (nonatomic, strong) SBTextField *iconURLField;
@property (nonatomic, strong) NSButton *fetchIconButton;
@property (nonatomic, strong) NSImageView *iconPreview;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, copy, nullable) BrowserShortcutEditorCompletionHandler completion;
@property (nonatomic, strong, nullable) BrowserShortcutItem *editingShortcut;
@property (nonatomic, strong, nullable) BrowserShortcutEditorPanelController *selfRetain;
@property (nonatomic, copy, nullable) NSString *fetchingHost;
@property (nonatomic, assign) BOOL fetchingIcon;
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
        self.iconURLField.stringValue = shortcut.iconURLString;
        [self refreshIconPreview];
    }
    return self;
}

- (void)buildWindowWithTitle:(NSString *)title {
    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 300)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;

    NSTextField *titleCaption = [NSTextField labelWithString:@"名称"];
    NSTextField *urlCaption = [NSTextField labelWithString:@"网址"];
    NSTextField *iconCaption = [NSTextField labelWithString:@"图标链接"];

    self.titleField = [SBTextField standardField];
    self.urlField = [SBTextField standardField];
    self.urlField.placeholderString = @"https://example.com";
    self.iconURLField = [SBTextField standardField];
    self.iconURLField.placeholderString = @"https://example.com/favicon.ico（可选）";
    self.titleField.delegate = self;
    self.urlField.delegate = self;
    self.iconURLField.delegate = self;

    self.fetchIconButton = [NSButton buttonWithTitle:@"自动获取" target:self action:@selector(onFetchIcon:)];
    self.fetchIconButton.bezelStyle = NSBezelStyleRounded;
    [self.fetchIconButton setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *iconRow = [NSStackView stackViewWithViews:@[self.iconURLField, self.fetchIconButton]];
    iconRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    iconRow.alignment = NSLayoutAttributeCenterY;
    iconRow.spacing = 8;
    iconRow.distribution = NSStackViewDistributionFill;
    [self.iconURLField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.iconPreview = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.iconPreview.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.iconPreview.wantsLayer = YES;
    self.iconPreview.layer.cornerRadius = 6.0;
    self.iconPreview.layer.masksToBounds = YES;
    self.iconPreview.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;
    self.iconPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconPreview.widthAnchor constraintEqualToConstant:32],
        [self.iconPreview.heightAnchor constraintEqualToConstant:32],
    ]];

    NSStackView *iconPreviewRow = [NSStackView stackViewWithViews:@[self.iconPreview, iconRow]];
    iconPreviewRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    iconPreviewRow.alignment = NSLayoutAttributeCenterY;
    iconPreviewRow.spacing = 10;
    iconPreviewRow.distribution = NSStackViewDistributionFill;
    [iconRow setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];

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
        @[iconCaption, iconPreviewRow],
    ]];
    grid.columnSpacing = 12;
    grid.rowSpacing = 10;
    [grid columnAtIndex:0].width = 64;
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
        [controller cancelInFlightFetch];
        controller.window.delegate = nil;
        controller.selfRetain = nil;
        if (returnCode == NSModalResponseCancel && controller.completion) {
            controller.completion(nil);
        }
    }];
}

- (void)dismissSheetWithReturnCode:(NSModalResponse)returnCode {
    [self cancelInFlightFetch];
    NSWindow *sheet = self.window;
    if (sheet.sheetParent) {
        [sheet.sheetParent endSheet:sheet returnCode:returnCode];
        return;
    }
    [NSApp endSheet:sheet returnCode:returnCode];
}

- (void)cancelInFlightFetch {
    if (self.fetchingHost.length > 0) {
        [[BrowserFaviconService sharedService] cancelFetchForHost:self.fetchingHost];
        self.fetchingHost = nil;
    }
    [self setFetchingIcon:NO];
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

- (void)onFetchIcon:(id)sender {
    (void)sender;
    if (self.fetchingIcon) {
        return;
    }

    NSString *urlInput = self.urlField.stringValue;
    NSString *normalizedURL = nil;
    if (![BrowserShortcutStore validateURLString:urlInput normalizedURL:&normalizedURL]) {
        [self showError:@"请先输入有效的网址，再自动获取图标"];
        return;
    }

    self.errorLabel.hidden = YES;
    [self setFetchingIcon:YES];
    NSString *host = BrowserFaviconHostFromURLString(normalizedURL);
    self.fetchingHost = host;

    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] fetchAndCacheForPageURLString:normalizedURL
                                                         preferredIconURL:nil
                                                                   reason:BrowserFaviconFetchReasonUserAction
                                                               completion:^(NSURL *iconURL, NSImage *image, NSError *error) {
        BrowserShortcutEditorPanelController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.fetchingHost = nil;
        [strongSelf setFetchingIcon:NO];

        if (error != nil && error.code == BrowserFaviconErrorCancelled) {
            return;
        }
        if (image == nil || iconURL.absoluteString.length == 0) {
            [strongSelf showError:@"未能获取图标，可手动填写"];
            return;
        }

        strongSelf.iconURLField.stringValue = iconURL.absoluteString;
        strongSelf.iconPreview.image = image;
        strongSelf.iconPreview.layer.backgroundColor = NSColor.clearColor.CGColor;
        strongSelf.errorLabel.hidden = YES;
    }];
}

- (void)setFetchingIcon:(BOOL)fetchingIcon {
    _fetchingIcon = fetchingIcon;
    self.fetchIconButton.enabled = !fetchingIcon;
    self.fetchIconButton.title = fetchingIcon ? @"获取中…" : @"自动获取";
}

- (void)refreshIconPreview {
    NSString *iconURL = self.iconURLField.stringValue;
    NSString *pageURL = self.urlField.stringValue;
    self.iconPreview.image = nil;
    self.iconPreview.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;

    NSString *host = BrowserFaviconHostFromURLString(pageURL);
    if (host.length > 0) {
        NSImage *cached = [[BrowserFaviconService sharedService] cachedImageForHost:host];
        if (cached != nil) {
            self.iconPreview.image = cached;
            self.iconPreview.layer.backgroundColor = NSColor.clearColor.CGColor;
            return;
        }
    }
    if (iconURL.length == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] imageForPageURLString:(pageURL.length > 0 ? pageURL : iconURL)
                                                 preferredIconURL:iconURL
                                                      triggerFetch:NO
                                                        completion:^(NSImage *image) {
        BrowserShortcutEditorPanelController *strongSelf = weakSelf;
        if (strongSelf == nil || image == nil) {
            return;
        }
        if (![strongSelf.iconURLField.stringValue isEqualToString:iconURL]) {
            return;
        }
        strongSelf.iconPreview.image = image;
        strongSelf.iconPreview.layer.backgroundColor = NSColor.clearColor.CGColor;
    }];
}

- (void)onSave:(id)sender {
    (void)sender;
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *urlInput = self.urlField.stringValue;
    NSString *iconInput = self.iconURLField.stringValue;

    if (title.length == 0) {
        [self showError:@"请输入名称"];
        return;
    }

    NSString *normalizedURL = nil;
    if (![BrowserShortcutStore validateURLString:urlInput normalizedURL:&normalizedURL]) {
        [self showError:@"请输入有效的网址，需包含 http/https 与域名"];
        return;
    }

    NSString *normalizedIconURL = nil;
    if (![BrowserShortcutStore validateIconURLString:iconInput normalizedURL:&normalizedIconURL]) {
        [self showError:@"请输入有效的图标链接，需包含 http/https 与域名"];
        return;
    }

    BrowserShortcutItem *result = nil;
    if (self.editingShortcut) {
        result = self.editingShortcut;
        result.title = title;
        result.urlString = normalizedURL;
        result.iconURLString = normalizedIconURL ?: @"";
    } else {
        result = [BrowserShortcutItem itemWithTitle:title
                                          urlString:normalizedURL
                                       iconURLString:normalizedIconURL ?: @""
                                          sortOrder:0];
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

- (void)controlTextDidChange:(NSNotification *)obj {
    (void)obj;
    if (obj.object == self.iconURLField || obj.object == self.urlField) {
        // 输入变化时不自动请求网络，仅在有 host 缓存时刷新预览。
        NSString *host = BrowserFaviconHostFromURLString(self.urlField.stringValue);
        if (host.length > 0) {
            NSImage *cached = [[BrowserFaviconService sharedService] cachedImageForHost:host];
            if (cached != nil) {
                self.iconPreview.image = cached;
                self.iconPreview.layer.backgroundColor = NSColor.clearColor.CGColor;
                return;
            }
        }
        if (self.iconURLField.stringValue.length == 0) {
            self.iconPreview.image = nil;
            self.iconPreview.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;
        }
    }
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
