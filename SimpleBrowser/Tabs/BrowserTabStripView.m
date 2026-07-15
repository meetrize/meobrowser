#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"
#import "BrowserTabDragGhostController.h"
#import "BrowserTabDropPlaceholderView.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"

const CGFloat BrowserTabStripHeight = 36.0;

static const CGFloat kTrafficLightLeadingInset = 78.0;
/// 标签顶部与条上缘间距（比早期 3pt 略大）
static const CGFloat kTabTopInset = 5.0;
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

/// 空白区可拖窗（交通灯旁 / 尾部）
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

/// 标签区域：禁止标题栏默认拖窗，否则 FullSizeContentView 下会抢走标签拖拽
@interface BrowserTabStripClipView : NSView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripClipView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    // 点在标签空隙时显式拖窗（不用 mouseDownCanMoveWindow，避免抢子视图）
    if (self.window) {
        [self.window performWindowDragWithEvent:event];
    }
}

@end

/// 承载标签项：命中区向上扩到条顶，覆盖标题与顶部留白
@interface BrowserTabStripTabsContainerView : NSView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripTabsContainerView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (BOOL)isOpaque {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) {
        return nil;
    }
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (![self mouse:local inRect:self.bounds]) {
        return nil;
    }

    // 倒序优先上层（拖拽中抬起的标签）
    for (NSView *subview in [self.subviews reverseObjectEnumerator]) {
        if (subview.hidden || ![subview isKindOfClass:[BrowserTabItemView class]]) {
            continue;
        }
        BrowserTabItemView *item = (BrowserTabItemView *)subview;
        NSRect hitRect = item.frame;
        // 非翻转坐标：向上扩到容器顶，盖住顶部 inset
        CGFloat maxY = NSMaxY(self.bounds);
        if (NSMaxY(hitRect) < maxY) {
            hitRect.size.height = maxY - hitRect.origin.y;
        }
        if (!NSPointInRect(local, hitRect)) {
            continue;
        }
        // 点在标签本体：交给 item（关闭按钮等）
        if (NSPointInRect(local, item.frame)) {
            NSView *hit = [item hitTest:local];
            if (hit) {
                return hit;
            }
        }
        // 点在顶部留白扩展区：仍算点中该标签，避免被标题栏拖窗抢走
        return item;
    }

    return self;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    if (self.window) {
        [self.window performWindowDragWithEvent:event];
    }
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
@property (nonatomic, strong, nullable) BrowserTabDragGhostController *dragGhost;
@property (nonatomic, assign) BOOL dragDetachMode;
@property (nonatomic, assign) BOOL dragForeignMode;
@property (nonatomic, assign) BOOL dragEnding;
@property (nonatomic, strong, nullable) BrowserTabDropPlaceholderView *foreignPlaceholder;
@property (nonatomic, assign) NSUInteger foreignPlaceholderIndex;
@property (nonatomic, weak, nullable) BrowserTabStripView *activeForeignStrip;
@property (nonatomic, weak, nullable) BrowserWindowController *activeForeignWindow;
@property (nonatomic, assign) NSUInteger activeForeignIndex;
@end

@implementation BrowserTabStripView

- (BOOL)isFlipped {
    // 与 NSStackView 一致：y=0 在顶部，顶部留白语义更直观
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint local = [self convertPoint:point fromView:self.superview];
    // 左侧交通灯区域穿透，避免盖住关闭/最小化/最大化按钮
    if (local.x < kTrafficLightLeadingInset) {
        return nil;
    }
    return [super hitTest:point];
}

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
        _foreignPlaceholderIndex = NSNotFound;
        _activeForeignIndex = NSNotFound;

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

        _tabsContentView = [[BrowserTabStripTabsContainerView alloc] initWithFrame:NSZeroRect];
        ((BrowserTabStripTabsContainerView *)_tabsContentView).stripView = self;
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
        ((BrowserTabStripTabsContainerView *)_tabsContentView).stripView = self;
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

NSColor *BrowserTabStripFillColor(void) {
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        dark = [[NSApp effectiveAppearance] bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameDarkAqua, NSAppearanceNameAqua
        ]] == NSAppearanceNameDarkAqua;
    }
    if (dark) {
        return [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:0.87 green:0.88 blue:0.91 alpha:1.0];
}

