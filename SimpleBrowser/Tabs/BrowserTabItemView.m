#import "BrowserTabItemView.h"

const CGFloat BrowserTabItemMinWidth = 108.0;
const CGFloat BrowserTabItemMaxWidth = 200.0;
/// 固定标签仍显示标题，宽度参与等宽分配时的最小宽与普通标签一致。
const CGFloat BrowserTabPinnedWidth = 108.0;

static const CGFloat kDefaultTabHeight = 31.0;
static const CGFloat kCloseAlwaysVisibleMinWidth = 120.0;
static const CGFloat kReorderDragThreshold = 4.0;
static const CGFloat kPinIconSize = 12.0;
static const CGFloat kLeadingPadding = 8.0;
static const CGFloat kTitleAfterPinGap = 4.0;

/// 标题不参与命中，全部由标签本身接收拖拽
@interface BrowserTabTitleLabel : NSTextField
@end

@implementation BrowserTabTitleLabel
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

@interface BrowserTabPinIconView : NSImageView
@end

@implementation BrowserTabPinIconView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

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
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingToPin;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingToEdge;
@property (nonatomic, strong) NSLayoutConstraint *pinLeadingConstraint;
@property (nonatomic, assign) CGFloat appliedWidth;
@property (nonatomic, assign) BOOL pointerInside;
@end

@implementation BrowserTabItemView

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIntrinsicContentSize {
    return [NSSet setWithObjects:@"tabTitle", @"tabSelected", @"tabPinned", nil];
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
        _tabTitle = @"";

        _titleLabel = [BrowserTabTitleLabel labelWithString:@"新标签页"];
        _titleLabel.font = [NSFont systemFontOfSize:12];
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.usesSingleLineMode = YES;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.refusesFirstResponder = YES;
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_titleLabel];

        _pinIconView = [[BrowserTabPinIconView alloc] initWithFrame:NSZeroRect];
        _pinIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _pinIconView.imageScaling = NSImageScaleProportionallyDown;
        _pinIconView.hidden = YES;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:10
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
        _pinLeadingConstraint = [_pinIconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                           constant:kLeadingPadding];
        _titleLeadingToPin = [_titleLabel.leadingAnchor constraintEqualToAnchor:_pinIconView.trailingAnchor
                                                                       constant:kTitleAfterPinGap];
        _titleLeadingToEdge = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                        constant:10];

        [NSLayoutConstraint activateConstraints:@[
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:16],
            [_closeButton.heightAnchor constraintEqualToConstant:16],

            _pinLeadingConstraint,
            [_pinIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pinIconView.widthAnchor constraintEqualToConstant:kPinIconSize],
            [_pinIconView.heightAnchor constraintEqualToConstant:kPinIconSize],

            _titleLeadingToEdge,
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _titleTrailingToClose,
        ]];
        _titleLeadingToPin.active = NO;

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

- (void)updatePinnedAppearance {
    BOOL showPin = self.tabPinned && (self.pinIconView.image != nil);
    self.pinIconView.hidden = !showPin;
    self.titleLabel.hidden = NO;
    self.titleLabel.stringValue = self.tabTitle.length > 0 ? self.tabTitle : @"新标签页";

    self.titleLeadingToPin.active = showPin;
    self.titleLeadingToEdge.active = !showPin;

    if (self.tabPinned) {
        self.closeButton.hidden = YES;
        self.titleTrailingToClose.active = NO;
        self.titleTrailingToEdge.active = YES;
    }
}

- (void)updateCloseButtonVisibility {
    if (self.tabPinned) {
        self.closeButton.hidden = YES;
        self.titleTrailingToClose.active = NO;
        self.titleTrailingToEdge.active = YES;
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

- (BOOL)isOpaque {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) {
        return nil;
    }
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (![self mouse:local inRect:self.bounds]) {
        return nil;
    }
    if (!self.closeButton.hidden) {
        NSPoint inClose = [self.closeButton convertPoint:local fromView:self];
        if ([self.closeButton mouse:inClose inRect:self.closeButton.bounds]) {
            return self.closeButton;
        }
    }
    return self;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount >= 2) {
        if (!self.tabPinned && self.onClose) {
            self.onClose();
        }
        return;
    }

    if (self.onSelect) {
        self.onSelect();
    }

    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    NSPoint start = event.locationInWindow;
    BOOL dragging = NO;
    NSEventMask mask = NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;

    while (YES) {
        NSEvent *next = [window nextEventMatchingMask:mask
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next) {
            break;
        }

        if (next.type == NSEventTypeLeftMouseDragged) {
            CGFloat deltaX = next.locationInWindow.x - start.x;
            if (!dragging) {
                if (fabs(deltaX) < kReorderDragThreshold) {
                    continue;
                }
                dragging = YES;
                if (self.onReorderDragBegan) {
                    self.onReorderDragBegan();
                }
            }
            if (self.onReorderDragMoved) {
                self.onReorderDragMoved(deltaX);
            }
            continue;
        }

        if (dragging && self.onReorderDragEnded) {
            self.onReorderDragEnded(next.locationInWindow);
        }
        break;
    }
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
