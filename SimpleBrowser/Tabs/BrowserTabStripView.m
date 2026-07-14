#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"

const CGFloat BrowserTabStripHeight = 36.0;

static const CGFloat kTrafficLightLeadingInset = 78.0;
static const CGFloat kTabTopInset = 3.0;
static const CGFloat kTrailingDragWidth = 16.0;
static const CGFloat kTabSpacing = 2.0;
static const CGFloat kOverflowButtonWidth = 22.0;
static const CGFloat kAddButtonWidth = 24.0;
static const CGFloat kAddButtonHeight = 24.0;
static const CGFloat kChromeGap = 4.0;

@class BrowserTabStripView;

@interface BrowserTabStripView (TitleBarInteraction)
- (void)handleTitleBarDoubleClick;
@end

@interface BrowserTabStripDragAreaView : NSView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripDragAreaView

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

@end

@interface BrowserTabStripClipView : NSView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripClipView

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

@end

@interface BrowserTabStripView () <NSMenuItemValidation>
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *leadingDragArea;
@property (nonatomic, strong) NSView *trailingDragArea;
@property (nonatomic, strong) BrowserTabStripClipView *tabsClipView;
@property (nonatomic, strong) NSView *tabsContentView;
@property (nonatomic, strong) NSButton *overflowButton;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSMutableArray<BrowserTabItemView *> *tabItems;
@property (nonatomic, strong) NSMapTable<BrowserTabItemView *, NSUUID *> *tabItemIDs;
@property (nonatomic, strong) NSMapTable<NSUUID *, BrowserTabItemView *> *tabItemsByID;
@property (nonatomic, strong, nullable) NSUUID *selectedTabID;
@property (nonatomic, strong) NSMutableArray<NSUUID *> *overflowTabIDs;
@property (nonatomic, assign) CGFloat lastLaidOutTabWidth;
@property (nonatomic, assign) CGFloat lastLaidOutAvailableWidth;
@property (nonatomic, assign) NSUInteger lastLaidOutTabCount;
@property (nonatomic, assign) NSUInteger lastVisibleStart;
@property (nonatomic, assign) NSUInteger lastVisibleCount;
@property (nonatomic, assign) BOOL lastOverflowVisible;
@property (nonatomic, assign) NSUInteger lastPinnedCount;
@property (nonatomic, weak, nullable) BrowserTabItemView *draggingItem;
@property (nonatomic, assign) NSUInteger draggingFromIndex;
@property (nonatomic, assign) NSUInteger draggingPreviewIndex;
@property (nonatomic, assign) NSRect draggingOriginalFrame;
@property (nonatomic, assign) BOOL suppressLayoutDuringDrag;
@end