- (void)updateStripAppearance {
    NSColor *strip = BrowserTabStripFillColor();
    self.backgroundView.layer.backgroundColor = strip.CGColor;
    if ([self.window isKindOfClass:[NSWindow class]]) {
        self.window.backgroundColor = strip;
    }
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
    // 标签条本体不拖窗；仅 leading/trailing/background 等 DragArea 可拖窗
    return NO;
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
    // 固定/普通标签均显示标题，最小宽统一，超出后进溢出菜单
    CGFloat width = length * BrowserTabItemMinWidth;
    if (length > 1) {
        width += (length - 1) * kTabSpacing;
    }
    (void)start;
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
        ? MAX(stripMiddle - kOverflowButtonWidth - 2.0, BrowserTabItemMinWidth)
        : stripMiddle;

    NSUInteger visibleStart = 0;
    NSUInteger visibleLen = 0;
    [self visibleRangeForCount:visibleCount start:&visibleStart count:&visibleLen];

    NSUInteger pinnedCount = [self pinnedTabCountInStrip];
    CGFloat spacingTotal = (visibleLen > 1) ? (visibleLen - 1) * kTabSpacing : 0;
    CGFloat ideal = visibleLen > 0 ? (available - spacingTotal) / (CGFloat)visibleLen : BrowserTabItemMinWidth;
    CGFloat tabWidth = MIN(BrowserTabItemMaxWidth, MAX(BrowserTabItemMinWidth, ideal));
    CGFloat contentW = (visibleLen > 0) ? (visibleLen * tabWidth + spacingTotal) : 0;
    // isFlipped：y=0 在顶；标签下移 kTabTopInset，高度不铺满
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;

    BOOL geometryChanged = fabs(tabWidth - self.lastLaidOutTabWidth) > 0.5
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

            if (item == self.draggingItem) {
                // 拖拽中的标签保留纵向布局，横向由拖拽逻辑更新
                item.hidden = NO;
                NSRect frame = item.frame;
                frame.origin.y = kTabTopInset;
                frame.size.width = tabWidth;
                frame.size.height = tabHeight;
                item.frame = frame;
                [item applyAvailableWidth:tabWidth];
                x += tabWidth + kTabSpacing;
                continue;
            }

            item.hidden = !visible;
            if (visible) {
                item.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
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
        self.lastLaidOutTabWidth = tabWidth;
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

static const CGFloat kStripDragZoneOutset = 8.0;

- (NSRect)stripEffectiveZoneInScreen {
    NSWindow *window = self.window;
    if (!window) {
        return NSZeroRect;
    }
    NSRect stripRect = [self convertRect:self.bounds toView:nil];
    NSRect screenRect = [window convertRectToScreen:stripRect];
    return NSInsetRect(screenRect, -kStripDragZoneOutset, -kStripDragZoneOutset);
}

- (NSPoint)screenPointFromLocationInWindow:(NSPoint)locationInWindow {
    NSWindow *window = self.window;
    if (!window) {
        return [NSEvent mouseLocation];
    }
    NSRect pointRect = NSMakeRect(locationInWindow.x, locationInWindow.y, 1, 1);
    return [window convertRectToScreen:pointRect].origin;
}

- (void)beginReorderDragForItem:(BrowserTabItemView *)item locationInWindow:(NSPoint)locationInWindow {
    NSUInteger index = [self.tabItems indexOfObject:item];
    if (index == NSNotFound) {
        return;
    }
    self.draggingItem = item;
    self.draggingFromIndex = index;
    self.draggingPreviewIndex = index;
    self.draggingOriginalFrame = item.frame;
    self.suppressLayoutDuringDrag = YES;
    self.dragDetachMode = NO;
    self.dragForeignMode = NO;
    self.dragEnding = NO;
    self.activeForeignStrip = nil;
    self.activeForeignWindow = nil;
    self.activeForeignIndex = NSNotFound;

    NSPoint grabInItem = [item convertPoint:locationInWindow fromView:nil];
    self.dragGhost = [[BrowserTabDragGhostController alloc] init];
    [self.dragGhost beginWithSourceView:item grabPointInSource:grabInItem];
    NSPoint screenPoint = [self screenPointFromLocationInWindow:locationInWindow];
    [self.dragGhost moveToScreenPoint:screenPoint];

    item.hidden = YES;
    [self layoutTabsExcludingDraggedItem:item];
}

- (nullable BrowserWindowController *)hostBrowserWindowController {
    NSWindowController *wc = self.window.windowController;
    if ([wc isKindOfClass:[BrowserWindowController class]]) {
        return (BrowserWindowController *)wc;
    }
    return nil;
}

- (void)clearForeignDropTarget {
    if (self.activeForeignStrip) {
        [self.activeForeignStrip hideForeignDropPlaceholder];
    }
    self.activeForeignStrip = nil;
    self.activeForeignWindow = nil;
    self.activeForeignIndex = NSNotFound;
    self.dragForeignMode = NO;
}

- (void)moveReorderDragForItem:(BrowserTabItemView *)item locationInWindow:(NSPoint)locationInWindow {
    if (item != self.draggingItem || self.dragEnding) {
        return;
    }

    NSPoint screenPoint = [self screenPointFromLocationInWindow:locationInWindow];
    [self.dragGhost moveToScreenPoint:screenPoint];

    BrowserWindowController *sourceWC = [self hostBrowserWindowController];
    AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
    BrowserWindowController *foreignWC = nil;
    if ([appDelegate respondsToSelector:@selector(browserWindowAtScreenPoint:excluding:)]) {
        foreignWC = [appDelegate browserWindowAtScreenPoint:screenPoint excluding:sourceWC];
    }

    if (foreignWC && foreignWC.tabStripView) {
        BrowserTabStripView *foreignStrip = foreignWC.tabStripView;
        NSUInteger insertIndex =
            [foreignStrip insertionIndexForForeignDropAtScreenPoint:screenPoint pinned:item.tabPinned];
        if (self.activeForeignStrip != foreignStrip) {
            [self clearForeignDropTarget];
            self.activeForeignStrip = foreignStrip;
            self.activeForeignWindow = foreignWC;
            if ([appDelegate respondsToSelector:@selector(hideForeignDropPlaceholdersExcludingStrip:)]) {
                [appDelegate hideForeignDropPlaceholdersExcludingStrip:foreignStrip];
            }
        }
        self.activeForeignIndex = insertIndex;
        self.dragForeignMode = YES;
        self.dragDetachMode = NO;
        [foreignStrip updateForeignDropPlaceholderAtIndex:insertIndex];
        [self.dragGhost setStyle:BrowserTabDragGhostStyleForeign animated:YES];
        [self layoutTabsCollapsingDraggedItem:item];
        return;
    }

    if (self.dragForeignMode) {
        [self clearForeignDropTarget];
    }

    BOOL inStrip = NSPointInRect(screenPoint, [self stripEffectiveZoneInScreen]);
    BOOL detach = !inStrip;
    if (detach != self.dragDetachMode || self.dragGhost.style == BrowserTabDragGhostStyleForeign) {
        self.dragDetachMode = detach;
        [self.dragGhost setStyle:(detach ? BrowserTabDragGhostStyleDetach : BrowserTabDragGhostStyleInStrip)
                        animated:YES];
        if (detach) {
            [self layoutTabsCollapsingDraggedItem:item];
        } else {
            [self layoutTabsExcludingDraggedItem:item];
        }
    }

    if (detach) {
        return;
    }

    NSPoint inContent = [self.tabsContentView convertPoint:locationInWindow fromView:nil];
    CGFloat centerX = inContent.x;
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
    BOOL pinned = item.tabPinned;
    NSUInteger actualPinned = 0;
    for (BrowserTabItemView *candidate in self.tabItems) {
        if (candidate.tabPinned) {
            actualPinned++;
        }
    }
    NSUInteger low = pinned ? 0 : actualPinned;
    NSUInteger high = pinned ? actualPinned : self.tabItems.count;
    if (low >= high) {
        return low < self.tabItems.count ? low : NSNotFound;
    }

    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    NSUInteger best = low;
    CGFloat bestDistance = CGFLOAT_MAX;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < self.tabItems.count; i++) {
        if (i >= low && i < high) {
            CGFloat slotCenter = x + tabWidth * 0.5;
            CGFloat distance = fabs(slotCenter - centerX);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
            }
        }
        x += tabWidth + kTabSpacing;
    }
    return best;
}

