#import "BrowserAddressBarActionGroup.h"

static const CGFloat kActionButtonSize = 28.0;
static const CGFloat kActionButtonSpacing = 2.0;
static const CGFloat kDefaultGroupWidth = 184.0;
static const CGFloat kMinimumGroupWidth = 36.0;
static const CGFloat kOverflowHysteresis = 8.0;
static const CGFloat kReorderDragThreshold = 4.0;
static NSString * const kActionOrderDefaultsKey = @"BrowserAddressBarActionOrder";

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
    (void)event;
    return YES;
}

@end

#pragma mark - Action Item

@interface BrowserAddressBarActionItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *toolTip;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation BrowserAddressBarActionItem
@end

#pragma mark - Reorderable Button

@class BrowserAddressBarActionGroup;

@interface BrowserAddressBarActionButton : NSButton
@property (nonatomic, weak) BrowserAddressBarActionGroup *actionGroup;
@end

@interface BrowserAddressBarActionGroup (Reorder)
- (void)handleMouseDownOnActionButton:(BrowserAddressBarActionButton *)button event:(NSEvent *)event;
@end

@implementation BrowserAddressBarActionButton

- (void)mouseDown:(NSEvent *)event {
    [self.actionGroup handleMouseDownOnActionButton:self event:event];
}

@end

#pragma mark - Action Group

@interface BrowserAddressBarActionGroup ()
@property (nonatomic, strong) NSStackView *buttonStack;
@property (nonatomic, strong) NSButton *overflowButton;
@property (nonatomic, strong) NSMenu *overflowMenu;
@property (nonatomic, strong) NSMutableArray<BrowserAddressBarActionItem *> *items;
@property (nonatomic, strong) NSMutableArray<NSButton *> *actionButtons;
@property (nonatomic, strong, readwrite) NSButton *downloadButton;
@property (nonatomic, assign) CGFloat preferredWidth;
@property (nonatomic, assign) CGFloat maximumWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, assign) BOOL isReordering;
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
        _lastVisibleButtonCount = -1;
        _lastMenuStartIndex = -1;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        _items = [[self orderedActionItems] mutableCopy];
        _actionButtons = [[self makeActionButtonsForItems:_items] mutableCopy];
        [self refreshDownloadButtonReference];

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

        // 不可 Required：否则用户拉宽动作区后，定宽会抬高窗口最小宽度，无法再拖窄
        _widthConstraint = [self.widthAnchor constraintEqualToConstant:_preferredWidth];
        _widthConstraint.priority = NSLayoutPriorityDefaultHigh;
        _widthConstraint.active = YES;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSZeroRect];
}

#pragma mark - Catalog & order

- (NSArray<BrowserAddressBarActionItem *> *)defaultActionItems {
    NSArray<NSDictionary<NSString *, NSString *> *> *specs = @[
        @{@"id": @"download", @"symbol": @"arrow.down.circle", @"tip": @"下载"},
        @{@"id": @"share", @"symbol": @"square.and.arrow.up", @"tip": @"分享"},
        @{@"id": @"screenshot", @"symbol": @"camera", @"tip": @"截图"},
        @{@"id": @"comment", @"symbol": @"text.bubble", @"tip": @"评论"},
        @{@"id": @"extension", @"symbol": @"puzzlepiece.extension", @"tip": @"扩展"},
        @{@"id": @"pageSettings", @"symbol": @"gearshape", @"tip": @"页面设置"},
        @{@"id": @"copyLink", @"symbol": @"doc.on.doc", @"tip": @"复制链接"},
    ];
    NSMutableArray<BrowserAddressBarActionItem *> *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *spec in specs) {
        BrowserAddressBarActionItem *item = [[BrowserAddressBarActionItem alloc] init];
        item.itemID = spec[@"id"];
        item.symbolName = spec[@"symbol"];
        item.toolTip = spec[@"tip"];
        [items addObject:item];
    }
    return items;
}