@implementation BrowserTabStripView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;

        _tabItems = [NSMutableArray array];
        _tabItemIDs = [NSMapTable weakToStrongObjectsMapTable];
        _tabItemsByID = [NSMapTable strongToWeakObjectsMapTable];
        _overflowTabIDs = [NSMutableArray array];
        _lastLaidOutTabWidth = -1;
        _lastLaidOutAvailableWidth = -1;
        _lastLaidOutTabCount = NSNotFound;
        _lastVisibleStart = NSNotFound;
        _lastVisibleCount = NSNotFound;
        _lastOverflowVisible = NO;
        _lastPinnedCount = NSNotFound;
        _draggingFromIndex = NSNotFound;
        _draggingPreviewIndex = NSNotFound;

        _backgroundView = [[BrowserTabStripDragAreaView alloc] init];
        _backgroundView.wantsLayer = YES;
        _backgroundView.translatesAutoresizingMaskIntoConstraints = NO;

        _leadingDragArea = [[BrowserTabStripDragAreaView alloc] init];
        _leadingDragArea.translatesAutoresizingMaskIntoConstraints = NO;

        _tabsClipView = [[BrowserTabStripClipView alloc] initWithFrame:NSZeroRect];
        _tabsClipView.translatesAutoresizingMaskIntoConstraints = NO;
        _tabsClipView.wantsLayer = YES;
        _tabsClipView.layer.masksToBounds = YES;
        [_tabsClipView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_tabsClipView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];

        _tabsContentView = [[BrowserTabStripDragAreaView alloc] initWithFrame:NSZeroRect];
        ((BrowserTabStripDragAreaView *)_tabsContentView).stripView = self;
        [_tabsClipView addSubview:_tabsContentView];

        // 「+」/溢出箭头用 frame 贴在末标签旁，不参与 AL 链，避免定宽抬高窗口 minSize
        _overflowButton = [self makeOverflowButton];
        _overflowButton.translatesAutoresizingMaskIntoConstraints = YES;
        _overflowButton.autoresizingMask = NSViewNotSizable;

        _addTabButton = [self newTabButton];
        _addTabButton.translatesAutoresizingMaskIntoConstraints = YES;
        _addTabButton.autoresizingMask = NSViewNotSizable;

        _trailingDragArea = [[BrowserTabStripDragAreaView alloc] init];
        _trailingDragArea.translatesAutoresizingMaskIntoConstraints = NO;
        [_trailingDragArea setContentHuggingPriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_trailingDragArea setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self addSubview:_backgroundView];
        [self addSubview:_leadingDragArea];
        [self addSubview:_tabsClipView];
        [self addSubview:_trailingDragArea];
        // 叠在 clip 之上，保证按钮可点；clip 弹性铺满中间，窗口可自由拖窄
        [self addSubview:_overflowButton];
        [self addSubview:_addTabButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],

            [_backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_leadingDragArea.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_leadingDragArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_leadingDragArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_leadingDragArea.widthAnchor constraintEqualToConstant:kTrafficLightLeadingInset],

            [_tabsClipView.leadingAnchor constraintEqualToAnchor:_leadingDragArea.trailingAnchor constant:kChromeGap],
            [_tabsClipView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_tabsClipView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_tabsClipView.trailingAnchor constraintEqualToAnchor:_trailingDragArea.leadingAnchor],

            [_trailingDragArea.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_trailingDragArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_trailingDragArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_trailingDragArea.widthAnchor constraintEqualToConstant:kTrailingDragWidth],
        ]];

        ((BrowserTabStripDragAreaView *)_backgroundView).stripView = self;
        ((BrowserTabStripDragAreaView *)_leadingDragArea).stripView = self;
        ((BrowserTabStripDragAreaView *)_trailingDragArea).stripView = self;
        ((BrowserTabStripDragAreaView *)_tabsContentView).stripView = self;
        _tabsClipView.stripView = self;

        _overflowButton.hidden = YES;
        [self updateStripAppearance];
    }
    return self;
}

- (NSButton *)makeOverflowButton {
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:11
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"chevron.down"
                                    accessibilityDescription:@"更多标签页"];
        if (symbol) {
            image = [symbol imageWithSymbolConfiguration:config];
        }
    }

    NSButton *button = image ? [NSButton buttonWithImage:image target:self action:@selector(showOverflowMenu:)]
                             : [NSButton buttonWithTitle:@"▾" target:self action:@selector(showOverflowMenu:)];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"其余标签页";
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    return button;
}

- (void)handleTitleBarDoubleClick {
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripViewDidDoubleClickTitleBar:)]) {
        [delegate tabStripViewDidDoubleClickTitleBar:self];
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateStripAppearance];
}

- (void)updateStripAppearance {
    BOOL dark = [self effectiveAppearanceIsDark];
    NSColor *strip = dark ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
                          : [NSColor colorWithCalibratedRed:0.87 green:0.88 blue:0.91 alpha:1.0];
    self.backgroundView.layer.backgroundColor = strip.CGColor;
}

- (BOOL)effectiveAppearanceIsDark {
    NSString *name = self.effectiveAppearance.name;
    return [name containsString:@"Dark"];
}

- (NSButton *)newTabButton {
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:14
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"新建标签页"];
        if (symbol) {
            image = [symbol imageWithSymbolConfiguration:config];
        }
    }

    NSButton *button = image ? [NSButton buttonWithImage:image target:self action:@selector(onNewTab:)]
                             : [NSButton buttonWithTitle:@"+" target:self action:@selector(onNewTab:)];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"新建标签页";
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    return button;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

- (void)layout {
    [super layout];
    if (!self.suppressLayoutDuringDrag) {
        [self updateTabFrames];
    }
}