- (void)layoutTabsExcludingDraggedItem:(BrowserTabItemView *)dragged {
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;
    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    CGFloat x = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        if (item == dragged) {
            x += tabWidth + kTabSpacing;
            continue;
        }
        if (!item.hidden) {
            item.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
            [item applyAvailableWidth:tabWidth];
        }
        x += tabWidth + kTabSpacing;
    }
}

- (void)layoutTabsCollapsingDraggedItem:(BrowserTabItemView *)dragged {
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;
    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    CGFloat x = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        if (item == dragged) {
            continue;
        }
        if (!item.hidden) {
            item.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
            [item applyAvailableWidth:tabWidth];
        }
        x += tabWidth + kTabSpacing;
    }
}

- (void)layoutTabsInsertingPlaceholderAtIndex:(NSUInteger)index {
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;
    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    CGFloat x = 0;
    NSUInteger slot = 0;
    BOOL placedPlaceholder = NO;

    for (BrowserTabItemView *item in self.tabItems) {
        if (slot == index && !placedPlaceholder) {
            self.foreignPlaceholder.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
            self.foreignPlaceholder.hidden = NO;
            x += tabWidth + kTabSpacing;
            placedPlaceholder = YES;
        }
        if (!item.hidden) {
            item.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
            [item applyAvailableWidth:tabWidth];
        }
        x += tabWidth + kTabSpacing;
        slot++;
    }
    if (!placedPlaceholder) {
        self.foreignPlaceholder.frame = NSMakeRect(x, kTabTopInset, tabWidth, tabHeight);
        self.foreignPlaceholder.hidden = NO;
    }

    CGFloat contentW = MAX(x + (placedPlaceholder ? 0 : (tabWidth + kTabSpacing)), 1);
    NSRect contentFrame = self.tabsContentView.frame;
    contentFrame.size.width = MAX(contentW, NSWidth(self.tabsClipView.bounds));
    contentFrame.size.height = BrowserTabStripHeight;
    self.tabsContentView.frame = contentFrame;
}

