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
static const NSTimeInterval kTabHoverTipDelay = 0.65;

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

/// 标题栏 accessory 内系统 toolTip 基本不弹出；用共享浮层模拟 Chrome 悬停提示。
@interface BrowserTabHoverTipWindow : NSObject
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, weak) NSView *anchorView;
@property (nonatomic, copy, nullable) NSString *pendingText;
@property (nonatomic, strong, nullable) NSTimer *delayTimer;
+ (instancetype)shared;
- (void)scheduleText:(NSString *)text fromView:(NSView *)view;
- (void)cancelForView:(nullable NSView *)view;
- (void)hide;
@end

@implementation BrowserTabHoverTipWindow

+ (instancetype)shared {
    static BrowserTabHoverTipWindow *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrowserTabHoverTipWindow alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10)
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:YES];
        _panel.opaque = NO;
        _panel.backgroundColor = [NSColor clearColor];
        _panel.hasShadow = YES;
        _panel.level = NSFloatingWindowLevel;
        _panel.ignoresMouseEvents = YES;
        _panel.hidesOnDeactivate = YES;
        _panel.releasedWhenClosed = NO;

        NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
        root.wantsLayer = YES;
        root.layer.cornerRadius = 6.0;
        if (@available(macOS 10.15, *)) {
            root.layer.cornerCurve = kCACornerCurveContinuous;
        }

        _label = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _label.editable = NO;
        _label.selectable = NO;
        _label.bordered = NO;
        _label.drawsBackground = NO;
        _label.font = [NSFont systemFontOfSize:11];
        _label.maximumNumberOfLines = 6;
        _label.lineBreakMode = NSLineBreakByWordWrapping;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8],
            [_label.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-8],
            [_label.topAnchor constraintEqualToAnchor:root.topAnchor constant:6],
            [_label.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6],
        ]];
        _panel.contentView = root;
    }
    return self;
}

- (void)applyAppearance {
    BOOL dark = NO;
    NSAppearance *appearance = self.anchorView.effectiveAppearance ?: NSApp.effectiveAppearance;
    if ([appearance.name containsString:@"Dark"]) {
        dark = YES;
    }
    NSView *root = self.panel.contentView;
    if (dark) {
        root.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.18 alpha:0.96] CGColor];
        self.label.textColor = [NSColor whiteColor];
    } else {
        root.layer.backgroundColor = [[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.88 alpha:0.98] CGColor];
        self.label.textColor = [NSColor blackColor];
    }
    self.panel.appearance = appearance;
}

- (void)scheduleText:(NSString *)text fromView:(NSView *)view {
    if (text.length == 0 || view == nil || view.window == nil) {
        if (self.anchorView == view) {
            [self hide];
            self.anchorView = nil;
            self.pendingText = nil;
        }
        return;
    }

    // 同一锚点、同一文案：已显示或已在倒计时则不重置，避免 mouseMoved 抖掉 tip。
    if (self.anchorView == view && [self.pendingText isEqualToString:text]) {
        if (self.panel.isVisible || self.delayTimer != nil) {
            return;
        }
    }

    // 文案变化但 tip 已显示：立即更新内容。
    if (self.anchorView == view && self.panel.isVisible && self.delayTimer == nil) {
        self.pendingText = [text copy];
        [self displayText:text fromView:view];
        return;
    }

    [self cancelTimer];
    self.anchorView = view;
    self.pendingText = [text copy];
    __weak typeof(self) weakSelf = self;
    __weak NSView *weakView = view;
    NSString *payload = [text copy];
    self.delayTimer = [NSTimer timerWithTimeInterval:kTabHoverTipDelay
                                             repeats:NO
                                               block:^(NSTimer *timer) {
                                                   (void)timer;
                                                   [weakSelf displayText:payload fromView:weakView];
                                               }];
    [[NSRunLoop mainRunLoop] addTimer:self.delayTimer forMode:NSRunLoopCommonModes];
}