- (NSUInteger)indexOfSelectedTab {
    if (!self.selectedTabID) {
        return NSNotFound;
    }
    for (NSUInteger i = 0; i < self.tabItems.count; i++) {
        NSUUID *tabID = [self.tabItemIDs objectForKey:self.tabItems[i]];
        if ([tabID isEqual:self.selectedTabID]) {
            return i;
        }
    }
    return NSNotFound;
}

- (NSUInteger)pinnedTabCountInStrip {
    NSUInteger count = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        if (!item.tabPinned) {
            break;
        }
        count++;
    }
    return count;
}

- (CGFloat)widthNeededForRangeStart:(NSUInteger)start length:(NSUInteger)length {
    if (length == 0) {
        return 0;
    }
    CGFloat width = 0;
    NSUInteger unpinned = 0;
    for (NSUInteger i = start; i < start + length && i < self.tabItems.count; i++) {
        if (self.tabItems[i].tabPinned) {
            width += BrowserTabPinnedWidth;
        } else {
            unpinned++;
            width += BrowserTabItemMinWidth;
        }
    }
    if (length > 1) {
        width += (length - 1) * kTabSpacing;
    }
    (void)unpinned;
    return width;
}

/// 在总宽 fullWidth 下最多能完整放下几个标签（可预留 overflow 按钮）
- (NSUInteger)maxVisibleTabCountForWidth:(CGFloat)fullWidth {
    if (fullWidth < 1.0 || self.tabItems.count == 0) {
        return 0;
    }

    NSUInteger total = self.tabItems.count;
    CGFloat allWidth = [self widthNeededForRangeStart:0 length:total];
    if (allWidth <= fullWidth + 0.5) {
        return total;
    }

    CGFloat tabsWidth = fullWidth - kOverflowButtonWidth - 2.0;
    if (tabsWidth < BrowserTabPinnedWidth && tabsWidth < BrowserTabItemMinWidth) {
        return 1;
    }

    for (NSUInteger count = total - 1; count >= 1; count--) {
        NSUInteger start = 0;
        NSUInteger len = 0;
        [self visibleRangeForCount:count start:&start count:&len];
        CGFloat needed = [self widthNeededForRangeStart:start length:len];
        if (needed <= tabsWidth + 0.5) {
            return count;
        }
        if (count == 1) {
            break;
        }
    }
    return 1;
}

- (void)visibleRangeForCount:(NSUInteger)visibleCount
                       start:(NSUInteger *)outStart
                       count:(NSUInteger *)outCount {
    NSUInteger total = self.tabItems.count;
    if (visibleCount >= total) {
        *outStart = 0;
        *outCount = total;
        return;
    }

    NSUInteger selected = [self indexOfSelectedTab];
    if (selected == NSNotFound) {
        selected = 0;
    }

    // 可见窗口始终包含选中标签，尽量靠左
    NSInteger start = (NSInteger)selected - (NSInteger)visibleCount + 1;
    if (start < 0) {
        start = 0;
    }
    if ((NSUInteger)start + visibleCount > total) {
        start = (NSInteger)total - (NSInteger)visibleCount;
    }
    *outStart = (NSUInteger)start;
    *outCount = visibleCount;
}

- (void)setOverflowVisible:(BOOL)visible {
    self.overflowButton.hidden = !visible;
}

/// 将 ▾ / + 贴到末个可见标签右侧（坐标相对标签条）
- (void)placeChromeButtonsAfterContentWidth:(CGFloat)contentW needsOverflow:(BOOL)needsOverflow {
    CGFloat clipLeading = kTrafficLightLeadingInset + kChromeGap;
    CGFloat buttonY = floor((BrowserTabStripHeight - kAddButtonHeight) * 0.5);
    CGFloat cursor = clipLeading + MAX(contentW, 0);

    if (needsOverflow) {
        cursor += 2.0;
        self.overflowButton.frame = NSMakeRect(cursor, buttonY, kOverflowButtonWidth, kAddButtonHeight);
        cursor = NSMaxX(self.overflowButton.frame) + kChromeGap;
    } else {
        self.overflowButton.frame = NSZeroRect;
        cursor += 2.0;
    }

    // 不要紧贴右缘越界：预留 trailing 拖拽带
    CGFloat maxAddX = NSWidth(self.bounds) - kTrailingDragWidth - kAddButtonWidth;
    if (cursor > maxAddX) {
        cursor = MAX(clipLeading, maxAddX);
    }
    self.addTabButton.frame = NSMakeRect(cursor, buttonY, kAddButtonWidth, kAddButtonHeight);
}