- (void)showForeignDropPlaceholderAtIndex:(NSUInteger)index {
    if (!self.foreignPlaceholder) {
        self.foreignPlaceholder = [[BrowserTabDropPlaceholderView alloc] initWithFrame:NSZeroRect];
        [self.tabsContentView addSubview:self.foreignPlaceholder];
    }
    self.foreignPlaceholderIndex = index;
    self.suppressLayoutDuringDrag = YES;
    [self layoutTabsInsertingPlaceholderAtIndex:index];
}

- (void)updateForeignDropPlaceholderAtIndex:(NSUInteger)index {
    if (self.foreignPlaceholderIndex == index && self.foreignPlaceholder && !self.foreignPlaceholder.hidden) {
        return;
    }
    [self showForeignDropPlaceholderAtIndex:index];
}

- (void)hideForeignDropPlaceholder {
    self.foreignPlaceholderIndex = NSNotFound;
    if (self.foreignPlaceholder) {
        self.foreignPlaceholder.hidden = YES;
    }
    if (!self.draggingItem) {
        self.suppressLayoutDuringDrag = NO;
        [self invalidateTabLayoutCache];
        [self setNeedsLayout:YES];
        [self layoutSubtreeIfNeeded];
    }
}

- (NSUInteger)insertionIndexForForeignDropAtScreenPoint:(NSPoint)screenPoint pinned:(BOOL)pinned {
    NSWindow *window = self.window;
    if (!window) {
        return self.tabItems.count;
    }
    NSRect pointRect = NSMakeRect(screenPoint.x, screenPoint.y, 1, 1);
    // screen → window → content
    NSRect inWindow = [window convertRectFromScreen:pointRect];
    NSPoint inContent = [self.tabsContentView convertPoint:inWindow.origin fromView:nil];

    NSUInteger actualPinned = 0;
    for (BrowserTabItemView *candidate in self.tabItems) {
        if (candidate.tabPinned) {
            actualPinned++;
        }
    }
    NSUInteger low = pinned ? 0 : actualPinned;
    // insertion can be at end of range (count of items in zone)
    NSUInteger high = pinned ? actualPinned : self.tabItems.count;
    // Allow inserting at index == high (append within zone).
    // Best slot boundary: between tabs and ends.
    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    NSUInteger best = low;
    CGFloat bestDistance = CGFLOAT_MAX;
    NSUInteger slotCount = high - low + 1; // insertion points
    for (NSUInteger s = 0; s < slotCount; s++) {
        NSUInteger insertAt = low + s;
        CGFloat slotX = insertAt * (tabWidth + kTabSpacing);
        CGFloat slotCenter = slotX + tabWidth * 0.5;
        CGFloat distance = fabs(slotCenter - inContent.x);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = insertAt;
        }
    }
    return best;
}

