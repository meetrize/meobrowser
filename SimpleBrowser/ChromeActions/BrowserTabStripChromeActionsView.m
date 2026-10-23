#import "BrowserTabStripChromeActionsView.h"
#import "BrowserChromeActionItem.h"
#import "BrowserChromeActionLayoutStore.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kChromeActionButtonSize = 22.0;
static const CGFloat kChromeActionSpacing = 2.0;
static const CGFloat kChromeResizeHandleWidth = 10.0;
static const CGFloat kChromeResizeHandleSpacing = 2.0;
static const CGFloat kChromeActionSymbolPointSize = 12.0;
static const CGFloat kChromeActionReorderDragThreshold = 4.0;
static const CGFloat kChromeActionMoreDropPadding = 4.0;
static const CGFloat kChromeActionGhostPad = 14.0;
static const CGFloat kChromeActionGhostScale = 1.12;
static const CGFloat kChromeActionGhostAlpha = 0.92;
static const CGFloat kChromeActionSourceDragAlpha = 0.28;

@class BrowserTabStripChromeActionsView;

/// 竖三点拖柄。用窗口坐标回调，避免视图随宽度移动时本地 delta 反馈抖动。
@interface BrowserTabStripChromeResizeHandleView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(NSEvent *event);
@property (nonatomic, copy, nullable) void (^onDragToWindowX)(CGFloat windowX);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@end

@implementation BrowserTabStripChromeResizeHandleView

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    CGFloat cx = NSMidX(bounds);
    CGFloat cy = NSMidY(bounds);
    CGFloat radius = 1.15;
    CGFloat gap = 4.0;
    NSColor *color = [NSColor tertiaryLabelColor];
    for (NSInteger i = -1; i <= 1; i++) {
        NSRect dot = NSMakeRect(cx - radius, cy + (CGFloat)i * gap - radius, radius * 2.0, radius * 2.0);
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:dot];
        [color setFill];
        [path fill];
    }
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window disableCursorRects];
    [[NSCursor resizeLeftRightCursor] set];
    if (self.onDragBegan) {
        self.onDragBegan(event);
    }

    // 全程用窗口坐标；勿 convert 到 self，否则父视图变宽后本地点会反向漂移
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        if (self.onDragToWindowX) {
            self.onDragToWindowX(next.locationInWindow.x);
        }
    }

    if (self.onDragEnded) {
        self.onDragEnded();
    }
    [self.window enableCursorRects];
    [self.window invalidateCursorRectsForView:self];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

@end

/// 裁剪容器：右侧图标被宽度挤出时平滑裁切，而不是显隐闪动。
@interface BrowserTabStripChromeActionsClipView : NSView
@end