- (void)invalidateTabLayoutCache {
    self.lastLaidOutTabWidth = -1;
    self.lastLaidOutAvailableWidth = -1;
    self.lastLaidOutTabCount = NSNotFound;
    self.lastVisibleStart = NSNotFound;
    self.lastVisibleCount = NSNotFound;
    self.lastPinnedCount = NSNotFound;
}

- (void)updateTabFrames {
    NSUInteger total = self.tabItems.count;
    // 为「+」预留占位后，中间可供「标签 + 可选箭头」的宽度
    // leading(78)+4 + middle + 4 + add(24) + trailing(16) = bounds.width
    CGFloat reservedChrome = kTrafficLightLeadingInset + kChromeGap + kChromeGap + kAddButtonWidth + kTrailingDragWidth;
    CGFloat stripMiddle = NSWidth(self.bounds) - reservedChrome;

    if (total == 0 || stripMiddle < 1.0) {
        [self setOverflowVisible:NO];
        self.tabsContentView.frame = NSMakeRect(0, 0, 1, BrowserTabStripHeight);
        [self.overflowTabIDs removeAllObjects];
        [self placeChromeButtonsAfterContentWidth:0 needsOverflow:NO];
        return;
    }

    NSUInteger visibleCount = [self maxVisibleTabCountForWidth:stripMiddle];
    BOOL needsOverflow = visibleCount < total;
    [self setOverflowVisible:needsOverflow];

    CGFloat available = needsOverflow
        ? MAX(stripMiddle - kOverflowButtonWidth - 2.0, BrowserTabPinnedWidth)
        : stripMiddle;

    NSUInteger visibleStart = 0;
    NSUInteger visibleLen = 0;
    [self visibleRangeForCount:visibleCount start:&visibleStart count:&visibleLen];

    NSUInteger pinnedCount = [self pinnedTabCountInStrip];
    NSUInteger visiblePinned = 0;
    NSUInteger visibleUnpinned = 0;
    for (NSUInteger i = visibleStart; i < visibleStart + visibleLen; i++) {
        if (self.tabItems[i].tabPinned) {
            visiblePinned++;
        } else {
            visibleUnpinned++;
        }
    }

    CGFloat spacingTotal = (visibleLen > 1) ? (visibleLen - 1) * kTabSpacing : 0;
    CGFloat pinnedSpace = visiblePinned * BrowserTabPinnedWidth;
    CGFloat unpinnedAvailable = MAX(available - pinnedSpace - spacingTotal, 0);
    CGFloat unpinnedWidth = BrowserTabItemMinWidth;
    if (visibleUnpinned > 0) {
        CGFloat ideal = unpinnedAvailable / (CGFloat)visibleUnpinned;
        unpinnedWidth = MIN(BrowserTabItemMaxWidth, MAX(BrowserTabItemMinWidth, ideal));
    }

    CGFloat contentW = pinnedSpace + visibleUnpinned * unpinnedWidth + spacingTotal;
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;

    BOOL geometryChanged = fabs(unpinnedWidth - self.lastLaidOutTabWidth) > 0.5
        || fabs(available - self.lastLaidOutAvailableWidth) > 0.5
        || total != self.lastLaidOutTabCount
        || visibleStart != self.lastVisibleStart
        || visibleLen != self.lastVisibleCount
        || needsOverflow != self.lastOverflowVisible
        || pinnedCount != self.lastPinnedCount
        || self.draggingItem != nil;

    if (geometryChanged) {
        [self.overflowTabIDs removeAllObjects];
        CGFloat x = 0;
        for (NSUInteger i = 0; i < total; i++) {
            BrowserTabItemView *item = self.tabItems[i];
            BOOL visible = (i >= visibleStart && i < visibleStart + visibleLen);
            CGFloat tabWidth = item.tabPinned ? BrowserTabPinnedWidth : unpinnedWidth;

            if (item == self.draggingItem) {
                // 拖拽中的标签保留纵向布局，横向由拖拽逻辑更新
                item.hidden = NO;
                NSRect frame = item.frame;
                frame.origin.y = 0;
                frame.size.width = tabWidth;
                frame.size.height = tabHeight;
                item.frame = frame;
                [item applyAvailableWidth:tabWidth];
                x += tabWidth + kTabSpacing;
                continue;
            }

            item.hidden = !visible;
            if (visible) {
                item.frame = NSMakeRect(x, 0, tabWidth, tabHeight);
                [item applyAvailableWidth:tabWidth];
                x += tabWidth + kTabSpacing;
            } else {
                item.frame = NSZeroRect;
                NSUUID *tabID = [self.tabItemIDs objectForKey:item];
                if (tabID) {
                    [self.overflowTabIDs addObject:tabID];
                }
            }
        }

        self.tabsContentView.frame = NSMakeRect(0, 0, MAX(contentW, 1), BrowserTabStripHeight);
        self.lastLaidOutTabWidth = unpinnedWidth;
        self.lastLaidOutAvailableWidth = available;
        self.lastLaidOutTabCount = total;
        self.lastVisibleStart = visibleStart;
        self.lastVisibleCount = visibleLen;
        self.lastOverflowVisible = needsOverflow;
        self.lastPinnedCount = pinnedCount;
    }

    // 每次 layout 都重摆「+」，跟随末标签；不依赖 AL 定宽
    [self placeChromeButtonsAfterContentWidth:contentW needsOverflow:needsOverflow];
}