- (NSArray<BrowserAddressBarActionItem *> *)orderedActionItems {
    NSArray<BrowserAddressBarActionItem *> *defaults = [self defaultActionItems];
    NSMutableDictionary<NSString *, BrowserAddressBarActionItem *> *byID = [NSMutableDictionary dictionary];
    for (BrowserAddressBarActionItem *item in defaults) {
        byID[item.itemID] = item;
    }

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kActionOrderDefaultsKey];
    if (![saved isKindOfClass:[NSArray class]] || saved.count == 0) {
        return defaults;
    }

    NSMutableArray<BrowserAddressBarActionItem *> *ordered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in saved) {
        if (![entry isKindOfClass:[NSString class]]) {
            continue;
        }
        BrowserAddressBarActionItem *item = byID[entry];
        if (item && ![seen containsObject:item.itemID]) {
            [ordered addObject:item];
            [seen addObject:item.itemID];
        }
    }
    for (BrowserAddressBarActionItem *item in defaults) {
        if (![seen containsObject:item.itemID]) {
            [ordered addObject:item];
        }
    }
    return ordered;
}

- (void)persistActionOrder {
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:self.items.count];
    for (BrowserAddressBarActionItem *item in self.items) {
        if (item.itemID.length > 0) {
            [ids addObject:item.itemID];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kActionOrderDefaultsKey];
}

- (void)refreshDownloadButtonReference {
    self.downloadButton = nil;
    for (NSUInteger i = 0; i < self.items.count; i++) {
        if ([self.items[i].itemID isEqualToString:@"download"]) {
            self.downloadButton = self.actionButtons[i];
            break;
        }
    }
}

#pragma mark - Buttons

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

- (BrowserAddressBarActionButton *)makeToolbarButtonWithSymbol:(NSString *)symbolName toolTip:(NSString *)toolTip {
    NSImage *image = [self symbolImageNamed:symbolName];
    BrowserAddressBarActionButton *button = [[BrowserAddressBarActionButton alloc] initWithFrame:NSZeroRect];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = [NSString stringWithFormat:@"%@（拖动可调整顺序）", toolTip];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.actionGroup = self;
    if (image) {
        button.image = image;
    } else {
        button.title = @"?";
    }
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kActionButtonSize],
    ]];
    button.target = self;
    button.action = @selector(demoButtonClicked:);
    return button;
}

- (NSArray<NSButton *> *)makeActionButtonsForItems:(NSArray<BrowserAddressBarActionItem *> *)items {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (BrowserAddressBarActionItem *item in items) {
        BrowserAddressBarActionButton *button = [self makeToolbarButtonWithSymbol:item.symbolName toolTip:item.toolTip];
        if (item.target && item.action) {
            button.target = item.target;
            button.action = item.action;
        }
        [buttons addObject:button];
    }
    return buttons;
}

- (NSButton *)makeOverflowButton {
    NSButton *button = [NSButton buttonWithImage:[self symbolImageNamed:@"chevron.right"]
                                          target:self
                                          action:@selector(showOverflowMenu:)];
    if (!button.image) {
        button = [NSButton buttonWithTitle:@"…" target:self action:@selector(showOverflowMenu:)];
    }
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"更多工具";
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

- (void)demoButtonClicked:(id)sender {
    (void)sender;
}

- (void)showOverflowMenu:(NSButton *)sender {
    NSPoint location = NSMakePoint(0, NSHeight(sender.bounds));
    [self.overflowMenu popUpMenuPositioningItem:nil atLocation:location inView:sender];
}

#pragma mark - Reorder / click

- (void)handleMouseDownOnActionButton:(BrowserAddressBarActionButton *)button event:(NSEvent *)event {
    if (button.hidden || self.isResizingWidth) {
        return;
    }

    NSInteger fromIndex = [self.actionButtons indexOfObject:button];
    if (fromIndex == NSNotFound) {
        return;
    }

    button.highlighted = YES;
    NSPoint startInWindow = event.locationInWindow;
    BOOL didReorder = NO;
    NSInteger currentIndex = fromIndex;

    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }

        NSPoint now = next.locationInWindow;
        CGFloat dx = now.x - startInWindow.x;
        CGFloat dy = now.y - startInWindow.y;
        if (!didReorder && (dx * dx + dy * dy) >= (kReorderDragThreshold * kReorderDragThreshold)) {
            didReorder = YES;
            self.isReordering = YES;
            if (@available(macOS 10.14, *)) {
                button.contentTintColor = [NSColor controlAccentColor];
            }
            button.alphaValue = 0.55;
        }
        if (!didReorder) {
            continue;
        }

        NSPoint inStack = [self.buttonStack convertPoint:now fromView:nil];
        NSInteger targetIndex = [self insertionIndexForPointInStack:inStack
                                                    excludingButton:button
                                                      currentIndex:currentIndex];
        if (targetIndex > currentIndex) {
            [self swapActionAtIndex:currentIndex withIndex:currentIndex + 1];
            currentIndex += 1;
        } else if (targetIndex < currentIndex) {
            [self swapActionAtIndex:currentIndex withIndex:currentIndex - 1];
            currentIndex -= 1;
        }
    }

    button.highlighted = NO;
    button.alphaValue = 1.0;
    if (!didReorder) {
        // 短按：触发原按钮动作
        if (button.target && button.action && [button.target respondsToSelector:button.action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [button.target performSelector:button.action withObject:button];
#pragma clang diagnostic pop
        }
    } else {
        if (@available(macOS 10.14, *)) {
            // 下载按钮忙碌高亮由窗口控制器维护；此处恢复为默认次要色
            if (button != self.downloadButton) {
                button.contentTintColor = [NSColor secondaryLabelColor];
            } else {
                button.contentTintColor = [NSColor secondaryLabelColor];
            }
        }
        [self persistActionOrder];
        self.isReordering = NO;
        self.lastVisibleButtonCount = -1;
        self.lastMenuStartIndex = -1;
        [self updateOverflowLayout];
        // 通知外部：下载按钮引用未变，但若角标依赖布局可稍后刷新
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BrowserAddressBarActionOrderDidChangeNotification"
                                                            object:self];
    }
}

