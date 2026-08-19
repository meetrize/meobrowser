#import "BrowserShortcutEditorSheet.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutIconPalette.h"
#import "BrowserFaviconService.h"
#import "BrowserFaviconUtil.h"
#import "SBTextField.h"

@interface BrowserShortcutEditorPanelController : NSWindowController <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) SBTextField *urlField;
@property (nonatomic, strong) SBTextField *iconURLField;
@property (nonatomic, strong) SBTextField *letterField;
@property (nonatomic, strong) NSButton *fetchIconButton;
@property (nonatomic, strong) NSButton *autoStyleButton;
@property (nonatomic, strong) NSButton *letterStyleButton;
@property (nonatomic, strong) NSView *autoIconRow;
@property (nonatomic, strong) NSView *letterOptionsView;
@property (nonatomic, strong) NSStackView *colorGrid;
@property (nonatomic, strong) NSMutableArray<NSButton *> *colorButtons;
@property (nonatomic, strong) NSView *iconPreviewPlate;
@property (nonatomic, strong) NSImageView *iconPreviewImage;
@property (nonatomic, strong) NSTextField *iconPreviewLetter;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, copy, nullable) BrowserShortcutEditorCompletionHandler completion;
@property (nonatomic, strong, nullable) BrowserShortcutItem *editingShortcut;
@property (nonatomic, strong, nullable) BrowserShortcutEditorPanelController *selfRetain;
@property (nonatomic, copy, nullable) NSString *fetchingHost;
@property (nonatomic, assign) BOOL fetchingIcon;
@property (nonatomic, assign) BOOL usingLetterStyle;
@property (nonatomic, assign) NSInteger selectedColorIndex;
@end

@implementation BrowserShortcutEditorPanelController

- (instancetype)initForAdding {
    self = [super initWithWindow:nil];
    if (self) {
        _usingLetterStyle = NO;
        _selectedColorIndex = 0;
        [self buildWindowWithTitle:@"添加快捷方式"];
        [self applyStyleModeUI];
        [self refreshIconPreview];
    }
    return self;
}

- (instancetype)initForEditingShortcut:(BrowserShortcutItem *)shortcut {
    self = [super initWithWindow:nil];
    if (self) {
        _editingShortcut = shortcut;
        _usingLetterStyle = shortcut.usesCustomLetterIcon;
        _selectedColorIndex = [BrowserShortcutIconPalette clampedIndex:shortcut.iconColorIndex];
        [self buildWindowWithTitle:@"编辑快捷方式"];
        self.titleField.stringValue = shortcut.title;
        self.urlField.stringValue = shortcut.urlString;
        self.iconURLField.stringValue = shortcut.iconURLString;
        NSString *letter = shortcut.iconLetter.length > 0
            ? shortcut.iconLetter
            : [BrowserShortcutIconPalette defaultLetterForTitle:shortcut.title urlString:shortcut.urlString];
        self.letterField.stringValue = letter;
        [self applyStyleModeUI];
        [self refreshIconPreview];
    }
    return self;
}