- (void)showOverflowMenu:(id)sender {
    (void)sender;
    if (self.overflowTabIDs.count == 0) {
        return;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"其余标签页"];
    menu.autoenablesItems = NO;

    for (NSUUID *tabID in self.overflowTabIDs) {
        BrowserTabItemView *itemView = [self.tabItemsByID objectForKey:tabID];
        NSString *baseTitle = itemView.tabTitle.length > 0 ? itemView.tabTitle : @"新标签页";
        NSString *title = itemView.tabPinned ? [NSString stringWithFormat:@"固定 · %@", baseTitle] : baseTitle;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectOverflowTab:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = tabID;
        item.enabled = YES;
        if ([tabID isEqual:self.selectedTabID]) {
            item.state = NSControlStateValueOn;
        }
        [menu addItem:item];
    }

    NSRect bounds = self.overflowButton.bounds;
    NSPoint point = NSMakePoint(NSMinX(bounds), NSMaxY(bounds) + 2.0);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:self.overflowButton];
}

- (void)selectOverflowTab:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    [self.delegate tabStripView:self didSelectTabID:tabID];
}

#pragma mark - Tab Reorder Drag

- (void)beginReorderDragForItem:(BrowserTabItemView *)item {
    NSUInteger index = [self.tabItems indexOfObject:item];
    if (index == NSNotFound) {
        return;
    }
    self.draggingItem = item;
    self.draggingFromIndex = index;
    self.draggingPreviewIndex = index;
    self.draggingOriginalFrame = item.frame;
    self.suppressLayoutDuringDrag = YES;
    [self.tabsContentView addSubview:item positioned:NSWindowAbove relativeTo:nil];
}

- (void)moveReorderDragForItem:(BrowserTabItemView *)item deltaX:(CGFloat)deltaX {
    if (item != self.draggingItem) {
        return;
    }

    NSRect frame = self.draggingOriginalFrame;
    frame.origin.x += deltaX;
    // 限制在内容区内
    CGFloat minX = 0;
    CGFloat maxX = MAX(NSWidth(self.tabsContentView.bounds) - NSWidth(frame), 0);
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    item.frame = frame;

    CGFloat centerX = NSMidX(frame);
    NSUInteger target = [self insertionIndexForDraggedItem:item centerX:centerX];
    if (target == self.draggingPreviewIndex || target == NSNotFound) {
        return;
    }

    NSUInteger current = [self.tabItems indexOfObject:item];
    if (current == NSNotFound || current == target) {
        self.draggingPreviewIndex = target;
        return;
    }

    [self.tabItems removeObjectAtIndex:current];
    NSUInteger insertAt = target;
    if (target > current) {
        // target 是最终下标；remove 后 insertAt == target 即可（见 BrowserTabController）
        insertAt = MIN(target, self.tabItems.count);
    } else {
        insertAt = target;
    }
    insertAt = MIN(insertAt, self.tabItems.count);
    [self.tabItems insertObject:item atIndex:insertAt];
    self.draggingPreviewIndex = insertAt;

    [self layoutTabsExcludingDraggedItem:item];
}

