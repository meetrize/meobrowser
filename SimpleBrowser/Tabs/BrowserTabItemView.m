#import "BrowserTabItemView.h"

const CGFloat BrowserTabItemMinWidth = 108.0;
const CGFloat BrowserTabItemMaxWidth = 200.0;

static const CGFloat kDefaultTabHeight = 33.0;
static const CGFloat kCloseAlwaysVisibleMinWidth = 120.0;

NSColor *BrowserTabActiveFillColor(void) {
    if ([[NSApp effectiveAppearance].name containsString:@"Dark"]) {
        return [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
    }
    return [NSColor whiteColor];
}

@interface BrowserTabItemView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToClose;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToEdge;
@property (nonatomic, assign) CGFloat appliedWidth;
@property (nonatomic, assign) BOOL pointerInside;
@end

@implementation BrowserTabItemView

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIntrinsicContentSize {
    return [NSSet setWithObjects:@"tabTitle", @"tabSelected", nil];
}

- (NSSize)intrinsicContentSize {
    CGFloat height = self.heightConstraint ? self.heightConstraint.constant : kDefaultTabHeight;
    return NSMakeSize(BrowserTabItemMinWidth, height);
}

- (void)setTabHeight:(CGFloat)height {
    if (!self.heightConstraint) {
        self.heightConstraint = [self.heightAnchor constraintEqualToConstant:height];
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = height;
    }
    [self invalidateIntrinsicContentSize];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        _appliedWidth = BrowserTabItemMaxWidth;

        _titleLabel = [NSTextField labelWithString:@"新标签页"];
        _titleLabel.font = [NSFont systemFontOfSize:12];
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.usesSingleLineMode = YES;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        // 避免标题拦截点击，导致无法切换标签
        _titleLabel.refusesFirstResponder = YES;
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_titleLabel];

        _closeButton = [NSButton buttonWithTitle:@"×" target:self action:@selector(onClose:)];
        _closeButton.bezelStyle = NSBezelStyleInline;
        _closeButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeButton setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_closeButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_closeButton];

        _titleTrailingToClose = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor
                                                                                     constant:-4];
        _titleTrailingToEdge = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                    constant:-8];

        [NSLayoutConstraint activateConstraints:@[
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:16],
            [_closeButton.heightAnchor constraintEqualToConstant:16],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _titleTrailingToClose,
        ]];

        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self updateChromeAppearance];
        [self updateCloseButtonVisibility];
    }
    return self;
}

- (void)setTabSelected:(BOOL)tabSelected {
    _tabSelected = tabSelected;
    [self updateChromeAppearance];
    [self updateCloseButtonVisibility];
    [self invalidateIntrinsicContentSize];
}

- (void)setTabTitle:(NSString *)tabTitle {
    NSString *normalized = tabTitle ?: @"";
    if ([_tabTitle isEqualToString:normalized]) {
        return;
    }
    _tabTitle = [normalized copy];
    self.titleLabel.stringValue = normalized.length > 0 ? normalized : @"新标签页";
    [self invalidateIntrinsicContentSize];
}

- (void)applyAvailableWidth:(CGFloat)width {
    if (fabs(self.appliedWidth - width) < 0.5) {
        return;
    }
    self.appliedWidth = width;
    [self updateCloseButtonVisibility];
}

- (void)updateCloseButtonVisibility {
    BOOL alwaysShow = self.tabSelected || self.appliedWidth >= kCloseAlwaysVisibleMinWidth;
    BOOL visible = alwaysShow || self.pointerInside;
    self.closeButton.hidden = !visible;
    self.titleTrailingToClose.active = visible;
    self.titleTrailingToEdge.active = !visible;
}

- (void)updateChromeAppearance {
    BOOL dark = [self effectiveAppearanceIsDark];
    NSColor *active = BrowserTabActiveFillColor();
    NSColor *inactive = dark ? [NSColor colorWithCalibratedWhite:0.13 alpha:1.0]
                             : [NSColor colorWithCalibratedWhite:0.82 alpha:1.0];

    self.layer.backgroundColor = (self.tabSelected ? active : inactive).CGColor;

    if (@available(macOS 10.13, *)) {
        // 顶角弧度贴近系统窗口（约 10–12pt），略大于侧缘以免选中态显得更方。
        self.layer.cornerRadius = self.tabSelected ? 11.0 : 10.0;
        self.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        if (@available(macOS 10.15, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }

    self.titleLabel.textColor = [NSColor labelColor];
    self.titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
}

- (BOOL)effectiveAppearanceIsDark {
    NSString *name = self.effectiveAppearance.name;
    return [name containsString:@"Dark"];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateChromeAppearance];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self.trackingAreas copy]) {
        [self removeTrackingArea:area];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.pointerInside = YES;
    [self updateCloseButtonVisibility];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.pointerInside = NO;
    [self updateCloseButtonVisibility];
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit) {
        return nil;
    }
    // 关闭按钮保持可点；标题等其它子视图点击视为选中标签
    if (hit == self.closeButton || [hit isDescendantOf:self.closeButton]) {
        return hit;
    }
    return self;
}

- (void)mouseDown:(NSEvent *)event {
    // 双击标签关闭；单击切换（双击序列里第一次仍会先选中，符合常见浏览器习惯）
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount >= 2) {
        if (self.onClose) {
            self.onClose();
        }
        return;
    }
    if (self.onSelect) {
        self.onSelect();
    }
}

- (void)onClose:(id)sender {
    (void)sender;
    BOOL optionHeld = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    if (optionHeld && self.onCloseTabsToTheRight) {
        self.onCloseTabsToTheRight();
        return;
    }
    if (self.onClose) {
        self.onClose();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.contextMenuProvider) {
        NSMenu *menu = self.contextMenuProvider();
        if (menu) {
            return menu;
        }
    }
    return [super menuForEvent:event];
}

@end
