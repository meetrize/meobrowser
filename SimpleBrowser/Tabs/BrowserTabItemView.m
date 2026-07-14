#import "BrowserTabItemView.h"

const CGFloat BrowserTabItemMinWidth = 108.0;
const CGFloat BrowserTabItemMaxWidth = 200.0;
const CGFloat BrowserTabPinnedWidth = 36.0;

static const CGFloat kDefaultTabHeight = 33.0;
static const CGFloat kCloseAlwaysVisibleMinWidth = 120.0;
static const CGFloat kReorderDragThreshold = 4.0;

NSColor *BrowserTabActiveFillColor(void) {
    if ([[NSApp effectiveAppearance].name containsString:@"Dark"]) {
        return [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
    }
    return [NSColor whiteColor];
}

@interface BrowserTabItemView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSImageView *pinIconView;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToClose;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToEdge;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, assign) CGFloat appliedWidth;
@property (nonatomic, assign) BOOL pointerInside;
@property (nonatomic, assign) BOOL trackingMouse;
@property (nonatomic, assign) BOOL isReorderDragging;
@property (nonatomic, assign) NSPoint mouseDownWindowPoint;
@end

@implementation BrowserTabItemView

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIntrinsicContentSize {
    return [NSSet setWithObjects:@"tabTitle", @"tabSelected", @"tabPinned", nil];
}

- (NSSize)intrinsicContentSize {
    CGFloat height = self.heightConstraint ? self.heightConstraint.constant : kDefaultTabHeight;
    CGFloat width = self.tabPinned ? BrowserTabPinnedWidth : BrowserTabItemMinWidth;
    return NSMakeSize(width, height);
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
        _tabTitle = @"";

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

        _pinIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _pinIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _pinIconView.imageScaling = NSImageScaleProportionallyDown;
        _pinIconView.hidden = YES;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:11
                                                                weight:NSFontWeightMedium
                                                                 scale:NSImageSymbolScaleMedium];
            NSImage *symbol = [NSImage imageWithSystemSymbolName:@"pin.fill"
                                        accessibilityDescription:@"固定标签页"];
            _pinIconView.image = symbol ? [symbol imageWithSymbolConfiguration:config] : nil;
            if (@available(macOS 10.14, *)) {
                _pinIconView.contentTintColor = [NSColor secondaryLabelColor];
            }
        }
        [self addSubview:_pinIconView];

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
        _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10];

        [NSLayoutConstraint activateConstraints:@[
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:16],
            [_closeButton.heightAnchor constraintEqualToConstant:16],

            _titleLeadingConstraint,
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _titleTrailingToClose,

            [_pinIconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_pinIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pinIconView.widthAnchor constraintEqualToConstant:14],
            [_pinIconView.heightAnchor constraintEqualToConstant:14],
        ]];

        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self updateChromeAppearance];
        [self updatePinnedAppearance];
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

- (void)setTabPinned:(BOOL)tabPinned {
    if (_tabPinned == tabPinned) {
        return;
    }
    _tabPinned = tabPinned;
    [self updatePinnedAppearance];
    [self updateCloseButtonVisibility];
    [self invalidateIntrinsicContentSize];
}

- (void)setTabTitle:(NSString *)tabTitle {
    NSString *normalized = tabTitle ?: @"";
    if ([_tabTitle isEqualToString:normalized]) {
        return;
    }
    _tabTitle = [normalized copy];
    if (self.tabPinned) {
        [self updatePinnedAppearance];
    } else {
        self.titleLabel.stringValue = normalized.length > 0 ? normalized : @"新标签页";
        self.toolTip = nil;
    }
    [self invalidateIntrinsicContentSize];
}

- (void)applyAvailableWidth:(CGFloat)width {
    if (fabs(self.appliedWidth - width) < 0.5) {
        return;
    }
    self.appliedWidth = width;
    [self updateCloseButtonVisibility];
}

- (void)updatePinnedAppearance {
    BOOL hasPinImage = (self.pinIconView.image != nil);
    self.pinIconView.hidden = !self.tabPinned || !hasPinImage;
    self.titleLabel.hidden = self.tabPinned && hasPinImage;
    if (self.tabPinned && !hasPinImage) {
        NSString *title = self.tabTitle.length > 0 ? self.tabTitle : @"新标签页";
        self.titleLabel.stringValue = [title substringToIndex:MIN((NSUInteger)1, title.length)];
        self.titleLeadingConstraint.constant = 10;
    } else if (!self.tabPinned) {
        self.titleLabel.stringValue = self.tabTitle.length > 0 ? self.tabTitle : @"新标签页";
        self.titleLeadingConstraint.constant = 10;
    }
    self.toolTip = self.tabPinned ? (self.tabTitle.length > 0 ? self.tabTitle : @"新标签页") : nil;
    if (self.tabPinned) {
        self.closeButton.hidden = YES;
        self.titleTrailingToClose.active = NO;
        self.titleTrailingToEdge.active = NO;
    }
}

- (void)updateCloseButtonVisibility {
    if (self.tabPinned) {
        self.closeButton.hidden = YES;
        self.titleTrailingToClose.active = NO;
        self.titleTrailingToEdge.active = NO;
        return;
    }

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
    if (@available(macOS 10.14, *)) {
        self.pinIconView.contentTintColor = self.tabSelected ? [NSColor labelColor]
                                                             : [NSColor secondaryLabelColor];
    }
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
    // 双击标签关闭（固定标签除外）；单击切换
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount >= 2) {
        if (!self.tabPinned && self.onClose) {
            self.onClose();
        }
        return;
    }

    self.trackingMouse = YES;
    self.isReorderDragging = NO;
    self.mouseDownWindowPoint = event.locationInWindow;
    if (self.onSelect) {
        self.onSelect();
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.trackingMouse) {
        return;
    }

    CGFloat deltaX = event.locationInWindow.x - self.mouseDownWindowPoint.x;
    if (!self.isReorderDragging) {
        if (fabs(deltaX) < kReorderDragThreshold) {
            return;
        }
        self.isReorderDragging = YES;
        if (self.onReorderDragBegan) {
            self.onReorderDragBegan();
        }
    }

    if (self.onReorderDragMoved) {
        self.onReorderDragMoved(deltaX);
    }
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (self.isReorderDragging && self.onReorderDragEnded) {
        self.onReorderDragEnded();
    }
    self.trackingMouse = NO;
    self.isReorderDragging = NO;
}

- (void)onClose:(id)sender {
    (void)sender;
    if (self.tabPinned) {
        return;
    }
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