- (NSUInteger)insertionIndexForDraggedItem:(BrowserTabItemView *)item centerX:(CGFloat)centerX {
    NSUInteger pinnedCount = [self pinnedTabCountInStrip];
    // 拖拽时 item 可能暂时不在「固定前缀」语义位置，用原始 pin 状态限制区间
    BOOL pinned = item.tabPinned;
    NSUInteger low = pinned ? 0 : pinnedCount;
    NSUInteger high = pinned ? pinnedCount : self.tabItems.count;
    // pinnedCount 在拖拽重排过程中仍应等于固定标签个数
    NSUInteger actualPinned = 0;
    for (BrowserTabItemView *candidate in self.tabItems) {
        if (candidate.tabPinned) {
            actualPinned++;
        }
    }
    low = pinned ? 0 : actualPinned;
    high = pinned ? actualPinned : self.tabItems.count;
    if (low >= high) {
        return low < self.tabItems.count ? low : NSNotFound;
    }

    NSUInteger best = low;
    CGFloat bestDistance = CGFLOAT_MAX;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < self.tabItems.count; i++) {
        BrowserTabItemView *candidate = self.tabItems[i];
        CGFloat width = candidate.tabPinned ? BrowserTabPinnedWidth : MAX(NSWidth(candidate.frame), BrowserTabItemMinWidth);
        if (candidate == item) {
            width = MAX(NSWidth(item.frame), candidate.tabPinned ? BrowserTabPinnedWidth : BrowserTabItemMinWidth);
        }
        if (i >= low && i < high) {
            CGFloat slotCenter = x + width * 0.5;
            CGFloat distance = fabs(slotCenter - centerX);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
            }
        }
        x += width + kTabSpacing;
    }
    return best;
}

- (void)layoutTabsExcludingDraggedItem:(BrowserTabItemView *)dragged {
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;
    CGFloat unpinnedWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    CGFloat x = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        CGFloat tabWidth = item.tabPinned ? BrowserTabPinnedWidth : unpinnedWidth;
        if (item == dragged) {
            x += tabWidth + kTabSpacing;
            continue;
        }
        if (!item.hidden) {
            item.frame = NSMakeRect(x, 0, tabWidth, tabHeight);
            [item applyAvailableWidth:tabWidth];
        }
        x += tabWidth + kTabSpacing;
    }
}

