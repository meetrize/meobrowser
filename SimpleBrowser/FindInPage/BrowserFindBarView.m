#import "BrowserFindBarView.h"
#import "SBTextField.h"

@interface BrowserFindBarView () <NSTextFieldDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSStackView *stack;
@property (nonatomic, strong) NSButton *optionsButton;
@property (nonatomic, strong) NSButton *modeButton;
@property (nonatomic, strong, readwrite) SBTextField *queryField;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSButton *previousButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign, readwrite) BrowserFindMode mode;
@property (nonatomic, assign, readwrite) BOOL caseSensitive;
@property (nonatomic, strong, nullable) NSColor *countDefaultColor;
@end

@implementation BrowserFindBarView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _mode = BrowserFindModeLiteral;
        _caseSensitive = NO;
        [self buildUI];
    }
    return self;
}

- (NSImage *)symbol:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return [image imageWithSymbolConfiguration:config] ?: image;
    }
    return nil;
}

- (NSButton *)iconButtonWithSymbol:(NSString *)symbol toolTip:(NSString *)tip action:(SEL)action {
    NSButton *button = [NSButton buttonWithImage:[self symbol:symbol] target:self action:action];
    button.bordered = NO;
    button.toolTip = tip;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:22].active = YES;
    [button.heightAnchor constraintEqualToConstant:22].active = YES;
    return button;
}

- (void)buildUI {
    static const CGFloat kCornerRadius = 8.0;

    // 外层负责投影：masksToBounds 必须为 NO，否则阴影会被裁掉。
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
    self.layer.shadowColor = NSColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.22;
    self.layer.shadowRadius = 14.0;
    // AppKit layer 坐标系 Y 向上；负值让阴影落在浮层下方。
    self.layer.shadowOffset = CGSizeMake(0, -3.0);

    self.effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.effectView.translatesAutoresizingMaskIntoConstraints = NO;
    // Menu 材质比 Popover 更不透明，与网页对比更清晰。
    self.effectView.material = NSVisualEffectMaterialMenu;
    self.effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.effectView.state = NSVisualEffectStateActive;
    self.effectView.wantsLayer = YES;
    self.effectView.layer.masksToBounds = YES;
    self.effectView.layer.cornerRadius = kCornerRadius;
    if (@available(macOS 10.15, *)) {
        self.effectView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.effectView.layer.borderWidth = 0.5;
    [self addSubview:self.effectView];
    [self updateChromeAppearance];

    self.optionsButton = [self iconButtonWithSymbol:@"textformat.abc"
                                            toolTip:@"查找选项"
                                             action:@selector(showOptionsMenu:)];
    self.modeButton = [self iconButtonWithSymbol:@"magnifyingglass"
                                         toolTip:@"字面匹配（点击切换通配符）"
                                          action:@selector(toggleMode:)];

    self.queryField = [SBTextField standardField];
    self.queryField.translatesAutoresizingMaskIntoConstraints = NO;
    self.queryField.placeholderString = @"查找";
    self.queryField.delegate = self;
    self.queryField.font = [NSFont systemFontOfSize:13];
    self.queryField.trailingContentInset = 22;
    // 矮输入框内默认 bezel 文字上下 inset 过大，底部易被裁切。
    self.queryField.usesCompactVerticalTextInsets = YES;
    [self.queryField.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    [self.queryField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.clearButton = [NSButton buttonWithImage:[self symbol:@"xmark.circle.fill"]
                                          target:self
                                          action:@selector(clearQuery:)];
    self.clearButton.bordered = NO;
    self.clearButton.hidden = YES;
    self.clearButton.toolTip = @"清空";
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.queryField addSubview:self.clearButton];

    self.previousButton = [self iconButtonWithSymbol:@"chevron.up"
                                             toolTip:@"上一个（⇧F3 / ⌘⇧G）"
                                              action:@selector(goPrevious:)];
    self.nextButton = [self iconButtonWithSymbol:@"chevron.down"
                                         toolTip:@"下一个（F3 / ⌘G）"
                                          action:@selector(goNext:)];
    self.previousButton.enabled = NO;
    self.nextButton.enabled = NO;

    self.countLabel = [NSTextField labelWithString:@"—"];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.countLabel.textColor = [NSColor secondaryLabelColor];
    self.countLabel.alignment = NSTextAlignmentRight;
    [self.countLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    self.countDefaultColor = self.countLabel.textColor;

    self.closeButton = [self iconButtonWithSymbol:@"xmark"
                                          toolTip:@"关闭（Esc）"
                                           action:@selector(closeBar:)];

    self.stack = [NSStackView stackViewWithViews:@[
        self.optionsButton,
        self.modeButton,
        self.queryField,
        self.previousButton,
        self.nextButton,
        self.countLabel,
        self.closeButton
    ]];
    self.stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.stack.spacing = 4;
    self.stack.alignment = NSLayoutAttributeCenterY;
    self.stack.edgeInsets = NSEdgeInsetsMake(6, 8, 6, 8);
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.effectView addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.effectView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.effectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.effectView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.effectView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.effectView.topAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.effectView.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.effectView.trailingAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.effectView.bottomAnchor],
        [self.queryField.heightAnchor constraintEqualToConstant:24],
        [self.clearButton.widthAnchor constraintEqualToConstant:14],
        [self.clearButton.heightAnchor constraintEqualToConstant:14],
        [self.clearButton.centerYAnchor constraintEqualToAnchor:self.queryField.centerYAnchor],
        [self.clearButton.trailingAnchor constraintEqualToAnchor:self.queryField.trailingAnchor constant:-6],
    ]];

    [self refreshModeButton];
}