- (NSInteger)insertionIndexForPointInStack:(NSPoint)point
                           excludingButton:(NSButton *)dragged
                             currentIndex:(NSInteger)currentIndex {
    (void)dragged;
    NSInteger bestIndex = currentIndex;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < self.actionButtons.count; i++) {
        NSButton *candidate = self.actionButtons[i];
        if (candidate.hidden) {
            continue;
        }
        CGFloat midX = NSMidX(candidate.frame);
        CGFloat distance = fabs(point.x - midX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = (NSInteger)i;
        }
    }
    return bestIndex;
}

- (void)swapActionAtIndex:(NSInteger)indexA withIndex:(NSInteger)indexB {
    if (indexA == indexB ||
        indexA < 0 || indexB < 0 ||
        indexA >= (NSInteger)self.actionButtons.count ||
        indexB >= (NSInteger)self.actionButtons.count) {
        return;
    }
    if (self.actionButtons[indexA].hidden || self.actionButtons[indexB].hidden) {
        return;
    }

    [self.actionButtons exchangeObjectAtIndex:indexA withObjectAtIndex:indexB];
    [self.items exchangeObjectAtIndex:indexA withObjectAtIndex:indexB];

    for (NSButton *button in [self.actionButtons copy]) {
        [self.buttonStack removeArrangedSubview:button];
        [button removeFromSuperview];
    }
    for (NSButton *button in self.actionButtons) {
        [self.buttonStack addArrangedSubview:button];
    }

    [self refreshDownloadButtonReference];
    self.lastVisibleButtonCount = -1;
}

#pragma mark - Width resize

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
    self.isResizingWidth = YES;
}

- (void)endWidthResize {
    self.isResizingWidth = NO;
    [self updateOverflowLayout];
}

#pragma mark - Overflow

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
    if (self.isReordering) {
        return;
    }
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
        !self.isResizingWidth) {
        return;
    }
    self.lastMenuStartIndex = startIndex;

    [self.overflowMenu removeAllItems];
    NSInteger total = (NSInteger)self.items.count;
    for (NSInteger i = startIndex; i < total; i++) {
        BrowserAddressBarActionItem *item = self.items[i];
        SEL action = @selector(demoButtonClicked:);
        id target = self;
        if (i < (NSInteger)self.actionButtons.count) {
            NSButton *button = self.actionButtons[i];
            if (button.target && button.action) {
                target = button.target;
                action = button.action;
            }
        }
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:item.toolTip
                                                          action:action
                                                   keyEquivalent:@""];
        menuItem.target = target;
        menuItem.image = [self symbolImageNamed:item.symbolName];
        [self.overflowMenu addItem:menuItem];
    }
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    [self updateMaximumWidthFromWindow];
    if (!self.isResizingWidth && !self.isReordering) {
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
    (void)notification;
    if (!self.isResizingWidth && !self.isReordering) {
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
    CGFloat clamped = [self clampedPreferredWidth:self.preferredWidth];
    if (fabs(clamped - self.preferredWidth) > 0.5) {
        self.preferredWidth = clamped;
        self.widthConstraint.constant = clamped;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
