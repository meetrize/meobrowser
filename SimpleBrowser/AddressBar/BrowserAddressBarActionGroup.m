#import "BrowserAddressBarActionGroup.h"

static const CGFloat kActionButtonSize = 28.0;
static const CGFloat kActionButtonSpacing = 2.0;
static const CGFloat kDefaultGroupWidth = 156.0;
static const CGFloat kMinimumGroupWidth = 36.0;
static const CGFloat kOverflowHysteresis = 8.0;

#pragma mark - Edge Resize

@implementation BrowserAddressBarEdgeResizeView

- (BOOL)isOpaque {
    return NO;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window disableCursorRects];
    [[NSCursor resizeLeftRightCursor] set];
    if (self.onDragBegan) {
        self.onDragBegan();
    }

    NSPoint lastPoint = [self convertPoint:event.locationInWindow fromView:nil];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
        CGFloat deltaX = point.x - lastPoint.x;
        lastPoint = point;
        if (self.onDrag && fabs(deltaX) > 0.01) {
            self.onDrag(deltaX);
        }
    }

    if (self.onDragEnded) {
        self.onDragEnded();
    }
    [self.window enableCursorRects];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

@end

#pragma mark - Action Item

@interface BrowserAddressBarActionItem : NSObject
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *toolTip;
@end

@implementation BrowserAddressBarActionItem
@end

#pragma mark - Action Group

@interface BrowserAddressBarActionGroup ()
@property (nonatomic, strong) NSStackView *buttonStack;
@property (nonatomic, strong) NSButton *overflowButton;
@property (nonatomic, strong) NSMenu *overflowMenu;
@property (nonatomic, strong) NSArray<BrowserAddressBarActionItem *> *items;
@property (nonatomic, strong) NSArray<NSButton *> *actionButtons;
@property (nonatomic, assign) CGFloat preferredWidth;
@property (nonatomic, assign) CGFloat maximumWidth;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL showsOverflowButton;
@property (nonatomic, strong, readwrite) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overflowWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overflowLeadingSpacingConstraint;
@property (nonatomic, assign) NSInteger lastMenuStartIndex;
@property (nonatomic, assign) NSInteger lastVisibleButtonCount;
@end

@implementation BrowserAddressBarActionGroup

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _preferredWidth = kDefaultGroupWidth;
        _maximumWidth = 400.0;
        _minimumAddressWidth = 120.0;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        _items = [self demoItems];
        _actionButtons = [self makeActionButtonsForItems:_items];
        _buttonStack = [NSStackView stackViewWithViews:_actionButtons];
        _buttonStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _buttonStack.spacing = kActionButtonSpacing;
        _buttonStack.translatesAutoresizingMaskIntoConstraints = NO;

        _overflowMenu = [[NSMenu alloc] init];
        _overflowButton = [self makeOverflowButton];
        _overflowButton.hidden = YES;

        [self addSubview:_buttonStack];
        [self addSubview:_overflowButton];

        _overflowWidthConstraint = [self.overflowButton.widthAnchor constraintEqualToConstant:0];
        _overflowLeadingSpacingConstraint = [self.overflowButton.leadingAnchor constraintEqualToAnchor:self.buttonStack.trailingAnchor];

        [NSLayoutConstraint activateConstraints:@[
            [self.buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.buttonStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.buttonStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            _overflowLeadingSpacingConstraint,
            [self.overflowButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.overflowButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _overflowWidthConstraint,
            [self.overflowButton.heightAnchor constraintEqualToConstant:kActionButtonSize],
        ]];

        _widthConstraint = [self.widthAnchor constraintEqualToConstant:_preferredWidth];
        _widthConstraint.priority = NSLayoutPriorityRequired;
        _widthConstraint.active = YES;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSZeroRect];
}