- (void)layout {
    [super layout];
    [self updateShadowPath];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateChromeAppearance];
}

- (void)updateChromeAppearance {
    if (!self.effectView.layer) {
        return;
    }
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        NSString *match = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua,
            NSAppearanceNameDarkAqua
        ]];
        dark = [match isEqualToString:NSAppearanceNameDarkAqua];
    }
    CGFloat borderAlpha = dark ? 0.45 : 0.28;
    self.effectView.layer.borderColor = [[NSColor separatorColor] colorWithAlphaComponent:borderAlpha].CGColor;
    self.layer.shadowOpacity = dark ? 0.45 : 0.22;
}

- (void)updateShadowPath {
    if (!self.layer || NSIsEmptyRect(self.bounds)) {
        return;
    }
    CGFloat radius = self.effectView.layer.cornerRadius;
    CGPathRef path = CGPathCreateWithRoundedRect(NSRectToCGRect(self.bounds), radius, radius, NULL);
    self.layer.shadowPath = path;
    CGPathRelease(path);
}

- (void)refreshModeButton {
    if (self.mode == BrowserFindModeWildcard) {
        self.modeButton.image = [self symbol:@"asterisk"];
        if (!self.modeButton.image) {
            self.modeButton.image = [self symbol:@"magnifyingglass"];
            self.modeButton.title = @"*";
        } else {
            self.modeButton.title = @"";
        }
        self.modeButton.toolTip = @"通配符：* 匹配任意字符（点击切回字面）";
        self.modeButton.contentTintColor = [NSColor controlAccentColor];
    } else {
        self.modeButton.image = [self symbol:@"magnifyingglass"];
        self.modeButton.title = @"";
        self.modeButton.toolTip = @"字面匹配（点击切换通配符）";
        self.modeButton.contentTintColor = [NSColor secondaryLabelColor];
    }
}

- (void)applySession:(BrowserFindSession *)session {
    self.mode = session.mode;
    self.caseSensitive = session.caseSensitive;
    self.queryField.stringValue = session.query ?: @"";
    [self refreshModeButton];
    [self refreshClearButton];
    [self updateMatchCount:session.currentIndex
                     total:session.matchCount
                 truncated:session.truncated
                   invalid:NO];
    [self setNavigationEnabled:session.matchCount > 0];
}

- (void)setMode:(BrowserFindMode)mode {
    _mode = mode;
    [self refreshModeButton];
}

- (void)setCaseSensitive:(BOOL)caseSensitive {
    _caseSensitive = caseSensitive;
}

