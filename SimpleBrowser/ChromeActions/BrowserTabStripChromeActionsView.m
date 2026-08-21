#import "BrowserTabStripChromeActionsView.h"
#import "BrowserChromeActionItem.h"
#import "BrowserChromeActionLayoutStore.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kChromeActionButtonSize = 22.0;
static const CGFloat kChromeActionSpacing = 2.0;
static const CGFloat kChromeActionSymbolPointSize = 12.0;
static const CGFloat kChromeActionReorderDragThreshold = 4.0;
static const CGFloat kChromeActionMoreDropPadding = 4.0;
static const CGFloat kChromeActionGhostPad = 14.0;
static const CGFloat kChromeActionGhostScale = 1.12;
static const CGFloat kChromeActionGhostAlpha = 0.92;
static const CGFloat kChromeActionSourceDragAlpha = 0.28;

@class BrowserTabStripChromeActionsView;

@interface BrowserTabStripChromeActionButton : NSButton
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, strong, nullable) BrowserChromeActionItem *actionItem;
@property (nonatomic, weak, nullable) BrowserTabStripChromeActionsView *actionsView;
@end

@interface BrowserTabStripChromeActionsView (Reorder)
- (void)handleMouseDownOnActionButton:(BrowserTabStripChromeActionButton *)button event:(NSEvent *)event;
@end

@implementation BrowserTabStripChromeActionButton

- (void)mouseDown:(NSEvent *)event {
    if ([self.itemID isEqualToString:BrowserChromeActionMoreMenuID]) {
        [super mouseDown:event];
        return;
    }
    [self.actionsView handleMouseDownOnActionButton:self event:event];
}

@end

@interface BrowserTabStripChromeActionsView ()
@property (nonatomic, copy, readwrite) NSArray<BrowserChromeActionItem *> *items;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserTabStripChromeActionButton *> *buttonsByID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *onStateByID;
@property (nonatomic, assign) BOOL isReordering;
@property (nonatomic, assign) BOOL moreMenuDropHighlighted;
@property (nonatomic, strong, nullable) NSPanel *dragGhostPanel;
@property (nonatomic, strong, nullable) NSImageView *dragGhostImageView;
@property (nonatomic, assign) NSPoint dragGhostGrabInSource;
@property (nonatomic, assign) NSSize dragGhostSourceSize;
@end

@implementation BrowserTabStripChromeActionsView

+ (NSArray<BrowserChromeActionItem *> *)itemsForCurrentLayout {
    NSMutableArray<BrowserChromeActionItem *> *items = [NSMutableArray array];
    for (NSString *itemID in [BrowserChromeActionLayoutStore visibleCustomActionIDs]) {
        BrowserChromeActionItem *item = [BrowserChromeActionItem catalogItemWithID:itemID];
        if (item) {
            [items addObject:item];
        }
    }
    [items addObject:[BrowserChromeActionItem moreMenuItem]];
    return [items copy];
}

+ (NSArray<BrowserChromeActionItem *> *)defaultItems {
    return [self itemsForCurrentLayout];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _buttonsByID = [NSMutableDictionary dictionary];
        _onStateByID = [NSMutableDictionary dictionary];
        _items = @[];

        _stackView = [NSStackView stackViewWithViews:@[]];
        _stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _stackView.spacing = kChromeActionSpacing;
        _stackView.alignment = NSLayoutAttributeCenterY;
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],
        ]];

        [self reloadFromLayoutStore];
    }
    return self;
}

- (CGFloat)preferredWidth {
    NSUInteger count = self.items.count;
    if (count == 0) {
        return 0;
    }
    return count * kChromeActionButtonSize + (count - 1) * kChromeActionSpacing;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize([self preferredWidth], kChromeActionButtonSize);
}

- (void)reloadFromLayoutStore {
    [self reloadWithItems:[[self class] itemsForCurrentLayout]];
}

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items {
    for (NSView *view in [self.stackView.views copy]) {
        [self.stackView removeView:view];
    }
    [self.buttonsByID removeAllObjects];

    self.items = [items copy] ?: @[];
    for (BrowserChromeActionItem *item in self.items) {
        BOOL on = [self.onStateByID[item.itemID] boolValue];
        BrowserTabStripChromeActionButton *button = [self makeButtonForItem:item on:on];
        self.buttonsByID[item.itemID] = button;
        [self.stackView addArrangedSubview:button];
    }

    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout:YES];
}