- (void)endReorderDragForItem:(BrowserTabItemView *)item {
    if (item != self.draggingItem) {
        return;
    }

    NSUInteger toIndex = [self.tabItems indexOfObject:item];
    NSUInteger fromIndex = self.draggingFromIndex;
    NSUUID *tabID = [self.tabItemIDs objectForKey:item];

    self.draggingItem = nil;
    self.draggingFromIndex = NSNotFound;
    self.draggingPreviewIndex = NSNotFound;
    self.suppressLayoutDuringDrag = NO;
    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];

    if (tabID && toIndex != NSNotFound && toIndex != fromIndex) {
        // 推迟到下一个 runloop，避免在 mouseUp 栈内 reload 标签条
        NSUUID *movedID = tabID;
        NSUInteger movedTo = toIndex;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            id<BrowserTabStripViewDelegate> delegate = strongSelf.delegate;
            if ([delegate respondsToSelector:@selector(tabStripView:didMoveTabID:toIndex:)]) {
                [delegate tabStripView:strongSelf didMoveTabID:movedID toIndex:movedTo];
            }
        });
    }
}

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    if (self.draggingItem) {
        self.draggingItem = nil;
        self.suppressLayoutDuringDrag = NO;
    }

    for (BrowserTabItemView *item in self.tabItems) {
        [item removeFromSuperview];
    }
    [self.tabItems removeAllObjects];
    [self.tabItemIDs removeAllObjects];
    [self.tabItemsByID removeAllObjects];
    [self.overflowTabIDs removeAllObjects];
    [self invalidateTabLayoutCache];
    self.selectedTabID = selectedTabID;

    for (BrowserTab *tab in tabs) {
        BOOL selected = [tab.tabID isEqual:selectedTabID];
        BrowserTabItemView *item = [[BrowserTabItemView alloc] initWithFrame:NSZeroRect];
        item.translatesAutoresizingMaskIntoConstraints = YES;
        item.autoresizingMask = NSViewNotSizable;
        item.tabTitle = [tab displayTitle];
        item.tabPinned = tab.isPinned;
        item.tabSelected = selected;

        __weak typeof(self) weakSelf = self;
        __weak BrowserTabItemView *weakItem = item;
        NSUUID *tabID = tab.tabID;
        item.onSelect = ^{
            [weakSelf.delegate tabStripView:weakSelf didSelectTabID:tabID];
        };
        item.onClose = ^{
            [weakSelf.delegate tabStripView:weakSelf didCloseTabID:tabID];
        };
        item.onCloseTabsToTheRight = ^{
            id<BrowserTabStripViewDelegate> delegate = weakSelf.delegate;
            if ([delegate respondsToSelector:@selector(tabStripView:didCloseTabsToTheRightOfTabID:)]) {
                [delegate tabStripView:weakSelf didCloseTabsToTheRightOfTabID:tabID];
            }
        };
        item.contextMenuProvider = ^{
            return [weakSelf contextMenuForTabID:tabID];
        };
        item.onReorderDragBegan = ^{
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf beginReorderDragForItem:strongItem];
            }
        };
        item.onReorderDragMoved = ^(CGFloat deltaX) {
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf moveReorderDragForItem:strongItem deltaX:deltaX];
            }
        };
        item.onReorderDragEnded = ^{
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf endReorderDragForItem:strongItem];
            }
        };

        [self.tabItemIDs setObject:tab.tabID forKey:item];
        [self.tabItemsByID setObject:item forKey:tab.tabID];
        [self.tabItems addObject:item];
        [self.tabsContentView addSubview:item];
    }

    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];
}

#pragma mark - Tab Context Menu

- (NSMenu *)contextMenuForTabID:(NSUUID *)tabID {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"标签页"];

    BOOL pinned = NO;
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripView:isTabPinnedForTabID:)]) {
        pinned = [delegate tabStripView:self isTabPinnedForTabID:tabID];
    } else {
        BrowserTabItemView *item = [self.tabItemsByID objectForKey:tabID];
        pinned = item.tabPinned;
    }

    NSString *pinTitle = pinned ? @"取消固定标签页" : @"固定标签页";
    NSMenuItem *pinItem = [menu addItemWithTitle:pinTitle
                                          action:@selector(contextTogglePinTab:)
                                   keyEquivalent:@""];
    pinItem.target = self;
    pinItem.representedObject = tabID;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *closeItem = [menu addItemWithTitle:@"关闭标签页"
                                            action:@selector(contextCloseTab:)
                                     keyEquivalent:@""];
    closeItem.target = self;
    closeItem.representedObject = tabID;

    NSMenuItem *closeOthers = [menu addItemWithTitle:@"关闭其他标签页"
                                              action:@selector(contextCloseOtherTabs:)
                                       keyEquivalent:@""];
    closeOthers.target = self;
    closeOthers.representedObject = tabID;

    NSMenuItem *closeRight = [menu addItemWithTitle:@"关闭右侧标签页"
                                             action:@selector(contextCloseTabsToTheRight:)
                                      keyEquivalent:@""];
    closeRight.target = self;
    closeRight.representedObject = tabID;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *restoreItem = [menu addItemWithTitle:@"恢复最近关闭的标签页"
                                              action:@selector(contextRestoreRecentlyClosedTab:)
                                       keyEquivalent:@""];
    restoreItem.target = self;

    return menu;
}