@implementation BrowserTabStripChromeActionsClipView
- (BOOL)isOpaque {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    // 裁剪区外（含被挤出的图标）不接收点击
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(local, self.bounds)) {
        return nil;
    }
    return [super hitTest:point];
}
@end

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
@property (nonatomic, strong) BrowserTabStripChromeResizeHandleView *resizeHandle;
@property (nonatomic, strong) BrowserTabStripChromeActionsClipView *clipView;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong, nullable) BrowserTabStripChromeActionButton *moreMenuButton;
@property (nonatomic, strong) NSMutableArray<BrowserTabStripChromeActionButton *> *actionButtons;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserTabStripChromeActionButton *> *buttonsByID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *onStateByID;
@property (nonatomic, assign) CGFloat allocatedWidth;
@property (nonatomic, assign, readwrite) BOOL isResizingWidth;
@property (nonatomic, assign) BOOL isReordering;
@property (nonatomic, assign) BOOL moreMenuDropHighlighted;
@property (nonatomic, assign) CGFloat resizeGrabOffsetInWindow;
@property (nonatomic, assign) CGFloat resizeTrailingXInWindow;
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
        _actionButtons = [NSMutableArray array];
        _items = @[];
        _allocatedWidth = 0;
        self.clipsToBounds = YES;

        _resizeHandle = [[BrowserTabStripChromeResizeHandleView alloc] initWithFrame:NSZeroRect];
        _resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
        _resizeHandle.toolTip = @"拖动调整工具栏宽度";
        [self addSubview:_resizeHandle];

        // 裁剪区 + 完整按钮栈：变窄时右侧图标被裁切进 ⋯，无显隐闪动
        _clipView = [[BrowserTabStripChromeActionsClipView alloc] initWithFrame:NSZeroRect];
        _clipView.translatesAutoresizingMaskIntoConstraints = NO;
        _clipView.clipsToBounds = YES;
        [self addSubview:_clipView];

        _stackView = [NSStackView stackViewWithViews:@[]];
        _stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _stackView.spacing = kChromeActionSpacing;
        _stackView.alignment = NSLayoutAttributeCenterY;
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [_clipView addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_resizeHandle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_resizeHandle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_resizeHandle.widthAnchor constraintEqualToConstant:kChromeResizeHandleWidth],
            [_resizeHandle.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],

            [_clipView.leadingAnchor constraintEqualToAnchor:_resizeHandle.trailingAnchor
                                                    constant:kChromeResizeHandleSpacing],
            [_clipView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                     constant:-(kChromeActionSpacing + kChromeActionButtonSize)],
            [_clipView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_clipView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            // 栈只贴 leading，宽度随内容；裁剪区变窄时从右侧切掉图标
            [_stackView.leadingAnchor constraintEqualToAnchor:_clipView.leadingAnchor],
            [_stackView.centerYAnchor constraintEqualToAnchor:_clipView.centerYAnchor],
            [_stackView.heightAnchor constraintEqualToAnchor:_clipView.heightAnchor],

            [self.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],
        ]];

        __weak typeof(self) weakSelf = self;
        _resizeHandle.onDragBegan = ^(NSEvent *event) {
            [weakSelf beginWidthResizeWithEvent:event];
        };
        _resizeHandle.onDragToWindowX = ^(CGFloat windowX) {
            [weakSelf applyWidthToWindowX:windowX];
        };
        _resizeHandle.onDragEnded = ^{
            [weakSelf endWidthResize];
        };

        [self reloadFromLayoutStore];
    }
    return self;
}

#pragma mark - Width math

- (CGFloat)leadingChromeWidth {
    return kChromeResizeHandleWidth + kChromeResizeHandleSpacing;
}

- (CGFloat)widthForCustomButtonCount:(NSInteger)count {
    CGFloat width = [self leadingChromeWidth] + kChromeActionButtonSize; // moreMenu 始终在
    if (count > 0) {
        width += (CGFloat)count * kChromeActionButtonSize + (CGFloat)count * kChromeActionSpacing;
    }
    return width;
}

- (CGFloat)fullContentWidth {
    return [self widthForCustomButtonCount:(NSInteger)MAX(0, (NSInteger)self.actionButtons.count - 1)];
}

- (CGFloat)minimumAllocatedWidth {
    return [self widthForCustomButtonCount:0];
}

- (CGFloat)clampedAllocatedWidth:(CGFloat)width {
    CGFloat minWidth = [self minimumAllocatedWidth];
    CGFloat maxWidth = MAX(minWidth, [self fullContentWidth]);
    return MIN(MAX(width, minWidth), maxWidth);
}

- (CGFloat)preferredWidth {
    if (self.allocatedWidth > 0.5) {
        return self.allocatedWidth;
    }
    return [self fullContentWidth];
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize([self preferredWidth], kChromeActionButtonSize);
}

- (void)notifyPreferredWidthDidChange {
    [self invalidateIntrinsicContentSize];
    if (!self.onPreferredWidthDidChange) {
        return;
    }
    if (self.isResizingWidth) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0;
            ctx.allowsImplicitAnimation = NO;
            self.onPreferredWidthDidChange();
        }];
    } else {
        self.onPreferredWidthDidChange();
    }
}