- (BrowserTabStripChromeActionButton *)makeButtonForItem:(BrowserChromeActionItem *)item on:(BOOL)on {
    BrowserTabStripChromeActionButton *button = [[BrowserTabStripChromeActionButton alloc] initWithFrame:NSZeroRect];
    button.itemID = item.itemID;
    button.actionItem = item;
    button.actionsView = self;
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    // 开态由 setOn:forItemID: 管理，避免 NSButtonTypeToggle 与 action 双翻
    button.buttonType = NSButtonTypeMomentaryChange;

    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kChromeActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],
    ]];

    [self applyAppearanceToButton:button item:item on:on];
    return button;
}

- (NSImage *)symbolImageNamed:(NSString *)symbolName {
    if (symbolName.length == 0) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:kChromeActionSymbolPointSize
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (void)applyAppearanceToButton:(BrowserTabStripChromeActionButton *)button
                           item:(BrowserChromeActionItem *)item
                             on:(BOOL)on {
    NSString *symbol = (on && item.onSymbolName.length > 0) ? item.onSymbolName : item.symbolName;
    NSImage *image = [self symbolImageNamed:symbol];
    if (image) {
        button.image = image;
        button.title = @"";
    } else {
        button.image = nil;
        button.title = on ? @"●" : @"○";
    }

    NSString *tip = (on && item.onToolTip.length > 0) ? item.onToolTip : item.toolTip;
    button.toolTip = tip;
    button.accessibilityLabel = tip;
    if (@available(macOS 10.10, *)) {
        button.accessibilityValue = on ? @"开" : @"关";
    }

    button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = on ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }
}

- (nullable NSButton *)buttonForItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return nil;
    }
    return self.buttonsByID[itemID];
}

- (void)setOn:(BOOL)on forItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    self.onStateByID[itemID] = @(on);
    BrowserTabStripChromeActionButton *button = self.buttonsByID[itemID];
    BrowserChromeActionItem *item = button.actionItem;
    if (!button || !item) {
        return;
    }
    [self applyAppearanceToButton:button item:item on:on];
}

- (BOOL)isOnForItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return NO;
    }
    return [self.onStateByID[itemID] boolValue];
}

#pragma mark - Reorder / drop on ⋯

- (void)endDragGhostImmediately {
    if (self.dragGhostPanel) {
        [self.dragGhostPanel orderOut:nil];
        self.dragGhostPanel = nil;
    }
    self.dragGhostImageView = nil;
    self.dragGhostSourceSize = NSZeroSize;
    self.dragGhostGrabInSource = NSZeroPoint;
}

- (void)beginDragGhostFromButton:(BrowserTabStripChromeActionButton *)button
                  windowPoint:(NSPoint)windowPoint {
    [self endDragGhostImmediately];
    if (!button || !button.window) {
        return;
    }

    NSRect bounds = button.bounds;
    if (NSWidth(bounds) < 1 || NSHeight(bounds) < 1) {
        return;
    }

    NSPoint grabInSource = [button convertPoint:windowPoint fromView:nil];
    self.dragGhostGrabInSource = grabInSource;
    self.dragGhostSourceSize = bounds.size;

    NSBitmapImageRep *rep = [button bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep) {
        return;
    }
    [button cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
    [image addRepresentation:rep];

    CGFloat scaledW = bounds.size.width * kChromeActionGhostScale;
    CGFloat scaledH = bounds.size.height * kChromeActionGhostScale;
    NSRect panelRect = NSMakeRect(0, 0,
                                  scaledW + kChromeActionGhostPad * 2.0,
                                  scaledH + kChromeActionGhostPad * 2.0);

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:panelRect
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = NO;
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSWindow *parent = button.window;
    NSInteger floating = (NSInteger)NSFloatingWindowLevel;
    NSInteger minLevel = parent ? ((NSInteger)parent.level + 1) : floating;
    panel.level = (NSWindowLevel)MAX(floating, minLevel);

    NSView *content = panel.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor clearColor].CGColor;

    NSRect imageFrame = NSMakeRect(kChromeActionGhostPad, kChromeActionGhostPad, scaledW, scaledH);
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:imageFrame];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleAxesIndependently;
    imageView.wantsLayer = YES;
    imageView.alphaValue = kChromeActionGhostAlpha;
    imageView.layer.masksToBounds = NO;
    imageView.layer.cornerRadius = 4.0;
    imageView.layer.shadowColor = [NSColor blackColor].CGColor;
    imageView.layer.shadowOpacity = 0.45;
    imageView.layer.shadowRadius = 10.0;
    imageView.layer.shadowOffset = CGSizeMake(0, -3);
    [content addSubview:imageView];

    self.dragGhostPanel = panel;
    self.dragGhostImageView = imageView;
    [self moveDragGhostToWindowPoint:windowPoint inWindow:button.window];
    [panel orderFront:nil];
}

