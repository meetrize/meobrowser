#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"

const CGFloat BrowserTabStripHeight = 36.0;

static const CGFloat kTrafficLightLeadingInset = 78.0;
static const CGFloat kTabTopInset = 3.0;
static const CGFloat kTrailingDragWidth = 16.0;
static const CGFloat kTabSpacing = 2.0;
static const CGFloat kOverflowButtonWidth = 22.0;

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

@interface BrowserTabStripView ()
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *leadingDragArea;
@property (nonatomic, strong) NSView *trailingDragArea;
@property (nonatomic, strong) BrowserTabStripClipView *tabsClipView;
@property (nonatomic, strong) NSView *tabsContentView;
@property (nonatomic, strong) NSButton *overflowButton;
@property (nonatomic, strong) NSLayoutConstraint *overflowWidthConstraint;
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

        _overflowButton = [self makeOverflowButton];
        _overflowButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_overflowButton setContentHuggingPriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_overflowButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                  forOrientation:NSLayoutConstraintOrientationHorizontal];

        _addTabButton = [self newTabButton];
        _addTabButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_addTabButton setContentHuggingPriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_addTabButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];

        _trailingDragArea = [[BrowserTabStripDragAreaView alloc] init];
        _trailingDragArea.translatesAutoresizingMaskIntoConstraints = NO;
        [_trailingDragArea setContentHuggingPriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_trailingDragArea setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self addSubview:_backgroundView];
        [self addSubview:_leadingDragArea];
        [self addSubview:_tabsClipView];
        [self addSubview:_overflowButton];
        [self addSubview:_addTabButton];
        [self addSubview:_trailingDragArea];

        _overflowWidthConstraint = [_overflowButton.widthAnchor constraintEqualToConstant:0];

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

            [_tabsClipView.leadingAnchor constraintEqualToAnchor:_leadingDragArea.trailingAnchor constant:4],
            [_tabsClipView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_tabsClipView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_tabsClipView.trailingAnchor constraintEqualToAnchor:_overflowButton.leadingAnchor constant:-2],

            [_overflowButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_overflowButton.heightAnchor constraintEqualToConstant:24],
            _overflowWidthConstraint,
            [_overflowButton.trailingAnchor constraintEqualToAnchor:_addTabButton.leadingAnchor constant:-4],

            [_addTabButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_addTabButton.widthAnchor constraintEqualToConstant:24],
            [_addTabButton.heightAnchor constraintEqualToConstant:24],
            [_addTabButton.trailingAnchor constraintEqualToAnchor:_trailingDragArea.leadingAnchor constant:-4],

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
    [self updateTabFrames];
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

/// 在总宽 fullWidth 下最多能完整放下几个最小宽标签（可预留 overflow 按钮）
- (NSUInteger)maxVisibleTabCountForWidth:(CGFloat)fullWidth {
    if (fullWidth < 1.0 || self.tabItems.count == 0) {
        return 0;
    }

    NSUInteger total = self.tabItems.count;
    CGFloat spacing = kTabSpacing;
    CGFloat minW = BrowserTabItemMinWidth;

    // 先看不显示箭头时能否全部放下
    CGFloat allWidth = total * minW + (total > 1 ? (total - 1) * spacing : 0);
    if (allWidth <= fullWidth + 0.5) {
        return total;
    }

    // 需要箭头：从可用宽度里扣掉箭头占位
    CGFloat tabsWidth = fullWidth - kOverflowButtonWidth - 2.0;
    if (tabsWidth < minW) {
        return 1;
    }

    NSUInteger maxCount = (NSUInteger)floor((tabsWidth + spacing) / (minW + spacing));
    if (maxCount < 1) {
        maxCount = 1;
    }
    if (maxCount > total) {
        maxCount = total;
    }
    // 若算出来能放下全部，则不必用 overflow（边界浮点）
    if (maxCount >= total) {
        return total;
    }
    return maxCount;
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
    self.overflowWidthConstraint.constant = visible ? kOverflowButtonWidth : 0;
}