#pragma mark - Reload

- (void)reloadFromLayoutStore {
    [self reloadWithItems:[[self class] itemsForCurrentLayout]];
}

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items {
    for (NSView *view in [self.stackView.views copy]) {
        [self.stackView removeView:view];
    }
    [self.moreMenuButton removeFromSuperview];
    self.moreMenuButton = nil;
    [self.buttonsByID removeAllObjects];
    [self.actionButtons removeAllObjects];

    self.items = [items copy] ?: @[];
    for (BrowserChromeActionItem *item in self.items) {
        BOOL on = [self.onStateByID[item.itemID] boolValue];
        BrowserTabStripChromeActionButton *button = [self makeButtonForItem:item on:on];
        self.buttonsByID[item.itemID] = button;
        [self.actionButtons addObject:button];
        if ([item.itemID isEqualToString:BrowserChromeActionMoreMenuID]) {
            self.moreMenuButton = button;
            [self addSubview:button];
            [NSLayoutConstraint activateConstraints:@[
                [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [button.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            ]];
        } else {
            [self.stackView addArrangedSubview:button];
        }
    }

    CGFloat full = [self fullContentWidth];
    CGFloat saved = [BrowserChromeActionLayoutStore preferredToolbarWidth];
    if (saved > 0.5) {
        self.allocatedWidth = [self clampedAllocatedWidth:saved];
    } else {
        self.allocatedWidth = full;
    }

    [self notifyPreferredWidthDidChange];
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

#pragma mark - Width resize

- (void)beginWidthResizeWithEvent:(NSEvent *)event {
    self.isResizingWidth = YES;
    // 冻结 trailing 窗口坐标：宽度变化时右缘不动，左缘（拖柄）跟着鼠标
    NSRect frameInWindow = [self convertRect:self.bounds toView:nil];
    self.resizeTrailingXInWindow = NSMaxX(frameInWindow);
    self.resizeGrabOffsetInWindow = event.locationInWindow.x - NSMinX(frameInWindow);
    [self applyWidthToWindowX:event.locationInWindow.x];
}

- (void)endWidthResize {
    self.isResizingWidth = NO;
    self.allocatedWidth = [self clampedAllocatedWidth:self.allocatedWidth];
    [BrowserChromeActionLayoutStore setPreferredToolbarWidth:self.allocatedWidth];
    [self notifyPreferredWidthDidChange];
}

- (void)applyWidthToWindowX:(CGFloat)windowX {
    // leading = mouseX - grabOffset；width = trailing - leading
    CGFloat newLeading = windowX - self.resizeGrabOffsetInWindow;
    CGFloat next = [self clampedAllocatedWidth:self.resizeTrailingXInWindow - newLeading];
    if (fabs(next - self.allocatedWidth) < 0.05) {
        return;
    }
    self.allocatedWidth = next;
    [self notifyPreferredWidthDidChange];
}

#pragma mark - Overflow

- (NSInteger)customButtonCount {
    return MAX(0, (NSInteger)self.actionButtons.count - 1); // 末尾固定 moreMenu
}

- (NSInteger)visibleCustomCountForWidth:(CGFloat)groupWidth {
    NSInteger customTotal = [self customButtonCount];
    if (customTotal <= 0) {
        return 0;
    }
    CGFloat full = [self widthForCustomButtonCount:customTotal];
    if (groupWidth >= full - 0.5) {
        return customTotal;
    }
    NSInteger best = 0;
    for (NSInteger n = 0; n <= customTotal; n++) {
        if ([self widthForCustomButtonCount:n] <= groupWidth + 0.5) {
            best = n;
        } else {
            break;
        }
    }
    return MAX(0, MIN(best, customTotal));
}

- (BOOL)isCustomButtonVisibleOnStrip:(BrowserTabStripChromeActionButton *)button {
    if (!button || button.hidden || !self.clipView) {
        return NO;
    }
    NSRect buttonInClip = [button convertRect:button.bounds toView:self.clipView];
    // 按钮右缘仍在裁剪区内才算可见（可点）
    return NSMaxX(buttonInClip) <= NSWidth(self.clipView.bounds) + 0.5;
}

- (NSArray<NSString *> *)widthOverflowedActionIDs {
    NSInteger visible = [self visibleCustomCountForWidth:self.allocatedWidth];
    NSInteger customTotal = [self customButtonCount];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSInteger i = visible; i < customTotal; i++) {
        NSString *itemID = self.actionButtons[i].itemID;
        if (itemID.length > 0) {
            [ids addObject:itemID];
        }
    }
    return [ids copy];
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

- (NSInteger)indexOfCustomButton:(BrowserTabStripChromeActionButton *)button {
    NSInteger customCount = [self customButtonCount];
    for (NSInteger i = 0; i < customCount; i++) {
        if (self.actionButtons[i] == button) {
            return i;
        }
    }
    return NSNotFound;
}

- (BOOL)isWindowPointOverMoreMenu:(NSPoint)windowPoint {
    NSButton *more = [self buttonForItemID:BrowserChromeActionMoreMenuID];
    if (!more || more.hidden) {
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
    NSInteger bestIndex = currentIndex;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger i = 0; i < customCount; i++) {
        BrowserTabStripChromeActionButton *candidate = self.actionButtons[i];
        if (![self isCustomButtonVisibleOnStrip:candidate]) {
            continue;
        }
        CGFloat midX = NSMidX(candidate.frame);
        CGFloat distance = fabs(point.x - midX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
        }
    }
    return bestIndex;
}

- (void)rebuildStackFromActionButtons {
    for (NSView *view in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (BrowserTabStripChromeActionButton *button in self.actionButtons) {
        if ([button.itemID isEqualToString:BrowserChromeActionMoreMenuID]) {
            continue;
        }
        [self.stackView addArrangedSubview:button];
    }

    NSMutableArray<BrowserChromeActionItem *> *newItems = [NSMutableArray array];
    for (BrowserTabStripChromeActionButton *button in self.actionButtons) {
        if (button.actionItem) {
            [newItems addObject:button.actionItem];
        }
    }
    self.items = [newItems copy];
}

- (void)swapCustomButtonAtIndex:(NSInteger)indexA withIndex:(NSInteger)indexB {
    NSInteger customCount = [self customButtonCount];
    if (indexA == indexB ||
        indexA < 0 || indexB < 0 ||
        indexA >= customCount || indexB >= customCount) {
        return;
    }
    if (![self isCustomButtonVisibleOnStrip:self.actionButtons[indexA]] ||
        ![self isCustomButtonVisibleOnStrip:self.actionButtons[indexB]]) {
        return;
    }

    [self.actionButtons exchangeObjectAtIndex:(NSUInteger)indexA withObjectAtIndex:(NSUInteger)indexB];
    [self rebuildStackFromActionButtons];
}

- (NSArray<NSString *> *)orderedCustomActionIDsFromButtons {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSInteger customCount = [self customButtonCount];
    for (NSInteger i = 0; i < customCount; i++) {
        NSString *itemID = self.actionButtons[i].itemID;
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
    if (self.isResizingWidth || !self.window) {
        return;
    }
    // 被宽度裁掉的图标不参与条上点击/改序（应从 ⋯ 菜单操作）
    if (![self isCustomButtonVisibleOnStrip:button]) {
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

    NSArray<NSString *> *visibleIDs = [self orderedCustomActionIDsFromButtons];
    NSArray<NSString *> *merged =
        [BrowserChromeActionLayoutStore orderedIDsByReplacingVisibleSubsequence:visibleIDs];
    [BrowserChromeActionLayoutStore setOrderedCustomActionIDs:merged];
}

@end
