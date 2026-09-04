#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"
#import "BrowserTabOverflowMenuRowView.h"
#import "BrowserTabDragGhostController.h"
#import "BrowserTabDropPlaceholderView.h"
#import "BrowserTabStripChromeActionsView.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"

const CGFloat BrowserTabStripHeightRegular = 36.0;
const CGFloat BrowserTabStripHeightCompact = 32.0;
const CGFloat BrowserTabStripHeight = 36.0; // 兼容旧引用 = Regular

static const CGFloat kTrafficLightLeadingInsetRegular = 78.0;
static const CGFloat kTrafficLightLeadingInsetCompact = 72.0;
static const CGFloat kTabTopInsetRegular = 5.0;
/// 精简模式与常态同为顶部 5pt inset；高度 = 条高 − inset，底边贴齐、不铺满。
static const CGFloat kTabTopInsetCompact = 5.0;
static const CGFloat kTrailingDragWidth = 16.0;
static const CGFloat kTabSpacing = 2.0;
static const CGFloat kOverflowButtonWidth = 22.0;
static const CGFloat kAddButtonWidth = 24.0;
static const CGFloat kAddButtonHeight = 24.0;
static const CGFloat kChromeGap = 4.0;

static NSString *BrowserTabToolTipString(BrowserTab *tab) {
    NSString *title = [tab displayTitle];
    if (title.length == 0) {
        title = @"新标签页";
    }
    if (tab.isNewTabPage) {
        return title;
    }
    NSURL *url = [tab currentOrRestorableURL];
    NSString *urlString = url.absoluteString;
    if (urlString.length == 0) {
        return title;
    }
    // Chrome 式：完整标题 + 完整网址（两行）
    return [NSString stringWithFormat:@"%@\n%@", title, urlString];
}

static NSString *BrowserTabPageURLString(BrowserTab *tab) {
    if (tab.isNewTabPage) {
        return @"";
    }
    NSURL *url = [tab currentOrRestorableURL];
    return url.absoluteString ?: @"";
}

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
@property (nonatomic, strong, nullable) NSLayoutConstraint *tabsClipTrailingToTrailingDrag;
@property (nonatomic, strong, nullable) NSLayoutConstraint *tabsClipTrailingToChromeActions;
@property (nonatomic, strong, nullable) NSLayoutConstraint *chromeActionsTrailingToTrailingDrag;
@property (nonatomic, strong, nullable) NSLayoutConstraint *chromeActionsCenterY;
@property (nonatomic, strong, nullable) NSLayoutConstraint *chromeActionsWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *leadingDragWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *tabsClipLeadingConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *leadingNavLeadingConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *leadingNavCenterYConstraint;
@property (nonatomic, strong) NSMutableArray<BrowserTabItemView *> *tabItems;
@property (nonatomic, strong) NSMapTable<BrowserTabItemView *, NSUUID *> *tabItemIDs;
@property (nonatomic, strong) NSMapTable<NSUUID *, BrowserTabItemView *> *tabItemsByID;
@property (nonatomic, copy) NSArray<BrowserTab *> *layoutTabs;
@property (nonatomic, strong) NSMapTable<NSUUID *, BrowserTab *> *layoutTabsByID;
@property (nonatomic, strong, nullable) NSUUID *selectedTabID;
@property (nonatomic, strong) NSMutableArray<NSUUID *> *overflowTabIDs;
@property (nonatomic, assign) CGFloat lastLaidOutTabWidth;
@property (nonatomic, assign) CGFloat lastLaidOutInactiveTabWidth;
@property (nonatomic, assign) CGFloat lastLaidOutSelectedTabWidth;
@property (nonatomic, assign) CGFloat lastLaidOutAvailableWidth;
@property (nonatomic, assign) NSUInteger lastLaidOutTabCount;
@property (nonatomic, copy, nullable) NSString *lastVisibleSignature;
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
    if (local.x < [self effectiveTrafficLightInset]) {
        return nil;
    }
    return [super hitTest:point];
}

- (CGFloat)effectiveStripHeight {
    return self.compactMetricsEnabled ? BrowserTabStripHeightCompact : BrowserTabStripHeightRegular;
}

- (CGFloat)effectiveTrafficLightInset {
    return self.compactMetricsEnabled ? kTrafficLightLeadingInsetCompact : kTrafficLightLeadingInsetRegular;
}

- (CGFloat)effectiveTabTopInset {
    return self.compactMetricsEnabled ? kTabTopInsetCompact : kTabTopInsetRegular;
}

/// 标签纵向：以实际条高为准；顶 inset 后底边贴齐（不铺满条高）。
- (void)tabVerticalMetricsWithStripHeight:(CGFloat *)outStripHeight
                                topInset:(CGFloat *)outTopInset
                               tabHeight:(CGFloat *)outTabHeight {
    CGFloat stripH = NSHeight(self.bounds);
    if (stripH < 1.0) {
        stripH = [self effectiveStripHeight];
    }
    CGFloat topInset = [self effectiveTabTopInset];
    if (outStripHeight) {
        *outStripHeight = stripH;
    }
    if (outTopInset) {
        *outTopInset = topInset;
    }
    if (outTabHeight) {
        *outTabHeight = MAX(stripH - topInset, 1.0);
    }
}