- (void)moveDragGhostToWindowPoint:(NSPoint)windowPoint inWindow:(NSWindow *)window {
    if (!self.dragGhostPanel || !window) {
        return;
    }
    NSPoint screenPoint = [window convertPointToScreen:windowPoint];
    CGFloat scale = kChromeActionGhostScale;
    NSPoint origin = NSMakePoint(screenPoint.x - self.dragGhostGrabInSource.x * scale - kChromeActionGhostPad,
                                 screenPoint.y - self.dragGhostGrabInSource.y * scale - kChromeActionGhostPad);
    NSRect frame = self.dragGhostPanel.frame;
    frame.origin = origin;
    [self.dragGhostPanel setFrame:frame display:YES];
}

- (NSInteger)customButtonCount {
    NSInteger count = (NSInteger)self.stackView.arrangedSubviews.count;
    return MAX(0, count - 1); // 末尾固定 moreMenu
}

- (NSInteger)indexOfCustomButton:(BrowserTabStripChromeActionButton *)button {
    NSArray<NSView *> *arranged = self.stackView.arrangedSubviews;
    NSInteger customCount = [self customButtonCount];
    for (NSInteger i = 0; i < customCount; i++) {
        if (arranged[(NSUInteger)i] == button) {
            return i;
        }
    }
    return NSNotFound;
}

- (BOOL)isWindowPointOverMoreMenu:(NSPoint)windowPoint {
    NSButton *more = [self buttonForItemID:BrowserChromeActionMoreMenuID];
    if (!more) {
        return NO;
    }
    NSPoint local = [more convertPoint:windowPoint fromView:nil];
    NSRect hit = NSInsetRect(more.bounds, -kChromeActionMoreDropPadding, -kChromeActionMoreDropPadding);
    return NSPointInRect(local, hit);
}

- (void)setMoreMenuDropHighlighted:(BOOL)highlighted {
    if (_moreMenuDropHighlighted == highlighted) {
        return;
    }
    _moreMenuDropHighlighted = highlighted;
    BrowserTabStripChromeActionButton *more =
        (BrowserTabStripChromeActionButton *)[self buttonForItemID:BrowserChromeActionMoreMenuID];
    if (!more) {
        return;
    }
    if (highlighted) {
        more.alphaValue = 1.0;
        if (@available(macOS 10.14, *)) {
            more.contentTintColor = [NSColor controlAccentColor];
        }
    } else {
        more.alphaValue = 1.0;
        BOOL on = [self isOnForItemID:BrowserChromeActionMoreMenuID];
        if (more.actionItem) {
            [self applyAppearanceToButton:more item:more.actionItem on:on];
        }
    }
}

- (NSInteger)targetCustomIndexForPointInStack:(NSPoint)point currentIndex:(NSInteger)currentIndex {
    NSInteger customCount = [self customButtonCount];
    if (customCount <= 0) {
        return currentIndex;
    }
    NSArray<NSView *> *arranged = self.stackView.arrangedSubviews;
    NSInteger bestIndex = currentIndex;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger i = 0; i < customCount; i++) {
        NSView *candidate = arranged[(NSUInteger)i];
        CGFloat midX = NSMidX(candidate.frame);
        CGFloat distance = fabs(point.x - midX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
        }
    }
    return bestIndex;
}

- (void)swapCustomButtonAtIndex:(NSInteger)indexA withIndex:(NSInteger)indexB {
    NSInteger customCount = [self customButtonCount];
    if (indexA == indexB ||
        indexA < 0 || indexB < 0 ||
        indexA >= customCount || indexB >= customCount) {
        return;
    }

    NSMutableArray<NSView *> *arranged = [self.stackView.arrangedSubviews mutableCopy];
    [arranged exchangeObjectAtIndex:(NSUInteger)indexA withObjectAtIndex:(NSUInteger)indexB];

    for (NSView *view in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSView *view in arranged) {
        [self.stackView addArrangedSubview:view];
    }

    NSMutableArray<BrowserChromeActionItem *> *newItems = [NSMutableArray array];
    for (NSView *view in arranged) {
        if (![view isKindOfClass:[BrowserTabStripChromeActionButton class]]) {
            continue;
        }
        BrowserChromeActionItem *item = ((BrowserTabStripChromeActionButton *)view).actionItem;
        if (item) {
            [newItems addObject:item];
        }
    }
    self.items = [newItems copy];
}