- (NSRect)screenRectForTabSlotAtIndex:(NSUInteger)index size:(NSSize)size {
    NSWindow *window = self.window;
    CGFloat tabWidth = self.lastLaidOutTabWidth > 0 ? self.lastLaidOutTabWidth : BrowserTabItemMinWidth;
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;
    CGFloat x = index * (tabWidth + kTabSpacing);
    NSRect localInContent = NSMakeRect(x, kTabTopInset, size.width > 0 ? size.width : tabWidth,
                                       size.height > 0 ? size.height : tabHeight);
    NSRect inWindow = [self.tabsContentView convertRect:localInContent toView:nil];
    if (!window) {
        return inWindow;
    }
    return [window convertRectToScreen:inWindow];
}

- (void)finishDragSessionRestoringItem:(BrowserTabItemView *)item {
    [self clearForeignDropTarget];
    item.hidden = NO;
    [self.dragGhost endAndRemoveImmediately];
    self.dragGhost = nil;
    self.draggingItem = nil;
    self.draggingFromIndex = NSNotFound;
    self.draggingPreviewIndex = NSNotFound;
    self.suppressLayoutDuringDrag = NO;
    self.dragDetachMode = NO;
    self.dragForeignMode = NO;
    self.dragEnding = NO;
    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];
}