- (CGFloat)leadingNavigationReservedWidth {
    NSView *nav = self.leadingNavigationView;
    if (!nav || nav.hidden) {
        return 0;
    }
    CGFloat width = NSWidth(nav.bounds);
    if (width < 1.0) {
        width = nav.fittingSize.width;
    }
    if (width < 1.0) {
        return 0;
    }
    return width + kChromeGap;
}

- (CGFloat)tabsClipLeadingOffset {
    return [self effectiveTrafficLightInset] + [self leadingNavigationReservedWidth] + kChromeGap;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;

        _tabItems = [NSMutableArray array];
        _tabItemIDs = [NSMapTable weakToStrongObjectsMapTable];
        _tabItemsByID = [NSMapTable strongToWeakObjectsMapTable];
        _layoutTabs = @[];
        _layoutTabsByID = [NSMapTable strongToStrongObjectsMapTable];
        _overflowTabIDs = [NSMutableArray array];
        _lastLaidOutTabWidth = -1;
        _lastLaidOutInactiveTabWidth = -1;
        _lastLaidOutSelectedTabWidth = -1;
        _lastLaidOutAvailableWidth = -1;
        _lastLaidOutTabCount = NSNotFound;
        _lastVisibleSignature = nil;
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

        NSLayoutConstraint *tabsClipTrailing =
            [_tabsClipView.trailingAnchor constraintEqualToAnchor:_trailingDragArea.leadingAnchor];
        _tabsClipTrailingToTrailingDrag = tabsClipTrailing;

        NSLayoutConstraint *heightConstraint =
            [self.heightAnchor constraintEqualToConstant:BrowserTabStripHeightRegular];
        _heightConstraint = heightConstraint;

        NSLayoutConstraint *leadingWidth =
            [_leadingDragArea.widthAnchor constraintEqualToConstant:kTrafficLightLeadingInsetRegular];
        _leadingDragWidthConstraint = leadingWidth;

        NSLayoutConstraint *tabsClipLeading =
            [_tabsClipView.leadingAnchor constraintEqualToAnchor:_leadingDragArea.trailingAnchor
                                                       constant:kChromeGap];
        _tabsClipLeadingConstraint = tabsClipLeading;

        [NSLayoutConstraint activateConstraints:@[
            heightConstraint,

            [_backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_leadingDragArea.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_leadingDragArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_leadingDragArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            leadingWidth,

            tabsClipLeading,
            [_tabsClipView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_tabsClipView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            tabsClipTrailing,

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

- (CGFloat)chromeActionsReservedWidth {
    NSView *actions = self.chromeActionsView;
    if (!actions || actions.hidden) {
        return 0;
    }
    CGFloat width = 0;
    if ([actions isKindOfClass:[BrowserTabStripChromeActionsView class]]) {
        width = [(BrowserTabStripChromeActionsView *)actions preferredWidth];
    } else {
        width = NSWidth(actions.bounds);
        if (width < 1.0) {
            width = actions.fittingSize.width;
        }
    }
    if (width < 1.0) {
        return 0;
    }
    return width + kChromeGap;
}

- (void)refreshChromeActionsLayout {
    if (!self.chromeActionsView || !self.chromeActionsWidthConstraint) {
        return;
    }
    CGFloat actionsWidth = 0;
    if ([self.chromeActionsView isKindOfClass:[BrowserTabStripChromeActionsView class]]) {
        actionsWidth = [(BrowserTabStripChromeActionsView *)self.chromeActionsView preferredWidth];
    }
    if (actionsWidth < 1.0) {
        actionsWidth = self.chromeActionsView.fittingSize.width;
    }
    self.chromeActionsWidthConstraint.constant = MAX(actionsWidth, 1);
    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
}

- (void)setChromeActionsView:(NSView *)chromeActionsView {
    if (_chromeActionsView == chromeActionsView) {
        return;
    }

    if (_chromeActionsView) {
        [_chromeActionsView removeFromSuperview];
    }
    if (self.tabsClipTrailingToChromeActions) {
        self.tabsClipTrailingToChromeActions.active = NO;
        self.tabsClipTrailingToChromeActions = nil;
    }
    if (self.chromeActionsTrailingToTrailingDrag) {
        self.chromeActionsTrailingToTrailingDrag.active = NO;
        self.chromeActionsTrailingToTrailingDrag = nil;
    }
    if (self.chromeActionsCenterY) {
        self.chromeActionsCenterY.active = NO;
        self.chromeActionsCenterY = nil;
    }
    if (self.chromeActionsWidthConstraint) {
        self.chromeActionsWidthConstraint.active = NO;
        self.chromeActionsWidthConstraint = nil;
    }

    _chromeActionsView = chromeActionsView;

    if (!chromeActionsView) {
        self.tabsClipTrailingToTrailingDrag.active = YES;
        [self invalidateTabLayoutCache];
        [self setNeedsLayout:YES];
        return;
    }

    chromeActionsView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:chromeActionsView positioned:NSWindowAbove relativeTo:self.tabsClipView];
    // 保证 ▾ / + 仍叠在动作区之上，避免重叠时点不到
    [self addSubview:self.overflowButton];
    [self addSubview:self.addTabButton];

    self.tabsClipTrailingToTrailingDrag.active = NO;

    CGFloat actionsWidth = 0;
    if ([chromeActionsView isKindOfClass:[BrowserTabStripChromeActionsView class]]) {
        actionsWidth = [(BrowserTabStripChromeActionsView *)chromeActionsView preferredWidth];
    }
    if (actionsWidth < 1.0) {
        actionsWidth = chromeActionsView.fittingSize.width;
    }

    self.tabsClipTrailingToChromeActions =
        [self.tabsClipView.trailingAnchor constraintEqualToAnchor:chromeActionsView.leadingAnchor
                                                         constant:-kChromeGap];
    self.chromeActionsTrailingToTrailingDrag =
        [chromeActionsView.trailingAnchor constraintEqualToAnchor:self.trailingDragArea.leadingAnchor];
    self.chromeActionsCenterY =
        [chromeActionsView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
    self.chromeActionsWidthConstraint =
        [chromeActionsView.widthAnchor constraintEqualToConstant:MAX(actionsWidth, 1)];

    [NSLayoutConstraint activateConstraints:@[
        self.tabsClipTrailingToChromeActions,
        self.chromeActionsTrailingToTrailingDrag,
        self.chromeActionsCenterY,
        self.chromeActionsWidthConstraint,
    ]];

    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
}

- (void)setLeadingNavigationView:(NSView *)leadingNavigationView {
    if (_leadingNavigationView == leadingNavigationView) {
        return;
    }

    if (_leadingNavigationView) {
        [_leadingNavigationView removeFromSuperview];
    }
    if (self.leadingNavLeadingConstraint) {
        self.leadingNavLeadingConstraint.active = NO;
        self.leadingNavLeadingConstraint = nil;
    }
    if (self.leadingNavCenterYConstraint) {
        self.leadingNavCenterYConstraint.active = NO;
        self.leadingNavCenterYConstraint = nil;
    }
    self.tabsClipLeadingConstraint.active = NO;

    _leadingNavigationView = leadingNavigationView;

    if (!leadingNavigationView) {
        self.tabsClipLeadingConstraint =
            [self.tabsClipView.leadingAnchor constraintEqualToAnchor:self.leadingDragArea.trailingAnchor
                                                            constant:kChromeGap];
        self.tabsClipLeadingConstraint.active = YES;
        [self invalidateTabLayoutCache];
        [self setNeedsLayout:YES];
        return;
    }

    leadingNavigationView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:leadingNavigationView positioned:NSWindowAbove relativeTo:self.leadingDragArea];
    [self addSubview:self.overflowButton];
    [self addSubview:self.addTabButton];

    self.leadingNavLeadingConstraint =
        [leadingNavigationView.leadingAnchor constraintEqualToAnchor:self.leadingDragArea.trailingAnchor
                                                            constant:kChromeGap];
    self.leadingNavCenterYConstraint =
        [leadingNavigationView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
    self.tabsClipLeadingConstraint =
        [self.tabsClipView.leadingAnchor constraintEqualToAnchor:leadingNavigationView.trailingAnchor
                                                        constant:kChromeGap];

    [NSLayoutConstraint activateConstraints:@[
        self.leadingNavLeadingConstraint,
        self.leadingNavCenterYConstraint,
        self.tabsClipLeadingConstraint,
    ]];

    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
}

- (void)setCompactMetricsEnabled:(BOOL)compactMetricsEnabled {
    if (_compactMetricsEnabled == compactMetricsEnabled) {
        return;
    }
    _compactMetricsEnabled = compactMetricsEnabled;
    self.heightConstraint.constant = [self effectiveStripHeight];
    self.leadingDragWidthConstraint.constant = [self effectiveTrafficLightInset];
    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
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

- (void)updateLayoutTabs:(NSArray<BrowserTab *> *)tabs {
    self.layoutTabs = [tabs copy];
    [self.layoutTabsByID removeAllObjects];
    for (BrowserTab *tab in tabs) {
        [self.layoutTabsByID setObject:tab forKey:tab.tabID];
    }
}

- (NSUInteger)indexForTabID:(NSUUID *)tabID {
    BrowserTabItemView *item = [self.tabItemsByID objectForKey:tabID];
    if (!item) {
        return NSNotFound;
    }
    return [self.tabItems indexOfObject:item];
}

- (NSTimeInterval)lastActiveTimestampForTabID:(NSUUID *)tabID {
    BrowserTab *tab = [self.layoutTabsByID objectForKey:tabID];
    if (!tab) {
        return 0;
    }
    return tab.lastActiveTimestamp;
}

- (NSMutableSet<NSUUID *> *)mustVisibleTabIDs {
    NSMutableSet<NSUUID *> *must = [NSMutableSet set];
    if (self.selectedTabID) {
        [must addObject:self.selectedTabID];
    }
    for (BrowserTabItemView *item in self.tabItems) {
        if (!item.tabPinned) {
            continue;
        }
        NSUUID *tabID = [self.tabItemIDs objectForKey:item];
        if (tabID) {
            [must addObject:tabID];
        }
    }
    return must;
}

- (CGFloat)minimumLayoutWidthForTabID:(NSUUID *)tabID {
    if ([tabID isEqual:self.selectedTabID]) {
        return BrowserTabItemMinimalSelectedWidth;
    }
    return BrowserTabItemAbsoluteMinWidth;
}

- (CGFloat)widthNeededForTabIDs:(NSArray<NSUUID *> *)tabIDs {
    if (tabIDs.count == 0) {
        return 0;
    }
    CGFloat total = 0;
    for (NSUUID *tabID in tabIDs) {
        total += [self minimumLayoutWidthForTabID:tabID];
    }
    if (tabIDs.count > 1) {
        total += (tabIDs.count - 1) * kTabSpacing;
    }
    return total;
}

- (NSArray<NSUUID *> *)candidateTabIDsSortedByLRUDescendingExcluding:(NSSet<NSUUID *> *)excluded {
    NSMutableArray<NSUUID *> *candidates = [NSMutableArray array];
    for (BrowserTabItemView *item in self.tabItems) {
        NSUUID *tabID = [self.tabItemIDs objectForKey:item];
        if (!tabID || [excluded containsObject:tabID]) {
            continue;
        }
        [candidates addObject:tabID];
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSUUID *a, NSUUID *b) {
        NSTimeInterval ta = [self lastActiveTimestampForTabID:a];
        NSTimeInterval tb = [self lastActiveTimestampForTabID:b];
        if (ta > tb) {
            return NSOrderedAscending;
        }
        if (ta < tb) {
            return NSOrderedDescending;
        }
        NSUInteger ia = [self indexForTabID:a];
        NSUInteger ib = [self indexForTabID:b];
        if (ia < ib) {
            return NSOrderedAscending;
        }
        if (ia > ib) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return candidates;
}

- (NSSet<NSUUID *> *)visibleTabIDsForBudget:(CGFloat)budget {
    NSSet<NSUUID *> *must = [self mustVisibleTabIDs];
    NSMutableArray<NSUUID *> *visible = [NSMutableArray array];
    for (BrowserTabItemView *item in self.tabItems) {
        NSUUID *tabID = [self.tabItemIDs objectForKey:item];
        if (tabID && [must containsObject:tabID]) {
            [visible addObject:tabID];
        }
    }

    if ([self widthNeededForTabIDs:visible] > budget + 0.5) {
        return [NSSet setWithSet:must];
    }

    for (NSUUID *tabID in [self candidateTabIDsSortedByLRUDescendingExcluding:must]) {
        NSMutableArray<NSUUID *> *trial = [visible mutableCopy];
        [trial addObject:tabID];
        if ([self widthNeededForTabIDs:trial] <= budget + 0.5) {
            [visible addObject:tabID];
        }
    }
    return [NSSet setWithArray:visible];
}

- (NSArray<NSUUID *> *)overflowTabIDsSortedByLRUAscendingForVisible:(NSSet<NSUUID *> *)visibleIDs {
    NSMutableArray<NSUUID *> *overflow = [NSMutableArray array];
    for (BrowserTabItemView *item in self.tabItems) {
        NSUUID *tabID = [self.tabItemIDs objectForKey:item];
        if (tabID && ![visibleIDs containsObject:tabID]) {
            [overflow addObject:tabID];
        }
    }
    [overflow sortUsingComparator:^NSComparisonResult(NSUUID *a, NSUUID *b) {
        NSTimeInterval ta = [self lastActiveTimestampForTabID:a];
        NSTimeInterval tb = [self lastActiveTimestampForTabID:b];
        if (ta < tb) {
            return NSOrderedAscending;
        }
        if (ta > tb) {
            return NSOrderedDescending;
        }
        NSUInteger ia = [self indexForTabID:a];
        NSUInteger ib = [self indexForTabID:b];
        if (ia < ib) {
            return NSOrderedAscending;
        }
        if (ia > ib) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return overflow;
}

- (NSString *)signatureForVisibleTabIDs:(NSSet<NSUUID *> *)visibleIDs {
    NSArray<NSUUID *> *sorted = [[visibleIDs allObjects] sortedArrayUsingSelector:@selector(compare:)];
    return [sorted componentsJoinedByString:@"|"];
}

- (CGFloat)assignedWidthForTabID:(NSUUID *)tabID inactiveBase:(CGFloat)baseW {
    if ([tabID isEqual:self.selectedTabID]) {
        CGFloat width = MIN(BrowserTabItemMaxWidth, baseW + BrowserTabActiveWidthBonus);
        return MAX(BrowserTabItemMinimalSelectedWidth, width);
    }
    CGFloat width = MIN(BrowserTabItemMaxWidth, baseW);
    return MAX(BrowserTabItemAbsoluteMinWidth, width);
}

- (CGFloat)layoutWidthForItem:(BrowserTabItemView *)item {
    NSUUID *tabID = [self.tabItemIDs objectForKey:item];
    if (!tabID) {
        return BrowserTabItemMinWidth;
    }
    CGFloat baseW = self.lastLaidOutInactiveTabWidth > 0 ? self.lastLaidOutInactiveTabWidth : BrowserTabItemMinWidth;
    return [self assignedWidthForTabID:tabID inactiveBase:baseW];
}

/// 在总宽 fullWidth 下 LRU 策略下最多能完整放下几个标签（可预留 overflow 按钮）
- (NSUInteger)maxVisibleTabCountForWidth:(CGFloat)fullWidth {
    if (fullWidth < 1.0 || self.tabItems.count == 0) {
        return 0;
    }

    NSSet<NSUUID *> *allVisible = [self visibleTabIDsForBudget:fullWidth];
    if (allVisible.count == self.tabItems.count) {
        return self.tabItems.count;
    }

    CGFloat tabsWidth = fullWidth - kOverflowButtonWidth - 2.0;
    if (tabsWidth < BrowserTabItemAbsoluteMinWidth) {
        return MAX((NSUInteger)1, [self mustVisibleTabIDs].count);
    }

    NSSet<NSUUID *> *visible = [self visibleTabIDsForBudget:tabsWidth];
    return MAX((NSUInteger)1, visible.count);
}

- (void)setOverflowVisible:(BOOL)visible {
    self.overflowButton.hidden = !visible;
}

/// 将 ▾ / + 贴到末个可见标签右侧（坐标相对标签条）
- (void)placeChromeButtonsAfterContentWidth:(CGFloat)contentW needsOverflow:(BOOL)needsOverflow {
    CGFloat clipLeading = [self tabsClipLeadingOffset];
    CGFloat buttonY = floor(([self effectiveStripHeight] - kAddButtonHeight) * 0.5);
    CGFloat cursor = clipLeading + MAX(contentW, 0);
    CGFloat chromeActionsWidth = [self chromeActionsReservedWidth];

    if (needsOverflow) {
        cursor += 2.0;
        self.overflowButton.frame = NSMakeRect(cursor, buttonY, kOverflowButtonWidth, kAddButtonHeight);
        cursor = NSMaxX(self.overflowButton.frame) + kChromeGap;
    } else {
        self.overflowButton.frame = NSZeroRect;
        cursor += 2.0;
    }

    // 不要紧贴右缘越界：预留 trailing 拖拽带与右侧 Chrome 动作区
    CGFloat maxAddX = NSWidth(self.bounds) - kTrailingDragWidth - chromeActionsWidth - kAddButtonWidth;
    if (cursor > maxAddX) {
        cursor = MAX(clipLeading, maxAddX);
    }
    self.addTabButton.frame = NSMakeRect(cursor, buttonY, kAddButtonWidth, kAddButtonHeight);
}

- (void)invalidateTabLayoutCache {
    self.lastLaidOutTabWidth = -1;
    self.lastLaidOutInactiveTabWidth = -1;
    self.lastLaidOutSelectedTabWidth = -1;
    self.lastLaidOutAvailableWidth = -1;
    self.lastLaidOutTabCount = NSNotFound;
    self.lastVisibleSignature = nil;
    self.lastPinnedCount = NSNotFound;
}

- (void)updateTabFrames {
    NSUInteger total = self.tabItems.count;
    // 为「+」与右侧 Chrome 动作区预留占位后，中间可供「标签 + 可选箭头」的宽度
    // leading(78)+4 + middle + 4 + add(24) + [gap+chromeActions] + trailing(16) = bounds.width
    CGFloat chromeActionsWidth = [self chromeActionsReservedWidth];
    CGFloat reservedChrome = [self tabsClipLeadingOffset] + kChromeGap + kAddButtonWidth
        + chromeActionsWidth + kTrailingDragWidth;
    CGFloat stripMiddle = NSWidth(self.bounds) - reservedChrome;

    if (total == 0 || stripMiddle < 1.0) {
        [self setOverflowVisible:NO];
        self.tabsContentView.frame = NSMakeRect(0, 0, 1, [self effectiveStripHeight]);
        [self.overflowTabIDs removeAllObjects];
        [self placeChromeButtonsAfterContentWidth:0 needsOverflow:NO];
        return;
    }

    NSUInteger visibleCount = [self maxVisibleTabCountForWidth:stripMiddle];
    BOOL needsOverflow = visibleCount < total;
    [self setOverflowVisible:needsOverflow];

    CGFloat available = needsOverflow
        ? MAX(stripMiddle - kOverflowButtonWidth - 2.0, BrowserTabItemAbsoluteMinWidth)
        : stripMiddle;

    NSSet<NSUUID *> *visibleIDs = [self visibleTabIDsForBudget:available];
    NSString *visibleSignature = [self signatureForVisibleTabIDs:visibleIDs];

    NSUInteger pinnedCount = [self pinnedTabCountInStrip];
    CGFloat spacingTotal = (visibleIDs.count > 1) ? (visibleIDs.count - 1) * kTabSpacing : 0;
    CGFloat baseW = visibleIDs.count > 0
        ? (available - BrowserTabActiveWidthBonus - spacingTotal) / (CGFloat)visibleIDs.count
        : BrowserTabItemAbsoluteMinWidth;
    baseW = MIN(BrowserTabItemMaxWidth, MAX(BrowserTabItemAbsoluteMinWidth, baseW));
    CGFloat selectedW = self.selectedTabID
        ? [self assignedWidthForTabID:self.selectedTabID inactiveBase:baseW]
        : baseW;

    // isFlipped：y=0 在顶。顶 inset（常态/精简均为 5pt），高度 = 条高 − inset，底边贴齐。
    CGFloat stripH = 0;
    CGFloat topInset = 0;
    CGFloat tabHeight = 0;
    [self tabVerticalMetricsWithStripHeight:&stripH topInset:&topInset tabHeight:&tabHeight];

    BOOL geometryChanged = fabs(baseW - self.lastLaidOutInactiveTabWidth) > 0.5
        || fabs(selectedW - self.lastLaidOutSelectedTabWidth) > 0.5
        || fabs(available - self.lastLaidOutAvailableWidth) > 0.5
        || total != self.lastLaidOutTabCount
        || ![visibleSignature isEqualToString:self.lastVisibleSignature]
        || needsOverflow != self.lastOverflowVisible
        || pinnedCount != self.lastPinnedCount
        || self.draggingItem != nil;

    if (geometryChanged) {
        [self.overflowTabIDs removeAllObjects];
        NSArray<NSUUID *> *overflowOrdered = [self overflowTabIDsSortedByLRUAscendingForVisible:visibleIDs];
        [self.overflowTabIDs addObjectsFromArray:overflowOrdered];

        CGFloat x = 0;
        for (NSUInteger i = 0; i < total; i++) {
            BrowserTabItemView *item = self.tabItems[i];
            NSUUID *tabID = [self.tabItemIDs objectForKey:item];
            BOOL visible = tabID && [visibleIDs containsObject:tabID];
            CGFloat tabWidth = tabID ? [self assignedWidthForTabID:tabID inactiveBase:baseW] : baseW;

            if (item == self.draggingItem) {
                item.hidden = NO;
                NSRect frame = item.frame;
                frame.origin.y = topInset;
                frame.size.width = tabWidth;
                frame.size.height = tabHeight;
                item.frame = frame;
                [item setTabHeight:tabHeight];
                [item applyAvailableWidth:tabWidth];
                if (visible) {
                    x += tabWidth + kTabSpacing;
                }
                continue;
            }

            item.hidden = !visible;
            if (visible) {
                item.frame = NSMakeRect(x, topInset, tabWidth, tabHeight);
                [item setTabHeight:tabHeight];
                [item applyAvailableWidth:tabWidth];
                x += tabWidth + kTabSpacing;
            } else {
                item.frame = NSZeroRect;
            }
        }

        CGFloat contentW = x > 0 ? x - kTabSpacing : 0;
        self.tabsContentView.frame = NSMakeRect(0, 0, MAX(contentW, 1), stripH);
        self.lastLaidOutInactiveTabWidth = baseW;
        self.lastLaidOutSelectedTabWidth = selectedW;
        self.lastLaidOutTabWidth = baseW;
        self.lastLaidOutAvailableWidth = available;
        self.lastLaidOutTabCount = total;
        self.lastVisibleSignature = visibleSignature;
        self.lastOverflowVisible = needsOverflow;
        self.lastPinnedCount = pinnedCount;
    }

    CGFloat contentWForChrome = 0;
    if (self.tabsContentView.frame.size.width > 1.0) {
        contentWForChrome = self.tabsContentView.frame.size.width;
    } else if (visibleIDs.count > 0) {
        contentWForChrome = available;
    }
    // 每次 layout 都重摆「+」，跟随末标签；不依赖 AL 定宽
    [self placeChromeButtonsAfterContentWidth:contentWForChrome needsOverflow:needsOverflow];
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

        BrowserTabOverflowMenuRowView *row =
            [[BrowserTabOverflowMenuRowView alloc] initWithFrame:NSZeroRect];
        row.titleText = title;
        row.pageURLString = itemView.pageURLString;
        row.checked = [tabID isEqual:self.selectedTabID];

        __weak typeof(self) weakSelf = self;
        NSUUID *capturedID = tabID;
        row.onSelect = ^{
            [weakSelf selectOverflowTabWithID:capturedID];
            [menu cancelTracking];
        };

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.view = row;
        item.representedObject = tabID;
        item.enabled = YES;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *overviewItem = [[NSMenuItem alloc] initWithTitle:@"显示全部标签…"
                                                          action:@selector(showAllTabsFromOverflow:)
                                                   keyEquivalent:@""];
    overviewItem.target = self;
    overviewItem.enabled = YES;
    [menu addItem:overviewItem];

    NSRect bounds = self.overflowButton.bounds;
    NSPoint point = NSMakePoint(NSMinX(bounds), NSMaxY(bounds) + 2.0);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:self.overflowButton];
}

- (void)showAllTabsFromOverflow:(id)sender {
    (void)sender;
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripViewDidRequestShowTabOverview:)]) {
        [delegate tabStripViewDidRequestShowTabOverview:self];
    }
}

- (void)selectOverflowTabWithID:(NSUUID *)tabID {
    if (![tabID isKindOfClass:[NSUUID class]]) {
        return;
    }
    [self.delegate tabStripView:self didSelectTabID:tabID];
}

- (void)selectOverflowTab:(NSMenuItem *)sender {
    NSUUID *tabID = sender.representedObject;
    [self selectOverflowTabWithID:tabID];
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
    __weak typeof(self) weakSelf = self;
    __weak BrowserTabItemView *weakItem = item;
    [self.dragGhost beginWithSourceView:item
                      grabPointInSource:grabInItem
                           afterCapture:^{
        typeof(self) strongSelf = weakSelf;
        BrowserTabItemView *strongItem = weakItem;
        if (!strongSelf || !strongItem || strongSelf.draggingItem != strongItem || strongSelf.dragEnding) {
            return;
        }
        strongItem.hidden = YES;
        [strongSelf layoutTabsExcludingDraggedItem:strongItem];
    }];
    NSPoint screenPoint = [self screenPointFromLocationInWindow:locationInWindow];
    [self.dragGhost moveToScreenPoint:screenPoint];
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

    NSUInteger best = low;
    CGFloat bestDistance = CGFLOAT_MAX;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < self.tabItems.count; i++) {
        BrowserTabItemView *candidate = self.tabItems[i];
        if (i >= low && i < high && candidate != item && !candidate.hidden) {
            CGFloat tabWidth = [self layoutWidthForItem:candidate];
            CGFloat slotCenter = x + tabWidth * 0.5;
            CGFloat distance = fabs(slotCenter - centerX);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
            }
            x += tabWidth + kTabSpacing;
        } else if (candidate != item && !candidate.hidden) {
            x += [self layoutWidthForItem:candidate] + kTabSpacing;
        } else if (candidate == item) {
            x += [self layoutWidthForItem:candidate] + kTabSpacing;
        }
    }
    return best;
}

- (void)layoutTabsExcludingDraggedItem:(BrowserTabItemView *)dragged {
    CGFloat topInset = 0;
    CGFloat tabHeight = 0;
    [self tabVerticalMetricsWithStripHeight:NULL topInset:&topInset tabHeight:&tabHeight];
    CGFloat x = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        if (item == dragged) {
            x += [self layoutWidthForItem:item] + kTabSpacing;
            continue;
        }
        if (!item.hidden) {
            CGFloat tabWidth = [self layoutWidthForItem:item];
            item.frame = NSMakeRect(x, topInset, tabWidth, tabHeight);
            [item setTabHeight:tabHeight];
            [item applyAvailableWidth:tabWidth];
            x += tabWidth + kTabSpacing;
        }
    }
}

- (void)layoutTabsCollapsingDraggedItem:(BrowserTabItemView *)dragged {
    CGFloat topInset = 0;
    CGFloat tabHeight = 0;
    [self tabVerticalMetricsWithStripHeight:NULL topInset:&topInset tabHeight:&tabHeight];
    CGFloat x = 0;
    for (BrowserTabItemView *item in self.tabItems) {
        if (item == dragged) {
            continue;
        }
        if (!item.hidden) {
            CGFloat tabWidth = [self layoutWidthForItem:item];
            item.frame = NSMakeRect(x, topInset, tabWidth, tabHeight);
            [item setTabHeight:tabHeight];
            [item applyAvailableWidth:tabWidth];
            x += tabWidth + kTabSpacing;
        }
    }
}

- (void)layoutTabsInsertingPlaceholderAtIndex:(NSUInteger)index {
    CGFloat topInset = 0;
    CGFloat tabHeight = 0;
    [self tabVerticalMetricsWithStripHeight:NULL topInset:&topInset tabHeight:&tabHeight];
    CGFloat placeholderWidth = self.lastLaidOutInactiveTabWidth > 0 ? self.lastLaidOutInactiveTabWidth : BrowserTabItemMinWidth;
    CGFloat x = 0;
    NSUInteger slot = 0;
    BOOL placedPlaceholder = NO;

    for (BrowserTabItemView *item in self.tabItems) {
        if (slot == index && !placedPlaceholder) {
            self.foreignPlaceholder.frame = NSMakeRect(x, topInset, placeholderWidth, tabHeight);
            self.foreignPlaceholder.hidden = NO;
            x += placeholderWidth + kTabSpacing;
            placedPlaceholder = YES;
        }
        if (!item.hidden) {
            CGFloat tabWidth = [self layoutWidthForItem:item];
            item.frame = NSMakeRect(x, topInset, tabWidth, tabHeight);
            [item setTabHeight:tabHeight];
            [item applyAvailableWidth:tabWidth];
            x += tabWidth + kTabSpacing;
        }
        slot++;
    }
    if (!placedPlaceholder) {
        self.foreignPlaceholder.frame = NSMakeRect(x, topInset, placeholderWidth, tabHeight);
        self.foreignPlaceholder.hidden = NO;
        x += placeholderWidth + kTabSpacing;
    }

    CGFloat contentW = MAX(x - (placedPlaceholder ? 0 : kTabSpacing), 1);
    NSRect contentFrame = self.tabsContentView.frame;
    contentFrame.size.width = MAX(contentW, NSWidth(self.tabsClipView.bounds));
    CGFloat stripH = 0;
    [self tabVerticalMetricsWithStripHeight:&stripH topInset:NULL tabHeight:NULL];
    contentFrame.size.height = stripH;
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
    CGFloat baseW = self.lastLaidOutInactiveTabWidth > 0 ? self.lastLaidOutInactiveTabWidth : BrowserTabItemMinWidth;
    NSUInteger best = low;
    CGFloat bestDistance = CGFLOAT_MAX;
    NSUInteger slotCount = high - low + 1;
    for (NSUInteger s = 0; s < slotCount; s++) {
        NSUInteger insertAt = low + s;
        CGFloat slotX = 0;
        for (NSUInteger i = 0; i < insertAt && i < self.tabItems.count; i++) {
            BrowserTabItemView *item = self.tabItems[i];
            if (!item.hidden) {
                slotX += [self layoutWidthForItem:item] + kTabSpacing;
            }
        }
        CGFloat slotWidth = baseW;
        if (insertAt < self.tabItems.count) {
            BrowserTabItemView *item = self.tabItems[insertAt];
            if (!item.hidden) {
                slotWidth = [self layoutWidthForItem:item];
            }
        }
        CGFloat slotCenter = slotX + slotWidth * 0.5;
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
    CGFloat topInset = 0;
    CGFloat tabHeight = 0;
    [self tabVerticalMetricsWithStripHeight:NULL topInset:&topInset tabHeight:&tabHeight];
    CGFloat x = index * (tabWidth + kTabSpacing);
    NSRect localInContent = NSMakeRect(x, topInset, size.width > 0 ? size.width : tabWidth,
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

- (BrowserTabItemView *)makeTabItemForTab:(BrowserTab *)tab selected:(BOOL)selected {
    BrowserTabItemView *item = [[BrowserTabItemView alloc] initWithFrame:NSZeroRect];
    item.translatesAutoresizingMaskIntoConstraints = YES;
    item.autoresizingMask = NSViewNotSizable;
    item.tabTitle = [tab displayTitle];
    item.pageURLString = BrowserTabPageURLString(tab);
    item.tabPinned = tab.isPinned;
    item.tabSelected = selected;
    item.tabToolTip = BrowserTabToolTipString(tab);

    __weak typeof(self) weakSelf = self;
    __weak BrowserTabItemView *weakItem = item;
    NSUUID *tabID = tab.tabID;
    item.onSelect = ^{
        [weakSelf.delegate tabStripView:weakSelf didSelectTabID:tabID];
    };
    item.onSelectGestureBegan = ^{
        id<BrowserTabStripViewDelegate> delegate = weakSelf.delegate;
        if ([delegate respondsToSelector:@selector(tabStripView:prepareToSelectTabID:)]) {
            [delegate tabStripView:weakSelf prepareToSelectTabID:tabID];
        }
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
    return item;
}

/// 新建标签页常见路径：末尾追加一个 tab，避免 O(n) 重建整条标签栏。
- (BOOL)tryAppendSingleTabFromTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    if (self.draggingItem || tabs.count != self.tabItems.count + 1) {
        return NO;
    }
    for (NSUInteger i = 0; i < self.tabItems.count; i++) {
        NSUUID *existingID = [self.tabItemIDs objectForKey:self.tabItems[i]];
        if (![existingID isEqual:tabs[i].tabID]) {
            return NO;
        }
    }

    BrowserTab *newTab = tabs.lastObject;
    BOOL selected = [newTab.tabID isEqual:selectedTabID];
    BrowserTabItemView *item = [self makeTabItemForTab:newTab selected:selected];
    [self.tabItems addObject:item];
    [self.tabsContentView addSubview:item];

    self.selectedTabID = selectedTabID;
    [self updateLayoutTabs:tabs];

    for (BrowserTabItemView *tabItem in self.tabItems) {
        NSUUID *tabID = [self.tabItemIDs objectForKey:tabItem];
        BOOL isSelected = tabID != nil && [tabID isEqual:selectedTabID];
        if (tabItem.tabSelected != isSelected) {
            tabItem.tabSelected = isSelected;
        }
    }

    [self invalidateTabLayoutCache];
    [self setNeedsLayout:YES];
    return YES;
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
    [self updateLayoutTabs:tabs];

    for (BrowserTab *tab in tabs) {
        BOOL selected = [tab.tabID isEqual:selectedTabID];
        BrowserTabItemView *item = [self makeTabItemForTab:tab selected:selected];
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
        if ([self tryAppendSingleTabFromTabs:tabs selectedTabID:selectedTabID]) {
            return;
        }
        [self reloadWithTabs:tabs selectedTabID:selectedTabID];
        return;
    }

    BOOL selectionChanged = (self.selectedTabID != selectedTabID)
        && ![self.selectedTabID isEqual:selectedTabID];
    BOOL pinOrOrderChanged = NO;
    self.selectedTabID = selectedTabID;
    [self updateLayoutTabs:tabs];

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

        NSString *toolTip = BrowserTabToolTipString(tab);
        if (item.tabToolTip != toolTip && ![item.tabToolTip isEqualToString:toolTip]) {
            item.tabToolTip = toolTip;
        }

        NSString *pageURL = BrowserTabPageURLString(tab);
        if (item.pageURLString != pageURL && ![item.pageURLString isEqualToString:pageURL]) {
            item.pageURLString = pageURL;
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