- (void)buildWindowWithTitle:(NSString *)title {
    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 360)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;

    NSTextField *titleCaption = [NSTextField labelWithString:@"名称"];
    NSTextField *urlCaption = [NSTextField labelWithString:@"网址"];
    NSTextField *iconCaption = [NSTextField labelWithString:@"图标"];

    self.titleField = [SBTextField standardField];
    self.urlField = [SBTextField standardField];
    self.urlField.placeholderString = @"https://example.com";
    self.iconURLField = [SBTextField standardField];
    self.iconURLField.placeholderString = @"https://example.com/favicon.ico（可选）";
    self.letterField = [SBTextField standardField];
    self.letterField.placeholderString = @"字母";
    self.titleField.delegate = self;
    self.urlField.delegate = self;
    self.iconURLField.delegate = self;
    self.letterField.delegate = self;

    static const CGFloat kFieldHeight = 22.0;
    for (NSTextField *field in @[self.titleField, self.urlField, self.iconURLField, self.letterField]) {
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [field.heightAnchor constraintEqualToConstant:kFieldHeight].active = YES;
        [field setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationVertical];
    }
    [self.letterField.widthAnchor constraintEqualToConstant:48].active = YES;

    self.fetchIconButton = [NSButton buttonWithTitle:@"自动获取" target:self action:@selector(onFetchIcon:)];
    self.fetchIconButton.bezelStyle = NSBezelStyleRounded;
    [self.fetchIconButton setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.autoStyleButton = [NSButton radioButtonWithTitle:@"自动（Favicon）"
                                                   target:self
                                                   action:@selector(onStyleChanged:)];
    self.letterStyleButton = [NSButton radioButtonWithTitle:@"自定义色块"
                                                     target:self
                                                     action:@selector(onStyleChanged:)];

    NSStackView *styleRow = [NSStackView stackViewWithViews:@[self.autoStyleButton, self.letterStyleButton]];
    styleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    styleRow.alignment = NSLayoutAttributeCenterY;
    styleRow.spacing = 16;

    self.iconPreviewPlate = [[NSView alloc] initWithFrame:NSZeroRect];
    self.iconPreviewPlate.wantsLayer = YES;
    self.iconPreviewPlate.layer.cornerRadius = 8.0;
    self.iconPreviewPlate.layer.masksToBounds = YES;
    self.iconPreviewPlate.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;
    self.iconPreviewPlate.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconPreviewPlate.widthAnchor constraintEqualToConstant:40],
        [self.iconPreviewPlate.heightAnchor constraintEqualToConstant:40],
    ]];

    self.iconPreviewImage = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.iconPreviewImage.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.iconPreviewImage.translatesAutoresizingMaskIntoConstraints = NO;

    self.iconPreviewLetter = [NSTextField labelWithString:@""];
    self.iconPreviewLetter.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    self.iconPreviewLetter.textColor = NSColor.whiteColor;
    self.iconPreviewLetter.alignment = NSTextAlignmentCenter;
    self.iconPreviewLetter.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconPreviewLetter.hidden = YES;

    [self.iconPreviewPlate addSubview:self.iconPreviewImage];
    [self.iconPreviewPlate addSubview:self.iconPreviewLetter];
    [NSLayoutConstraint activateConstraints:@[
        [self.iconPreviewImage.topAnchor constraintEqualToAnchor:self.iconPreviewPlate.topAnchor],
        [self.iconPreviewImage.leadingAnchor constraintEqualToAnchor:self.iconPreviewPlate.leadingAnchor],
        [self.iconPreviewImage.trailingAnchor constraintEqualToAnchor:self.iconPreviewPlate.trailingAnchor],
        [self.iconPreviewImage.bottomAnchor constraintEqualToAnchor:self.iconPreviewPlate.bottomAnchor],
        [self.iconPreviewLetter.centerXAnchor constraintEqualToAnchor:self.iconPreviewPlate.centerXAnchor],
        [self.iconPreviewLetter.centerYAnchor constraintEqualToAnchor:self.iconPreviewPlate.centerYAnchor],
    ]];

    NSStackView *iconURLRow = [NSStackView stackViewWithViews:@[self.iconURLField, self.fetchIconButton]];
    iconURLRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    iconURLRow.alignment = NSLayoutAttributeCenterY;
    iconURLRow.spacing = 8;
    iconURLRow.distribution = NSStackViewDistributionFill;
    [self.iconURLField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.autoIconRow = iconURLRow;

    NSTextField *letterCaption = [NSTextField labelWithString:@"字母"];
    NSStackView *letterRow = [NSStackView stackViewWithViews:@[letterCaption, self.letterField]];
    letterRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    letterRow.alignment = NSLayoutAttributeCenterY;
    letterRow.spacing = 8;

    self.colorButtons = [NSMutableArray array];
    NSMutableArray<NSView *> *colorRows = [NSMutableArray array];
    for (NSInteger row = 0; row < 4; row++) {
        NSMutableArray<NSView *> *rowButtons = [NSMutableArray array];
        for (NSInteger col = 0; col < 4; col++) {
            NSInteger index = row * 4 + col;
            NSButton *swatch = [[NSButton alloc] initWithFrame:NSZeroRect];
            swatch.bordered = NO;
            swatch.wantsLayer = YES;
            swatch.layer.cornerRadius = 10.0;
            swatch.layer.masksToBounds = YES;
            swatch.layer.backgroundColor = [BrowserShortcutIconPalette colorAtIndex:index].CGColor;
            swatch.tag = index;
            swatch.target = self;
            swatch.action = @selector(onColorSwatch:);
            swatch.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [swatch.widthAnchor constraintEqualToConstant:20],
                [swatch.heightAnchor constraintEqualToConstant:20],
            ]];
            [self.colorButtons addObject:swatch];
            [rowButtons addObject:swatch];
        }
        NSStackView *rowStack = [NSStackView stackViewWithViews:rowButtons];
        rowStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        rowStack.spacing = 6;
        [colorRows addObject:rowStack];
    }
    self.colorGrid = [NSStackView stackViewWithViews:colorRows];
    self.colorGrid.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.colorGrid.spacing = 6;
    self.colorGrid.alignment = NSLayoutAttributeLeading;

    NSStackView *letterOptions = [NSStackView stackViewWithViews:@[letterRow, self.colorGrid]];
    letterOptions.orientation = NSUserInterfaceLayoutOrientationVertical;
    letterOptions.alignment = NSLayoutAttributeLeading;
    letterOptions.spacing = 8;
    self.letterOptionsView = letterOptions;

    NSStackView *iconBody = [NSStackView stackViewWithViews:@[
        styleRow,
        self.autoIconRow,
        self.letterOptionsView,
    ]];
    iconBody.orientation = NSUserInterfaceLayoutOrientationVertical;
    iconBody.alignment = NSLayoutAttributeLeading;
    iconBody.spacing = 8;
    iconBody.distribution = NSStackViewDistributionFill;

    NSStackView *iconPreviewColumn = [NSStackView stackViewWithViews:@[self.iconPreviewPlate, iconBody]];
    iconPreviewColumn.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    iconPreviewColumn.alignment = NSLayoutAttributeTop;
    iconPreviewColumn.spacing = 12;
    iconPreviewColumn.distribution = NSStackViewDistributionFill;
    [iconBody setContentHuggingPriority:NSLayoutPriorityDefaultLow
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
        @[iconCaption, iconPreviewColumn],
    ]];
    grid.columnSpacing = 12;
    grid.rowSpacing = 10;
    [grid columnAtIndex:0].width = 48;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    for (NSInteger row = 0; row < grid.numberOfRows; row++) {
        [grid rowAtIndex:row].yPlacement = NSGridCellPlacementTop;
    }
    [grid setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                     forOrientation:NSLayoutConstraintOrientationVertical];
    [grid setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationVertical];

    NSStackView *buttons = [NSStackView stackViewWithViews:@[cancelButton, saveButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8;

    NSStackView *root = [[NSStackView alloc] initWithFrame:NSZeroRect];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.distribution = NSStackViewDistributionGravityAreas;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [root addView:grid inGravity:NSStackViewGravityTop];
    [root addView:self.errorLabel inGravity:NSStackViewGravityTop];
    [root addView:buttons inGravity:NSStackViewGravityBottom];

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

- (void)applyStyleModeUI {
    self.autoStyleButton.state = self.usingLetterStyle ? NSControlStateValueOff : NSControlStateValueOn;
    self.letterStyleButton.state = self.usingLetterStyle ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoIconRow.hidden = self.usingLetterStyle;
    self.letterOptionsView.hidden = !self.usingLetterStyle;
    self.iconURLField.enabled = !self.usingLetterStyle;
    self.fetchIconButton.enabled = !self.usingLetterStyle && !self.fetchingIcon;
    self.letterField.enabled = self.usingLetterStyle;
    [self updateColorSelectionChrome];
}

- (void)updateColorSelectionChrome {
    for (NSButton *button in self.colorButtons) {
        BOOL selected = (button.tag == self.selectedColorIndex);
        button.layer.borderWidth = selected ? 2.0 : 0.0;
        button.layer.borderColor = selected ? NSColor.whiteColor.CGColor : nil;
        if (selected) {
            button.layer.shadowOpacity = 0.35;
            button.layer.shadowRadius = 2.0;
            button.layer.shadowOffset = CGSizeMake(0, -0.5);
            button.layer.masksToBounds = NO;
        } else {
            button.layer.shadowOpacity = 0;
            button.layer.masksToBounds = YES;
        }
    }
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

- (void)onStyleChanged:(NSButton *)sender {
    BOOL wantLetter = (sender == self.letterStyleButton);
    if (wantLetter == self.usingLetterStyle) {
        [self applyStyleModeUI];
        return;
    }
    self.usingLetterStyle = wantLetter;
    if (wantLetter) {
        if (self.letterField.stringValue.length == 0) {
            self.letterField.stringValue = [BrowserShortcutIconPalette defaultLetterForTitle:self.titleField.stringValue
                                                                                   urlString:self.urlField.stringValue];
        }
        if (self.editingShortcut == nil || !self.editingShortcut.usesCustomLetterIcon) {
            self.selectedColorIndex = [BrowserShortcutIconPalette defaultIndexForURLString:self.urlField.stringValue];
        }
        [self cancelInFlightFetch];
    }
    [self applyStyleModeUI];
    [self refreshIconPreview];
}

- (void)onColorSwatch:(NSButton *)sender {
    self.selectedColorIndex = [BrowserShortcutIconPalette clampedIndex:sender.tag];
    [self updateColorSelectionChrome];
    [self refreshIconPreview];
}

- (void)onFetchIcon:(id)sender {
    (void)sender;
    if (self.fetchingIcon || self.usingLetterStyle) {
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
        if (strongSelf.usingLetterStyle) {
            return;
        }
        if (image == nil || iconURL.absoluteString.length == 0) {
            [strongSelf showError:@"未能获取图标，可手动填写"];
            return;
        }

        strongSelf.iconURLField.stringValue = iconURL.absoluteString;
        [strongSelf showAutoPreviewImage:image];
        strongSelf.errorLabel.hidden = YES;
    }];
}

- (void)setFetchingIcon:(BOOL)fetchingIcon {
    _fetchingIcon = fetchingIcon;
    if (!self.usingLetterStyle) {
        self.fetchIconButton.enabled = !fetchingIcon;
    }
    self.fetchIconButton.title = fetchingIcon ? @"获取中…" : @"自动获取";
}

- (void)showAutoPreviewImage:(NSImage *)image {
    self.iconPreviewImage.image = image;
    self.iconPreviewImage.hidden = NO;
    self.iconPreviewLetter.hidden = YES;
    self.iconPreviewPlate.layer.backgroundColor = NSColor.clearColor.CGColor;
}

- (void)showLetterPreview {
    NSString *letter = [BrowserShortcutIconPalette normalizedLetterFromString:self.letterField.stringValue];
    if (letter.length == 0) {
        letter = [BrowserShortcutIconPalette defaultLetterForTitle:self.titleField.stringValue
                                                         urlString:self.urlField.stringValue];
    }
    self.iconPreviewImage.image = nil;
    self.iconPreviewImage.hidden = YES;
    self.iconPreviewLetter.hidden = NO;
    self.iconPreviewLetter.stringValue = letter;
    NSColor *color = [BrowserShortcutIconPalette colorAtIndex:self.selectedColorIndex];
    self.iconPreviewPlate.layer.backgroundColor = color.CGColor;
}

- (void)refreshIconPreview {
    if (self.usingLetterStyle) {
        [self showLetterPreview];
        return;
    }

    NSString *iconURL = self.iconURLField.stringValue;
    NSString *pageURL = self.urlField.stringValue;
    self.iconPreviewImage.image = nil;
    self.iconPreviewImage.hidden = NO;
    self.iconPreviewLetter.hidden = YES;
    self.iconPreviewPlate.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;

    NSString *host = BrowserFaviconHostFromURLString(pageURL);
    if (host.length > 0) {
        NSImage *cached = [[BrowserFaviconService sharedService] cachedImageForHost:host];
        if (cached != nil) {
            [self showAutoPreviewImage:cached];
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
        if (strongSelf == nil || image == nil || strongSelf.usingLetterStyle) {
            return;
        }
        if (![strongSelf.iconURLField.stringValue isEqualToString:iconURL]) {
            return;
        }
        [strongSelf showAutoPreviewImage:image];
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
    if (!self.usingLetterStyle) {
        if (![BrowserShortcutStore validateIconURLString:iconInput normalizedURL:&normalizedIconURL]) {
            [self showError:@"请输入有效的图标链接，需包含 http/https 与域名"];
            return;
        }
    } else {
        // 自定义色块时保留已有 iconURL，不因空/无效链接挡保存。
        if (iconInput.length > 0 &&
            [BrowserShortcutStore validateIconURLString:iconInput normalizedURL:&normalizedIconURL]) {
            // keep normalized
        } else if (self.editingShortcut != nil && self.editingShortcut.iconURLString.length > 0) {
            normalizedIconURL = self.editingShortcut.iconURLString;
        } else {
            normalizedIconURL = @"";
        }
    }

    NSString *style = self.usingLetterStyle ? BrowserShortcutIconStyleLetter : BrowserShortcutIconStyleAuto;
    NSString *letter = [BrowserShortcutIconPalette normalizedLetterFromString:self.letterField.stringValue];
    if (self.usingLetterStyle && letter.length == 0) {
        letter = [BrowserShortcutIconPalette defaultLetterForTitle:title urlString:normalizedURL];
    }
    NSInteger colorIndex = [BrowserShortcutIconPalette clampedIndex:self.selectedColorIndex];

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
    result.iconStyle = style;
    result.iconLetter = letter;
    result.iconColorIndex = colorIndex;

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
    if (obj.object == self.letterField || obj.object == self.titleField) {
        if (self.usingLetterStyle) {
            [self refreshIconPreview];
        }
        return;
    }
    if (obj.object == self.iconURLField || obj.object == self.urlField) {
        if (self.usingLetterStyle) {
            return;
        }
        NSString *host = BrowserFaviconHostFromURLString(self.urlField.stringValue);
        if (host.length > 0) {
            NSImage *cached = [[BrowserFaviconService sharedService] cachedImageForHost:host];
            if (cached != nil) {
                [self showAutoPreviewImage:cached];
                return;
            }
        }
        if (self.iconURLField.stringValue.length == 0) {
            self.iconPreviewImage.image = nil;
            self.iconPreviewLetter.hidden = YES;
            self.iconPreviewPlate.layer.backgroundColor = NSColor.quaternaryLabelColor.CGColor;
        } else {
            [self refreshIconPreview];
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