- (void)updateTabFrames {
    NSUInteger total = self.tabItems.count;
    // 中间可供「标签 + 可选箭头」的宽度（不含交通灯 / + / trailing）
    // leading(78)+4 + middle + 4 + add(24) + 4 + trailing(16) = bounds.width
    CGFloat reservedChrome = kTrafficLightLeadingInset + 4.0 + 4.0 + 24.0 + 4.0 + kTrailingDragWidth;
    CGFloat stripMiddle = NSWidth(self.bounds) - reservedChrome;

    if (total == 0 || stripMiddle < 1.0) {
        [self setOverflowVisible:NO];
        self.tabsContentView.frame = NSMakeRect(0, 0, 1, BrowserTabStripHeight);
        [self.overflowTabIDs removeAllObjects];
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

    CGFloat spacingTotal = (visibleLen > 1) ? (visibleLen - 1) * kTabSpacing : 0;
    CGFloat ideal = visibleLen > 0 ? (available - spacingTotal) / (CGFloat)visibleLen : BrowserTabItemMinWidth;
    CGFloat tabWidth = MIN(BrowserTabItemMaxWidth, MAX(BrowserTabItemMinWidth, ideal));
    CGFloat tabHeight = BrowserTabStripHeight - kTabTopInset;

    BOOL geometryChanged = fabs(tabWidth - self.lastLaidOutTabWidth) > 0.5
        || fabs(available - self.lastLaidOutAvailableWidth) > 0.5
        || total != self.lastLaidOutTabCount
        || visibleStart != self.lastVisibleStart
        || visibleLen != self.lastVisibleCount
        || needsOverflow != self.lastOverflowVisible;

    if (!geometryChanged) {
        return;
    }

    [self.overflowTabIDs removeAllObjects];
    CGFloat x = 0;
    for (NSUInteger i = 0; i < total; i++) {
        BrowserTabItemView *item = self.tabItems[i];
        BOOL visible = (i >= visibleStart && i < visibleStart + visibleLen);
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

    CGFloat contentW = (visibleLen > 0) ? (visibleLen * tabWidth + spacingTotal) : available;
    self.tabsContentView.frame = NSMakeRect(0, 0, MAX(contentW, 1), BrowserTabStripHeight);
    self.lastLaidOutTabWidth = tabWidth;
    self.lastLaidOutAvailableWidth = available;
    self.lastLaidOutTabCount = total;
    self.lastVisibleStart = visibleStart;
    self.lastVisibleCount = visibleLen;
    self.lastOverflowVisible = needsOverflow;
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
        NSString *title = itemView.tabTitle.length > 0 ? itemView.tabTitle : @"新标签页";
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

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    for (BrowserTabItemView *item in self.tabItems) {
        [item removeFromSuperview];
    }
    [self.tabItems removeAllObjects];
    [self.tabItemIDs removeAllObjects];
    [self.tabItemsByID removeAllObjects];
    [self.overflowTabIDs removeAllObjects];
    self.lastLaidOutTabWidth = -1;
    self.lastLaidOutAvailableWidth = -1;
    self.lastLaidOutTabCount = NSNotFound;
    self.lastVisibleStart = NSNotFound;
    self.lastVisibleCount = NSNotFound;
    self.selectedTabID = selectedTabID;

    for (BrowserTab *tab in tabs) {
        BOOL selected = [tab.tabID isEqual:selectedTabID];
        BrowserTabItemView *item = [[BrowserTabItemView alloc] initWithFrame:NSZeroRect];
        item.translatesAutoresizingMaskIntoConstraints = YES;
        item.autoresizingMask = NSViewNotSizable;
        item.tabTitle = [tab displayTitle];
        item.tabSelected = selected;

        __weak typeof(self) weakSelf = self;
        NSUUID *tabID = tab.tabID;
        item.onSelect = ^{
            [weakSelf.delegate tabStripView:weakSelf didSelectTabID:tabID];
        };
        item.onClose = ^{
            [weakSelf.delegate tabStripView:weakSelf didCloseTabID:tabID];
        };

        [self.tabItemIDs setObject:tab.tabID forKey:item];
        [self.tabItemsByID setObject:item forKey:tab.tabID];
        [self.tabItems addObject:item];
        [self.tabsContentView addSubview:item];
    }

    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];
}

- (void)syncWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    if (self.tabItems.count != tabs.count) {
        [self reloadWithTabs:tabs selectedTabID:selectedTabID];
        return;
    }

    BOOL selectionChanged = (self.selectedTabID != selectedTabID)
        && ![self.selectedTabID isEqual:selectedTabID];
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

        BOOL selected = [tab.tabID isEqual:selectedTabID];
        if (item.tabSelected != selected) {
            item.tabSelected = selected;
        }
    }

    if (selectionChanged) {
        // 选中变化可能改变可见窗口（需把选中项滚入条内）
        self.lastVisibleStart = NSNotFound;
        [self setNeedsLayout:YES];
    }
}

- (void)onNewTab:(id)sender {
    (void)sender;
    [self.delegate tabStripViewDidRequestNewTab:self];
}

@end