- (NSArray<NSString *> *)visibleCustomActionIDsFromStack {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSInteger customCount = [self customButtonCount];
    NSArray<NSView *> *arranged = self.stackView.arrangedSubviews;
    for (NSInteger i = 0; i < customCount; i++) {
        NSView *view = arranged[(NSUInteger)i];
        if (![view isKindOfClass:[BrowserTabStripChromeActionButton class]]) {
            continue;
        }
        NSString *itemID = ((BrowserTabStripChromeActionButton *)view).itemID;
        if (itemID.length > 0) {
            [ids addObject:itemID];
        }
    }
    return [ids copy];
}

- (void)handleMouseDownOnActionButton:(BrowserTabStripChromeActionButton *)button event:(NSEvent *)event {
    if (!button || [button.itemID isEqualToString:BrowserChromeActionMoreMenuID]) {
        return;
    }
    if (!self.window) {
        return;
    }

    NSInteger fromIndex = [self indexOfCustomButton:button];
    if (fromIndex == NSNotFound) {
        return;
    }

    button.highlighted = YES;
    NSPoint startInWindow = event.locationInWindow;
    BOOL didReorder = NO;
    BOOL dropOnMore = NO;
    NSInteger currentIndex = fromIndex;

    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            dropOnMore = didReorder && [self isWindowPointOverMoreMenu:next.locationInWindow];
            break;
        }

        NSPoint now = next.locationInWindow;
        CGFloat dx = now.x - startInWindow.x;
        CGFloat dy = now.y - startInWindow.y;
        if (!didReorder && (dx * dx + dy * dy) >= (kChromeActionReorderDragThreshold * kChromeActionReorderDragThreshold)) {
            didReorder = YES;
            self.isReordering = YES;
            button.alphaValue = kChromeActionSourceDragAlpha;
            if (@available(macOS 10.14, *)) {
                button.contentTintColor = [NSColor tertiaryLabelColor];
            }
            [self beginDragGhostFromButton:button windowPoint:now];
        }
        if (!didReorder) {
            continue;
        }

        [self moveDragGhostToWindowPoint:now inWindow:self.window];

        if ([self isWindowPointOverMoreMenu:now]) {
            [self setMoreMenuDropHighlighted:YES];
            continue;
        }
        [self setMoreMenuDropHighlighted:NO];

        NSPoint inStack = [self.stackView convertPoint:now fromView:nil];
        NSInteger targetIndex = [self targetCustomIndexForPointInStack:inStack currentIndex:currentIndex];
        if (targetIndex > currentIndex) {
            [self swapCustomButtonAtIndex:currentIndex withIndex:currentIndex + 1];
            currentIndex += 1;
        } else if (targetIndex < currentIndex) {
            [self swapCustomButtonAtIndex:currentIndex withIndex:currentIndex - 1];
            currentIndex -= 1;
        }
    }

    NSString *draggedID = [button.itemID copy];
    [self endDragGhostImmediately];
    button.highlighted = NO;
    button.alphaValue = 1.0;
    [self setMoreMenuDropHighlighted:NO];
    self.isReordering = NO;

    if (button.actionItem) {
        [self applyAppearanceToButton:button item:button.actionItem on:[self isOnForItemID:draggedID]];
    }

    if (!didReorder) {
        if (button.action) {
            [NSApp sendAction:button.action to:button.target from:button];
        }
        return;
    }

    if (dropOnMore && draggedID.length > 0) {
        // 只隐藏：丢弃拖拽中的临时改序，由 Store 通知触发 reload
        [BrowserChromeActionLayoutStore setActionID:draggedID hidden:YES];
        return;
    }

    NSArray<NSString *> *visibleIDs = [self visibleCustomActionIDsFromStack];
    NSArray<NSString *> *merged =
        [BrowserChromeActionLayoutStore orderedIDsByReplacingVisibleSubsequence:visibleIDs];
    [BrowserChromeActionLayoutStore setOrderedCustomActionIDs:merged];
}

@end