- (void)contextTogglePinTab:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }

    BOOL pinned = NO;
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripView:isTabPinnedForTabID:)]) {
        pinned = [delegate tabStripView:self isTabPinnedForTabID:tabID];
    } else {
        BrowserTabItemView *item = [self.tabItemsByID objectForKey:tabID];
        pinned = item.tabPinned;
    }

    if ([delegate respondsToSelector:@selector(tabStripView:didSetPinned:forTabID:)]) {
        [delegate tabStripView:self didSetPinned:!pinned forTabID:tabID];
    }
}

- (void)contextCloseTab:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    [self.delegate tabStripView:self didCloseTabID:tabID];
}

- (void)contextCloseOtherTabs:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripView:didCloseOtherTabsExceptTabID:)]) {
        [delegate tabStripView:self didCloseOtherTabsExceptTabID:tabID];
    }
}

- (void)contextCloseTabsToTheRight:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripView:didCloseTabsToTheRightOfTabID:)]) {
        [delegate tabStripView:self didCloseTabsToTheRightOfTabID:tabID];
    }
}

- (void)contextRestoreRecentlyClosedTab:(NSMenuItem *)sender {
    (void)sender;
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripViewDidRequestRestoreRecentlyClosedTab:)]) {
        [delegate tabStripViewDidRequestRestoreRecentlyClosedTab:self];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    NSUUID *tabID = menuItem.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        tabID = nil;
    }

    if (action == @selector(contextTogglePinTab:)) {
        return tabID != nil;
    }

    if (action == @selector(contextCloseOtherTabs:)) {
        if (!tabID) {
            return NO;
        }
        if ([delegate respondsToSelector:@selector(tabStripView:canCloseOtherTabsExceptTabID:)]) {
            return [delegate tabStripView:self canCloseOtherTabsExceptTabID:tabID];
        }
        return self.tabItems.count > 1;
    }

    if (action == @selector(contextCloseTabsToTheRight:)) {
        if (!tabID) {
            return NO;
        }
        if ([delegate respondsToSelector:@selector(tabStripView:canCloseTabsToTheRightOfTabID:)]) {
            return [delegate tabStripView:self canCloseTabsToTheRightOfTabID:tabID];
        }
        BrowserTabItemView *item = [self.tabItemsByID objectForKey:tabID];
        NSUInteger index = item ? [self.tabItems indexOfObject:item] : NSNotFound;
        return index != NSNotFound && index + 1 < self.tabItems.count;
    }

    if (action == @selector(contextRestoreRecentlyClosedTab:)) {
        if ([delegate respondsToSelector:@selector(tabStripViewCanRestoreRecentlyClosedTab:)]) {
            return [delegate tabStripViewCanRestoreRecentlyClosedTab:self];
        }
        return NO;
    }

    return YES;
}

- (void)syncWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    if (self.draggingItem) {
        return;
    }

    if (self.tabItems.count != tabs.count) {
        [self reloadWithTabs:tabs selectedTabID:selectedTabID];
        return;
    }

    BOOL selectionChanged = (self.selectedTabID != selectedTabID)
        && ![self.selectedTabID isEqual:selectedTabID];
    BOOL pinOrOrderChanged = NO;
    self.selectedTabID = selectedTabID;

    for (NSUInteger i = 0; i < tabs.count; i++) {
        BrowserTab *tab = tabs[i];
        BrowserTabItemView *item = [self.tabItemsByID objectForKey:tab.tabID];
        if (!item || self.tabItems[i] != item) {
            [self reloadWithTabs:tabs selectedTabID:selectedTabID];
            return;
        }

        NSString *title = [tab displayTitle];
        if (![item.tabTitle isEqualToString:title]) {
            item.tabTitle = title;
        }

        if (item.tabPinned != tab.isPinned) {
            item.tabPinned = tab.isPinned;
            pinOrOrderChanged = YES;
        }

        BOOL selected = [tab.tabID isEqual:selectedTabID];
        if (item.tabSelected != selected) {
            item.tabSelected = selected;
        }
    }

    if (selectionChanged || pinOrOrderChanged) {
        // 选中/固定变化可能改变可见窗口与宽度分配
        [self invalidateTabLayoutCache];
        [self setNeedsLayout:YES];
    }
}

- (void)onNewTab:(id)sender {
    (void)sender;
    [self.delegate tabStripViewDidRequestNewTab:self];
}

@end