- (NSArray<BrowserAddressBarActionItem *> *)demoItems {
    NSArray<NSDictionary<NSString *, NSString *> *> *specs = @[
        @{@"symbol": @"square.and.arrow.up", @"tip": @"分享"},
        @{@"symbol": @"camera", @"tip": @"截图"},
        @{@"symbol": @"text.bubble", @"tip": @"评论"},
        @{@"symbol": @"puzzlepiece.extension", @"tip": @"扩展"},
        @{@"symbol": @"gearshape", @"tip": @"页面设置"},
        @{@"symbol": @"doc.on.doc", @"tip": @"复制链接"},
    ];
    NSMutableArray<BrowserAddressBarActionItem *> *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *spec in specs) {
        BrowserAddressBarActionItem *item = [[BrowserAddressBarActionItem alloc] init];
        item.symbolName = spec[@"symbol"];
        item.toolTip = spec[@"tip"];
        [items addObject:item];
    }
    return items;
}

- (NSImage *)symbolImageNamed:(NSString *)symbolName {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:15
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (NSButton *)makeToolbarButtonWithSymbol:(NSString *)symbolName toolTip:(NSString *)toolTip {
    NSImage *image = [self symbolImageNamed:symbolName];
    NSButton *button = image ? [NSButton buttonWithImage:image target:self action:@selector(demoButtonClicked:)]
                             : [NSButton buttonWithTitle:@"?" target:self action:@selector(demoButtonClicked:)];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = toolTip;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kActionButtonSize],
    ]];
    return button;
}

- (NSArray<NSButton *> *)makeActionButtonsForItems:(NSArray<BrowserAddressBarActionItem *> *)items {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (BrowserAddressBarActionItem *item in items) {
        NSButton *button = [self makeToolbarButtonWithSymbol:item.symbolName toolTip:item.toolTip];
        [buttons addObject:button];
    }
    return buttons;
}

- (NSButton *)makeOverflowButton {
    NSButton *button = [self makeToolbarButtonWithSymbol:@"chevron.right" toolTip:@"更多工具"];
    button.target = self;
    button.action = @selector(showOverflowMenu:);
    return button;
}

- (void)demoButtonClicked:(id)sender {
    // 演示按钮，功能待实现。
}

- (void)showOverflowMenu:(NSButton *)sender {
    NSPoint location = NSMakePoint(0, NSHeight(sender.bounds));
    [self.overflowMenu popUpMenuPositioningItem:nil atLocation:location inView:sender];
}

- (CGFloat)clampedPreferredWidth:(CGFloat)width {
    CGFloat minWidth = kMinimumGroupWidth;
    CGFloat maxWidth = MAX(minWidth, self.maximumWidth);
    return MIN(MAX(width, minWidth), maxWidth);
}

- (void)applyWidthDelta:(CGFloat)deltaX {
    CGFloat next = [self clampedPreferredWidth:round(self.preferredWidth + deltaX)];
    if (fabs(next - self.preferredWidth) < 0.5) {
        return;
    }
    self.preferredWidth = next;
    self.widthConstraint.constant = next;
    [self updateOverflowLayoutForWidth:next];
}

- (void)beginWidthResize {
    self.isDragging = YES;
}

- (void)endWidthResize {
    self.isDragging = NO;
}

- (void)setIsDragging:(BOOL)isDragging {
    if (_isDragging == isDragging) {
        return;
    }
    _isDragging = isDragging;
    if (!isDragging) {
        [self updateOverflowLayout];
    }
}

- (CGFloat)totalButtonsWidth {
    NSInteger count = (NSInteger)self.actionButtons.count;
    if (count == 0) {
        return 0;
    }
    return [self widthForButtonCount:count includeOverflow:NO];
}

- (CGFloat)widthForButtonCount:(NSInteger)count includeOverflow:(BOOL)includeOverflow {
    if (count <= 0) {
        return includeOverflow ? kActionButtonSize : 0;
    }
    CGFloat width = (CGFloat)count * kActionButtonSize + (CGFloat)(count - 1) * kActionButtonSpacing;
    if (includeOverflow) {
        width += kActionButtonSpacing + kActionButtonSize;
    }
    return width;
}

- (NSInteger)visibleButtonCountForAvailableWidth:(CGFloat)available total:(NSInteger)total {
    NSInteger visibleCount = 0;
    for (NSInteger i = 1; i <= total; i++) {
        if ([self widthForButtonCount:i includeOverflow:NO] <= available + 0.5) {
            visibleCount = i;
        } else {
            break;
        }
    }
    return visibleCount;
}