- (void)displayText:(NSString *)text fromView:(NSView *)view {
    if (view == nil || view != self.anchorView || view.window == nil || text.length == 0) {
        return;
    }
    NSPoint windowPoint = [view.window mouseLocationOutsideOfEventStream];
    NSPoint local = [view convertPoint:windowPoint fromView:nil];
    if (![view mouse:local inRect:view.bounds]) {
        [self hide];
        return;
    }

    self.label.stringValue = text;
    self.label.preferredMaxLayoutWidth = 420.0;
    [self applyAppearance];
    [self.label invalidateIntrinsicContentSize];
    NSSize labelSize = [self.label sizeThatFits:NSMakeSize(420.0, CGFLOAT_MAX)];
    CGFloat width = MIN(436.0, MAX(80.0, ceil(labelSize.width) + 16.0));
    CGFloat height = ceil(labelSize.height) + 12.0;
    [self.panel setContentSize:NSMakeSize(width, height)];

    NSRect viewRect = [view convertRect:view.bounds toView:nil];
    NSRect screenRect = [view.window convertRectToScreen:viewRect];
    CGFloat tipX = NSMidX(screenRect) - width * 0.5;
    CGFloat tipY = NSMinY(screenRect) - height - 6.0;
    NSScreen *screen = view.window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    if (tipX < NSMinX(visible) + 4) {
        tipX = NSMinX(visible) + 4;
    }
    if (tipX + width > NSMaxX(visible) - 4) {
        tipX = NSMaxX(visible) - width - 4;
    }
    if (tipY < NSMinY(visible) + 4) {
        tipY = NSMaxY(screenRect) + 6.0;
    }
    [self.panel setFrameOrigin:NSMakePoint(tipX, tipY)];
    NSWindow *parent = view.window;
    if (parent) {
        NSInteger minLevel = (NSInteger)parent.level + 1;
        if ((NSInteger)self.panel.level < minLevel) {
            self.panel.level = (NSWindowLevel)minLevel;
        }
    }
    [self.panel orderFront:nil];
}

- (void)cancelTimer {
    [self.delayTimer invalidate];
    self.delayTimer = nil;
}

- (void)cancelForView:(NSView *)view {
    if (view != nil && self.anchorView != view) {
        return;
    }
    [self cancelTimer];
    [self hide];
    self.anchorView = nil;
    self.pendingText = nil;
}

- (void)hide {
    [self cancelTimer];
    [self.panel orderOut:nil];
}

@end

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

- (void)dealloc {
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
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

- (void)setTabToolTip:(NSString *)tabToolTip {
    NSString *normalized = tabToolTip.length > 0 ? [tabToolTip copy] : nil;
    if ((_tabToolTip == nil && normalized == nil) || [_tabToolTip isEqualToString:normalized]) {
        return;
    }
    _tabToolTip = normalized;
    if (self.pointerInside) {
        [self scheduleHoverTipIfNeeded];
    }
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
    // 需要 MouseMoved：在标题区与关闭按钮之间移动时切换 tip 文案。
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
        | NSTrackingMouseMoved
        | NSTrackingActiveInKeyWindow
        | NSTrackingInVisibleRect;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (nullable NSString *)hoverTipTextForCurrentPointer {
    if (!self.window) {
        return nil;
    }
    NSPoint windowPoint = [self.window mouseLocationOutsideOfEventStream];
    NSPoint local = [self convertPoint:windowPoint fromView:nil];
    if (![self mouse:local inRect:self.bounds]) {
        return nil;
    }
    if (!self.closeButton.hidden) {
        NSPoint inClose = [self.closeButton convertPoint:local fromView:self];
        if ([self.closeButton mouse:inClose inRect:self.closeButton.bounds]) {
            return @"关闭标签页";
        }
    }
    return self.tabToolTip;
}

- (void)scheduleHoverTipIfNeeded {
    NSString *text = [self hoverTipTextForCurrentPointer];
    if (text.length == 0) {
        [[BrowserTabHoverTipWindow shared] cancelForView:self];
        return;
    }
    [[BrowserTabHoverTipWindow shared] scheduleText:text fromView:self];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.pointerInside = YES;
    [self updateCloseButtonVisibility];
    [self scheduleHoverTipIfNeeded];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.pointerInside = NO;
    [self updateCloseButtonVisibility];
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
}

- (void)mouseMoved:(NSEvent *)event {
    (void)event;
    if (self.pointerInside) {
        [self scheduleHoverTipIfNeeded];
    }
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
    [[BrowserTabHoverTipWindow shared] cancelForView:self];

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
            CGFloat deltaY = next.locationInWindow.y - start.y;
            CGFloat distance = hypot(deltaX, deltaY);
            if (!dragging) {
                if (distance < kReorderDragThreshold) {
                    continue;
                }
                dragging = YES;
                if (self.onReorderDragBegan) {
                    self.onReorderDragBegan(next.locationInWindow);
                }
            }
            if (self.onReorderDragMoved) {
                self.onReorderDragMoved(next.locationInWindow);
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
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
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
    (void)event;
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
    if (self.contextMenuProvider) {
        return self.contextMenuProvider();
    }
    return nil;
}

@end