- (void)endReorderDragForItem:(BrowserTabItemView *)item locationInWindow:(NSPoint)locationInWindow {
    if (item != self.draggingItem || self.dragEnding) {
        return;
    }

    NSUInteger toIndex = [self.tabItems indexOfObject:item];
    NSUInteger fromIndex = self.draggingFromIndex;
    NSUUID *tabID = [self.tabItemIDs objectForKey:item];
    NSPoint screenPoint = [self screenPointFromLocationInWindow:locationInWindow];

    BrowserWindowController *foreignWC = self.activeForeignWindow;
    BrowserTabStripView *foreignStrip = self.activeForeignStrip;
    NSUInteger foreignIndex = self.activeForeignIndex;
    BOOL foreignDrop = (foreignWC != nil && foreignStrip != nil && tabID != nil
                        && NSPointInRect(screenPoint, [foreignStrip stripEffectiveZoneInScreen]));

    self.dragEnding = YES;
    __weak typeof(self) weakSelf = self;
    BrowserTabDragGhostController *ghost = self.dragGhost;

    void (^commitForeign)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSUUID *movedID = tabID;
        BrowserWindowController *destination = foreignWC;
        NSUInteger atIndex = foreignIndex;
        [strongSelf clearForeignDropTarget];
        item.hidden = NO;
        [strongSelf.dragGhost endAndRemoveImmediately];
        strongSelf.dragGhost = nil;
        strongSelf.draggingItem = nil;
        strongSelf.draggingFromIndex = NSNotFound;
        strongSelf.draggingPreviewIndex = NSNotFound;
        strongSelf.suppressLayoutDuringDrag = NO;
        strongSelf.dragDetachMode = NO;
        strongSelf.dragForeignMode = NO;
        strongSelf.dragEnding = NO;
        [strongSelf invalidateTabLayoutCache];
        [strongSelf setNeedsLayout:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) inner = weakSelf;
            if (!inner || !destination || !movedID) {
                return;
            }
            id<BrowserTabStripViewDelegate> delegate = inner.delegate;
            if ([delegate respondsToSelector:@selector(tabStripView:didRequestTransferTabID:toWindow:atIndex:)]) {
                [delegate tabStripView:inner
             didRequestTransferTabID:movedID
                            toWindow:destination
                             atIndex:atIndex];
            }
        });
    };

    void (^commitDetach)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf finishDragSessionRestoringItem:item];
        if (!tabID) {
            return;
        }
        NSUUID *movedID = tabID;
        NSPoint dropPoint = screenPoint;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) inner = weakSelf;
            if (!inner) {
                return;
            }
            id<BrowserTabStripViewDelegate> delegate = inner.delegate;
            if ([delegate respondsToSelector:@selector(tabStripView:didRequestMoveTabIDToNewWindow:screenPoint:)]) {
                [delegate tabStripView:inner
        didRequestMoveTabIDToNewWindow:movedID
                           screenPoint:dropPoint];
            }
        });
    };

    void (^commitReorder)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf finishDragSessionRestoringItem:item];
        if (tabID && toIndex != NSNotFound && toIndex != fromIndex) {
            NSUUID *movedID = tabID;
            NSUInteger movedTo = toIndex;
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) inner = weakSelf;
                if (!inner) {
                    return;
                }
                id<BrowserTabStripViewDelegate> delegate = inner.delegate;
                if ([delegate respondsToSelector:@selector(tabStripView:didMoveTabID:toIndex:)]) {
                    [delegate tabStripView:inner didMoveTabID:movedID toIndex:movedTo];
                }
            });
        }
    };

    if (foreignDrop) {
        [ghost fadeOutWithCompletion:^{
            commitForeign();
        }];
        return;
    }

    [self clearForeignDropTarget];
    BOOL detach = !NSPointInRect(screenPoint, [self stripEffectiveZoneInScreen]);

    if (detach && tabID) {
        NSSize ghostSize = ghost.ghostSize;
        if (ghostSize.width < 1) {
            ghostSize = item.bounds.size;
        }
        NSRect flyRect = NSMakeRect(screenPoint.x - ghostSize.width * 0.25,
                                    screenPoint.y - ghostSize.height * 0.5,
                                    ghostSize.width,
                                    ghostSize.height);
        [ghost setStyle:BrowserTabDragGhostStyleDetach animated:NO];
        [ghost animateToScreenRect:flyRect completion:^{
            commitDetach();
        }];
        return;
    }

    NSUInteger slotIndex = (toIndex != NSNotFound) ? toIndex : fromIndex;
    NSRect slotRect = [self screenRectForTabSlotAtIndex:slotIndex size:ghost.ghostSize];
    [ghost setStyle:BrowserTabDragGhostStyleInStrip animated:NO];
    [ghost animateToScreenRect:slotRect completion:^{
        commitReorder();
    }];
}

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    if (self.draggingItem) {
        self.draggingItem.hidden = NO;
        self.draggingItem = nil;
        self.suppressLayoutDuringDrag = NO;
        self.dragEnding = NO;
        self.dragDetachMode = NO;
        self.dragForeignMode = NO;
        [self.dragGhost endAndRemoveImmediately];
        self.dragGhost = nil;
        [self clearForeignDropTarget];
    }
    [self hideForeignDropPlaceholder];

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
        item.onReorderDragBegan = ^(NSPoint locationInWindow) {
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf beginReorderDragForItem:strongItem locationInWindow:locationInWindow];
            }
        };
        item.onReorderDragMoved = ^(NSPoint locationInWindow) {
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf moveReorderDragForItem:strongItem locationInWindow:locationInWindow];
            }
        };
        item.onReorderDragEnded = ^(NSPoint locationInWindow) {
            BrowserTabItemView *strongItem = weakItem;
            if (strongItem) {
                [weakSelf endReorderDragForItem:strongItem locationInWindow:locationInWindow];
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

    NSMenuItem *moveToWindow = [menu addItemWithTitle:@"将标签移到新窗口"
                                               action:@selector(contextMoveTabToNewWindow:)
                                        keyEquivalent:@""];
    moveToWindow.target = self;
    moveToWindow.representedObject = tabID;

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

- (void)contextMoveTabToNewWindow:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tabStripView:didRequestMoveTabIDToNewWindow:screenPoint:)]) {
        return;
    }
    NSPoint screenPoint = [NSEvent mouseLocation];
    [delegate tabStripView:self didRequestMoveTabIDToNewWindow:tabID screenPoint:screenPoint];
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

    if (action == @selector(contextMoveTabToNewWindow:)) {
        return tabID != nil &&
            [delegate respondsToSelector:@selector(tabStripView:didRequestMoveTabIDToNewWindow:screenPoint:)];
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