- (void)applyVisibleButtonCount:(NSInteger)visibleCount total:(NSInteger)total {
    if (visibleCount == self.lastVisibleButtonCount) {
        return;
    }
    self.lastVisibleButtonCount = visibleCount;
    for (NSInteger i = 0; i < total; i++) {
        BOOL shouldHide = (i >= visibleCount);
        NSButton *button = self.actionButtons[i];
        if (button.hidden != shouldHide) {
            button.hidden = shouldHide;
        }
    }
}

- (void)updateOverflowLayout {
    CGFloat groupWidth = floor(self.preferredWidth > 0 ? self.preferredWidth : MAX(0, NSWidth(self.bounds)));
    [self updateOverflowLayoutForWidth:groupWidth];
}

- (void)updateOverflowLayoutForWidth:(CGFloat)groupWidth {
    NSInteger total = (NSInteger)self.actionButtons.count;
    if (total == 0) {
        self.showsOverflowButton = NO;
        [self applyOverflowPresentation];
        return;
    }

    groupWidth = floor(MAX(0, groupWidth));
    CGFloat allButtonsWidth = [self totalButtonsWidth];
    BOOL shouldShowOverflow = NO;

    if (self.showsOverflowButton) {
        shouldShowOverflow = (groupWidth + kOverflowHysteresis) < allButtonsWidth;
    } else {
        shouldShowOverflow = groupWidth < allButtonsWidth;
    }

    if (self.showsOverflowButton != shouldShowOverflow) {
        self.showsOverflowButton = shouldShowOverflow;
        [self applyOverflowPresentation];
    }

    NSInteger visibleCount = total;
    NSInteger menuStartIndex = total;
    if (shouldShowOverflow) {
        CGFloat available = groupWidth - (kActionButtonSpacing + kActionButtonSize);
        visibleCount = [self visibleButtonCountForAvailableWidth:available total:total];
        visibleCount = MAX(0, MIN(visibleCount, total - 1));
        menuStartIndex = visibleCount;
    }

    [self applyVisibleButtonCount:visibleCount total:total];
    [self rebuildOverflowMenuStartingAtIndex:menuStartIndex];
}

- (void)applyOverflowPresentation {
    if (self.showsOverflowButton) {
        self.overflowWidthConstraint.constant = kActionButtonSize;
        self.overflowLeadingSpacingConstraint.constant = kActionButtonSpacing;
        self.overflowButton.hidden = NO;
    } else {
        self.overflowWidthConstraint.constant = 0;
        self.overflowLeadingSpacingConstraint.constant = 0;
        self.overflowButton.hidden = YES;
    }
}

- (void)rebuildOverflowMenuStartingAtIndex:(NSInteger)startIndex {
    if (self.overflowMenu.numberOfItems > 0 &&
        self.lastMenuStartIndex == startIndex &&
        !self.isDragging) {
        return;
    }
    self.lastMenuStartIndex = startIndex;

    [self.overflowMenu removeAllItems];
    NSInteger total = (NSInteger)self.items.count;
    for (NSInteger i = startIndex; i < total; i++) {
        BrowserAddressBarActionItem *item = self.items[i];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:item.toolTip
                                                          action:@selector(demoButtonClicked:)
                                                   keyEquivalent:@""];
        menuItem.target = self;
        menuItem.image = [self symbolImageNamed:item.symbolName];
        [self.overflowMenu addItem:menuItem];
    }
}

- (void)layout {
    [super layout];
    [self updateMaximumWidthFromWindow];
    if (!self.isDragging) {
        [self updateOverflowLayout];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:self.window];
        [self updateMaximumWidthFromWindow];
        [self updateOverflowLayout];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSWindowDidResizeNotification
                                                      object:self.window];
    }
    [super viewWillMoveToWindow:newWindow];
}

- (void)windowDidResize:(NSNotification *)notification {
    if (!self.isDragging) {
        [self updateMaximumWidthFromWindow];
        [self updateOverflowLayout];
    }
}

- (void)updateMaximumWidthFromWindow {
    NSView *container = self.layoutContainer ?: self.superview;
    if (!container) {
        return;
    }
    CGFloat containerWidth = floor(NSWidth(container.bounds));
    if (containerWidth < 1.0) {
        return;
    }
    self.maximumWidth = MAX(kMinimumGroupWidth, containerWidth - self.minimumAddressWidth);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