- (void)updateMatchCount:(NSInteger)current total:(NSInteger)total truncated:(BOOL)truncated invalid:(BOOL)invalid {
    self.countLabel.textColor = self.countDefaultColor ?: [NSColor secondaryLabelColor];
    NSString *query = [self.queryField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.countLabel.stringValue = @"—";
        return;
    }
    if (invalid) {
        self.countLabel.stringValue = @"无效";
        self.countLabel.textColor = [NSColor systemOrangeColor];
        return;
    }
    NSString *totalText = truncated ? [NSString stringWithFormat:@"%ld+", (long)total] : [NSString stringWithFormat:@"%ld", (long)total];
    if (total <= 0) {
        self.countLabel.stringValue = @"0 / 0";
        self.countLabel.textColor = [NSColor secondaryLabelColor];
        return;
    }
    if (total > 999) {
        totalText = truncated ? @"999+" : @"999+";
    }
    NSInteger displayCurrent = MIN(MAX(current, 0), total > 999 ? 999 : total);
    self.countLabel.stringValue = [NSString stringWithFormat:@"%ld / %@", (long)displayCurrent, totalText];
}

- (void)flashWrapHint {
    self.countLabel.textColor = [NSColor controlAccentColor];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.countLabel.textColor = weakSelf.countDefaultColor ?: [NSColor secondaryLabelColor];
    });
}

- (void)focusAndSelectAll {
    [self.window makeFirstResponder:self.queryField];
    NSText *editor = [self.queryField currentEditor];
    if (editor) {
        [editor selectAll:nil];
    } else {
        [self.queryField selectText:nil];
    }
}

- (void)setNavigationEnabled:(BOOL)enabled {
    self.previousButton.enabled = enabled;
    self.nextButton.enabled = enabled;
}

- (void)setFindEnabled:(BOOL)enabled {
    self.queryField.enabled = enabled;
    self.optionsButton.enabled = enabled;
    self.modeButton.enabled = enabled;
    self.clearButton.enabled = enabled;
    if (!enabled) {
        self.queryField.placeholderString = @"当前页无法查找";
        [self setNavigationEnabled:NO];
        self.countLabel.stringValue = @"—";
    } else {
        self.queryField.placeholderString = @"查找";
    }
}

- (void)refreshClearButton {
    NSString *text = self.queryField.stringValue ?: @"";
    self.clearButton.hidden = (text.length == 0);
}

#pragma mark - Actions

- (void)toggleMode:(id)sender {
    (void)sender;
    self.mode = (self.mode == BrowserFindModeLiteral) ? BrowserFindModeWildcard : BrowserFindModeLiteral;
    [self refreshModeButton];
    [self.delegate findBarViewDidToggleMode:self];
}

- (void)showOptionsMenu:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"查找选项"];
    NSMenuItem *caseItem = [[NSMenuItem alloc] initWithTitle:@"区分大小写"
                                                      action:@selector(toggleCaseSensitive:)
                                               keyEquivalent:@""];
    caseItem.target = self;
    caseItem.state = self.caseSensitive ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:caseItem];
    NSButton *button = (NSButton *)sender;
    NSPoint point = NSMakePoint(0, NSMaxY(button.bounds) + 2);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:button];
}

- (void)toggleCaseSensitive:(id)sender {
    (void)sender;
    self.caseSensitive = !self.caseSensitive;
    [self.delegate findBarViewDidToggleCaseSensitive:self];
}

- (void)clearQuery:(id)sender {
    (void)sender;
    self.queryField.stringValue = @"";
    [self refreshClearButton];
    [self.window makeFirstResponder:self.queryField];
    [self.delegate findBarViewQueryDidChange:self];
}

- (void)goNext:(id)sender {
    (void)sender;
    [self.delegate findBarViewDidRequestNext:self];
}

- (void)goPrevious:(id)sender {
    (void)sender;
    [self.delegate findBarViewDidRequestPrevious:self];
}

- (void)closeBar:(id)sender {
    (void)sender;
    [self.delegate findBarViewDidRequestClose:self];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    (void)obj;
    [self refreshClearButton];
    [self.delegate findBarViewQueryDidChange:self];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;
    // 回车只走这里（key monitor 不再处理 Return），避免重复 next。
    if (commandSelector == @selector(insertNewline:) || commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
        NSEvent *event = NSApp.currentEvent;
        BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
        if (shift) {
            [self.delegate findBarViewDidRequestPrevious:self];
        } else {
            [self.delegate findBarViewDidRequestNext:self];
        }
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self.delegate findBarViewDidRequestClose:self];
        return YES;
    }
    return NO;
}

@end
