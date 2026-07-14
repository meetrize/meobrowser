#import "BrowserLaunchpadView.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutCellView.h"
#import "BrowserShortcutEditorSheet.h"
#import "BrowserShortcutFolderOverlay.h"
#import "BrowserLaunchpadAppearance.h"
#import "BrowserLaunchpadAppearancePanel.h"
#import "BrowserWallpaperStore.h"
#import <QuartzCore/QuartzCore.h>

static NSPasteboardType const kBrowserShortcutDragType = @"com.meobrowser.shortcut-item-id";

@class BrowserLaunchpadView;

@interface BrowserLaunchpadView (ContextMenu)
- (NSMenu *)menuForCollectionEvent:(NSEvent *)event;
@end

@interface BrowserLaunchpadView (HostHelpers)
@property (nonatomic, readonly, getter=isDraggingShortcut) BOOL draggingShortcut;
- (BOOL)launchpadBeginDraggingShortcut:(BrowserShortcutItem *)shortcut
                              fromView:(NSView *)view
                                 event:(NSEvent *)event;
- (NSDragOperation)launchpadHandleDraggingUpdated:(id<NSDraggingInfo>)sender;
- (void)launchpadHandleDraggingExited;
- (BOOL)launchpadHandlePerformDragOperation:(id<NSDraggingInfo>)sender;
- (NSInteger)launchpadDraggingSourceIndex;
- (NSInteger)launchpadDropInsertIndex;
@end

/// 拖拽时重排：源图标隐去，在插入点腾出完整空位，后续图标后移。
@interface BrowserLaunchpadFlowLayout : NSCollectionViewFlowLayout
@property (nonatomic, weak) BrowserLaunchpadView *launchpadHost;
- (NSRect)launchpadBaseFrameForItemAtIndex:(NSInteger)index;
- (NSRect)launchpadPlaceholderFrameForInsertIndex:(NSInteger)insertIndex
                                     sourceIndex:(NSInteger)sourceIndex;
@end

@implementation BrowserLaunchpadFlowLayout

- (NSInteger)launchpadSourceIndex {
    return self.launchpadHost ? [self.launchpadHost launchpadDraggingSourceIndex] : NSNotFound;
}

- (NSInteger)launchpadInsertIndex {
    return self.launchpadHost ? [self.launchpadHost launchpadDropInsertIndex] : NSNotFound;
}

- (NSInteger)launchpadHoleVisualSlotForInsert:(NSInteger)insert source:(NSInteger)source {
    if (insert == NSNotFound) {
        return NSNotFound;
    }
    // 夹外拖入：源不在顶层列表，空位就是 insert 本身。
    if (source == NSNotFound) {
        return insert;
    }
    return (insert <= source) ? insert : (insert - 1);
}

- (BOOL)launchpadNeedsReflow {
    return [self launchpadInsertIndex] != NSNotFound || [self launchpadSourceIndex] != NSNotFound;
}

- (NSInteger)launchpadVisualSlotForItemIndex:(NSInteger)itemIndex {
    NSInteger source = [self launchpadSourceIndex];
    NSInteger insert = [self launchpadInsertIndex];
    NSInteger hole = [self launchpadHoleVisualSlotForInsert:insert source:source];
    NSInteger count = [self.collectionView numberOfItemsInSection:0];

    // 从文件夹拖入：在 insert 处开孔，其后项整体后移一格。
    if (source == NSNotFound) {
        if (hole == NSNotFound) {
            return itemIndex;
        }
        if (itemIndex >= hole) {
            return itemIndex + 1;
        }
        return itemIndex;
    }

    if (hole == NSNotFound) {
        // 无有效插入位：收起源位置，后面的往前填。
        if (itemIndex == source) {
            return source;
        }
        if (itemIndex > source) {
            return itemIndex - 1;
        }
        return itemIndex;
    }

    NSInteger slot = 0;
    for (NSInteger i = 0; i < count; i++) {
        if (i == source) {
            continue;
        }
        if (slot == hole) {
            slot++;
        }
        if (i == itemIndex) {
            return slot;
        }
        slot++;
    }
    return itemIndex;
}

- (NSRect)launchpadBaseFrameForItemAtIndex:(NSInteger)index {
    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    if (index >= 0 && index < count) {
        NSCollectionViewLayoutAttributes *attrs =
            [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
        return attrs ? attrs.frame : NSZeroRect;
    }
    // 挤位后多出的末尾槽位（外部插入时最后一格可能落到 count）。
    if (index == count && count > 0) {
        NSRect last = [self launchpadBaseFrameForItemAtIndex:count - 1];
        if (NSIsEmptyRect(last)) {
            return NSZeroRect;
        }
        CGFloat nextX = NSMaxX(last) + self.minimumInteritemSpacing;
        CGFloat maxX = NSWidth(self.collectionView.bounds) - self.sectionInset.right - self.itemSize.width;
        NSRect frame = last;
        frame.size = self.itemSize;
        if (nextX <= maxX + 0.5) {
            frame.origin.x = nextX;
        } else {
            // 与主网格其它追加占位一致（AppKit collection view 坐标系）。
            frame.origin.x = self.sectionInset.left;
            frame.origin.y -= (self.itemSize.height + self.minimumLineSpacing);
        }
        return frame;
    }
    return NSZeroRect;
}

- (NSRect)launchpadPlaceholderFrameForInsertIndex:(NSInteger)insertIndex
                                     sourceIndex:(NSInteger)sourceIndex {
    NSInteger hole = [self launchpadHoleVisualSlotForInsert:insertIndex source:sourceIndex];
    if (hole == NSNotFound) {
        return NSZeroRect;
    }
    return [self launchpadBaseFrameForItemAtIndex:hole];
}

- (void)launchpadApplyReflowToAttributes:(NSCollectionViewLayoutAttributes *)attributes {
    if (!attributes || attributes.representedElementCategory != NSCollectionElementCategoryItem) {
        return;
    }
    if (![self launchpadNeedsReflow]) {
        return;
    }
    NSInteger source = [self launchpadSourceIndex];
    NSInteger itemIndex = attributes.indexPath.item;
    if (source != NSNotFound && itemIndex == source) {
        // 拖起的源图标本身由拖影表示，格子让给占位或收起。
        NSInteger insert = [self launchpadInsertIndex];
        NSInteger hole = [self launchpadHoleVisualSlotForInsert:insert source:source];
        NSInteger slot = (hole != NSNotFound) ? hole : source;
        NSRect frame = [self launchpadBaseFrameForItemAtIndex:slot];
        if (!NSIsEmptyRect(frame)) {
            attributes.frame = frame;
        }
        attributes.alpha = 0.0;
        attributes.zIndex = -1;
        return;
    }

    NSInteger visualSlot = [self launchpadVisualSlotForItemIndex:itemIndex];
    NSRect frame = [self launchpadBaseFrameForItemAtIndex:visualSlot];
    if (!NSIsEmptyRect(frame)) {
        attributes.frame = frame;
    }
}

- (NSSize)collectionViewContentSize {
    NSSize size = [super collectionViewContentSize];
    if (![self launchpadNeedsReflow]) {
        return size;
    }
    // 外部插入时最后一格可能多出一行，扩大 contentSize 以免裁切。
    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    NSRect trailing = [self launchpadBaseFrameForItemAtIndex:count];
    if (!NSIsEmptyRect(trailing)) {
        size.width = MAX(size.width, NSMaxX(trailing) + self.sectionInset.right);
        size.height = MAX(size.height, NSMaxY(trailing) + self.sectionInset.bottom);
    }
    return size;
}

- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect {
    NSArray<NSCollectionViewLayoutAttributes *> *base = [super layoutAttributesForElementsInRect:rect];
    if (![self launchpadNeedsReflow]) {
        return base;
    }
    // 重排后 frame 可能移出原 rect，放宽查询以免漏掉正在动画的 cell。
    NSRect query = NSInsetRect(rect, -self.itemSize.width * 2.0, -self.itemSize.height * 2.0);
    NSArray<NSCollectionViewLayoutAttributes *> *wide = [super layoutAttributesForElementsInRect:query];
    NSMutableArray<NSCollectionViewLayoutAttributes *> *result = [NSMutableArray arrayWithCapacity:wide.count];
    NSMutableSet<NSIndexPath *> *seen = [NSMutableSet set];
    for (NSCollectionViewLayoutAttributes *attrs in wide) {
        NSCollectionViewLayoutAttributes *copy = [attrs copy];
        [self launchpadApplyReflowToAttributes:copy];
        if (copy.indexPath) {
            [seen addObject:copy.indexPath];
        }
        if (NSIntersectsRect(rect, copy.frame) || copy.alpha < 0.01) {
            [result addObject:copy];
        }
    }
    // 确保所有 item 都有 attributes（否则部分 cell 不更新）。
    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    for (NSInteger i = 0; i < count; i++) {
        NSIndexPath *path = [NSIndexPath indexPathForItem:i inSection:0];
        if ([seen containsObject:path]) {
            continue;
        }
        NSCollectionViewLayoutAttributes *attrs = [self layoutAttributesForItemAtIndexPath:path];
        if (attrs && (NSIntersectsRect(rect, attrs.frame) || attrs.alpha < 0.01)) {
            [result addObject:attrs];
        }
    }
    return result;
}

- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSCollectionViewLayoutAttributes *attrs = [[super layoutAttributesForItemAtIndexPath:indexPath] copy];
    [self launchpadApplyReflowToAttributes:attrs];
    return attrs;
}

@end

@interface BrowserLaunchpadCollectionView : NSCollectionView
@property (nonatomic, weak) BrowserLaunchpadView *launchpadHost;
- (nullable NSIndexPath *)launchpadLayoutIndexPathAtPoint:(NSPoint)point;
@end

@implementation BrowserLaunchpadCollectionView

- (nullable NSIndexPath *)launchpadLayoutIndexPathAtPoint:(NSPoint)point {
    NSInteger count = [self numberOfItemsInSection:0];
    for (NSInteger i = 0; i < count; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
        NSCollectionViewLayoutAttributes *attributes =
            [self.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
        if (attributes && NSPointInRect(point, attributes.frame)) {
            return indexPath;
        }
    }
    return nil;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.launchpadHost) {
        return [self.launchpadHost menuForCollectionEvent:event];
    }
    return [super menuForEvent:event];
}

#pragma mark - NSDraggingDestination（绕过默认间隙拒绝）

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self.launchpadHost launchpadHandleDraggingUpdated:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self.launchpadHost launchpadHandleDraggingUpdated:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    (void)sender;
    [self.launchpadHost launchpadHandleDraggingExited];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    (void)sender;
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.launchpadHost launchpadHandlePerformDragOperation:sender];
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
    (void)sender;
    [self.launchpadHost launchpadHandleDraggingExited];
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

@end

@interface BrowserLaunchpadView () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSPopoverDelegate, BrowserShortcutFolderOverlayDelegate, NSDraggingSource>
@property (nonatomic, strong) NSView *wallpaperView;
@property (nonatomic, strong) NSView *scrimView;
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, assign) BOOL wallpaperAcquired;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) BrowserLaunchpadCollectionView *collectionView;
@property (nonatomic, strong) BrowserLaunchpadFlowLayout *flowLayout;
@property (nonatomic, strong) NSMutableArray<BrowserShortcutItem *> *mutableShortcuts;
@property (nonatomic, copy) NSArray<BrowserShortcutItem *> *displayShortcuts;
@property (nonatomic, strong, nullable) id escapeMonitor;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@property (nonatomic, strong) NSButton *settingsButton;
@property (nonatomic, strong, nullable) NSPopover *appearancePopover;
@property (nonatomic, strong) BrowserLaunchpadAppearancePanel *appearancePanel;
@property (nonatomic, assign) CGFloat cachedIconSize;
@property (nonatomic, assign) CGFloat cachedHorizontalSpacing;
@property (nonatomic, assign) CGFloat cachedVerticalSpacing;
@property (nonatomic, strong) BrowserShortcutFolderOverlay *folderOverlay;
@property (nonatomic, copy, nullable) NSString *mergeTargetItemID;
@property (nonatomic, copy, nullable) NSString *draggingItemID;
@property (nonatomic, strong) NSView *dropPlaceholderView;
@property (nonatomic, assign) NSInteger dropPlaceholderIndex; // DropBefore 插入下标；NSNotFound 表示隐藏
@property (nonatomic, assign) BOOL dropDidCommit;
@end

@implementation BrowserLaunchpadView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _mutableShortcuts = [[NSMutableArray alloc] init];
        _displayShortcuts = @[];
        BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
        _cachedIconSize = appearance.iconSize;
        _cachedHorizontalSpacing = appearance.horizontalSpacing;
        _cachedVerticalSpacing = appearance.verticalSpacing;
        [self setupViews];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appearanceDidChange:)
                                                     name:BrowserLaunchpadAppearanceDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(wallpaperDidChange:)
                                                     name:BrowserWallpaperDidChangeNotification
                                                   object:nil];
        [self refreshWallpaperPresentation];
    }
    return self;
}

- (void)dealloc {
    [self releaseWallpaperIfNeeded];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeEscapeMonitor];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window != nil && !self.hidden) {
        [self acquireWallpaperIfNeeded];
        [self refreshWallpaperPresentation];
    } else {
        [self releaseWallpaperIfNeeded];
    }
}

- (void)setHidden:(BOOL)hidden {
    BOOL wasHidden = self.hidden;
    [super setHidden:hidden];
    if (wasHidden == hidden) {
        return;
    }
    if (hidden) {
        [self releaseWallpaperIfNeeded];
    } else if (self.window != nil) {
        [self acquireWallpaperIfNeeded];
        [self refreshWallpaperPresentation];
    }
}

- (void)setupViews {
    self.wantsLayer = YES;
    // 壁纸 aspectFill 会超出 layer bounds；必须裁剪，避免盖住标签栏/地址栏。
    self.clipsToBounds = YES;

    _wallpaperView = [[NSView alloc] initWithFrame:NSZeroRect];
    _wallpaperView.wantsLayer = YES;
    _wallpaperView.layer.contentsGravity = kCAGravityResizeAspectFill;
    _wallpaperView.layer.masksToBounds = YES;
    _wallpaperView.translatesAutoresizingMaskIntoConstraints = NO;
    _wallpaperView.hidden = YES;
    [self addSubview:_wallpaperView];

    _scrimView = [[NSView alloc] initWithFrame:NSZeroRect];
    _scrimView.wantsLayer = YES;
    _scrimView.layer.masksToBounds = YES;
    _scrimView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrimView.hidden = YES;
    [self addSubview:_scrimView];

    _effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    _effectView.material = NSVisualEffectMaterialContentBackground;
    _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _effectView.state = NSVisualEffectStateActive;
    _effectView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_effectView];

    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:self.cachedIconSize];
    _flowLayout = [[BrowserLaunchpadFlowLayout alloc] init];
    _flowLayout.launchpadHost = self;
    _flowLayout.itemSize = NSMakeSize(cellWidth, [BrowserLaunchpadAppearance cellHeightForIconSize:self.cachedIconSize]);
    _flowLayout.minimumInteritemSpacing = self.cachedHorizontalSpacing;
    _flowLayout.minimumLineSpacing = self.cachedVerticalSpacing;
    _flowLayout.sectionInset = NSEdgeInsetsMake(self.cachedVerticalSpacing,
                                                 self.cachedHorizontalSpacing,
                                                 self.cachedVerticalSpacing,
                                                 self.cachedHorizontalSpacing);
    _flowLayout.scrollDirection = NSCollectionViewScrollDirectionVertical;

    _collectionView = [[BrowserLaunchpadCollectionView alloc] initWithFrame:NSZeroRect];
    _collectionView.launchpadHost = self;
    _collectionView.collectionViewLayout = _flowLayout;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.backgroundColors = @[[NSColor clearColor]];
    // 点击/拖拽由 cell 自行处理，无需 selection。
    _collectionView.selectable = NO;
    _collectionView.clipsToBounds = NO;
    [_collectionView registerClass:[BrowserShortcutCellView class] forItemWithIdentifier:@"ShortcutCell"];
    // destination 接收落点；拖拽发起在 cell → launchpadBeginDraggingShortcut。
    [_collectionView registerForDraggedTypes:@[kBrowserShortcutDragType]];

    _dropPlaceholderIndex = NSNotFound;
    _dropPlaceholderView = [[NSView alloc] initWithFrame:NSZeroRect];
    _dropPlaceholderView.wantsLayer = YES;
    _dropPlaceholderView.hidden = YES;
    _dropPlaceholderView.layer.masksToBounds = YES;
    CGFloat placeholderRadius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:self.cachedIconSize];
    _dropPlaceholderView.layer.cornerRadius = placeholderRadius;
    if (@available(macOS 10.14, *)) {
        _dropPlaceholderView.layer.backgroundColor =
            [NSColor.controlAccentColor colorWithAlphaComponent:0.14].CGColor;
    } else {
        _dropPlaceholderView.layer.backgroundColor =
            [[NSColor selectedControlColor] colorWithAlphaComponent:0.20].CGColor;
    }
    // 虚线边框：用 shape layer 叠一层，形状与图标圆角正方形一致
    CAShapeLayer *dash = [CAShapeLayer layer];
    dash.fillColor = nil;
    dash.strokeColor = NSColor.controlAccentColor.CGColor;
    dash.lineWidth = 2.0;
    dash.lineDashPattern = @[ @6, @4 ];
    dash.name = @"launchpad.dropPlaceholder.dash";
    [_dropPlaceholderView.layer addSublayer:dash];
    [_collectionView addSubview:_dropPlaceholderView];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.documentView = _collectionView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    _scrollView.verticalScrollElasticity = NSScrollElasticityAllowed;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scrollView];

    _settingsButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleAppearancePopover:)];
    _settingsButton.bezelStyle = NSBezelStyleToolbar;
    _settingsButton.bordered = NO;
    _settingsButton.toolTip = @"外观与背景";
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        NSImage *gear = [NSImage imageWithSystemSymbolName:@"gearshape"
                                  accessibilityDescription:@"外观与背景"];
        gear.template = YES;
        gear.size = NSMakeSize(16, 16);
        _settingsButton.image = gear;
        _settingsButton.imagePosition = NSImageOnly;
    } else {
        _settingsButton.title = @"⚙";
        _settingsButton.font = [NSFont systemFontOfSize:16];
    }
    if (@available(macOS 10.14, *)) {
        _settingsButton.contentTintColor = NSColor.secondaryLabelColor;
    }
    [self addSubview:_settingsButton];

    _folderOverlay = [[BrowserShortcutFolderOverlay alloc] initWithFrame:NSZeroRect];
    _folderOverlay.delegate = self;

    [NSLayoutConstraint activateConstraints:@[
        [_wallpaperView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_wallpaperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_wallpaperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_wallpaperView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_scrimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_effectView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_effectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_effectView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_effectView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_settingsButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_settingsButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
        [_settingsButton.widthAnchor constraintEqualToConstant:28],
        [_settingsButton.heightAnchor constraintEqualToConstant:28],
    ]];
}

- (void)acquireWallpaperIfNeeded {
    if (self.wallpaperAcquired) {
        return;
    }
    [[BrowserWallpaperStore sharedStore] acquireDisplayImage];
    self.wallpaperAcquired = YES;
}

- (void)releaseWallpaperIfNeeded {
    if (!self.wallpaperAcquired) {
        return;
    }
    [[BrowserWallpaperStore sharedStore] releaseDisplayImage];
    self.wallpaperAcquired = NO;
    self.wallpaperView.layer.contents = nil;
}

- (void)wallpaperDidChange:(NSNotification *)notification {
    (void)notification;
    if (!self.hidden && self.window != nil) {
        [self acquireWallpaperIfNeeded];
    }
    [self refreshWallpaperPresentation];
}

- (void)refreshWallpaperPresentation {
    BrowserWallpaperStore *store = [BrowserWallpaperStore sharedStore];
    BOOL showWallpaper = store.isWallpaperEnabled && store.displayImage != nil;
    if (showWallpaper) {
        self.wallpaperView.layer.contents = store.displayImage;
        self.wallpaperView.hidden = NO;
        self.scrimView.hidden = NO;
        self.scrimView.layer.backgroundColor =
            [[NSColor blackColor] colorWithAlphaComponent:store.scrimAlpha].CGColor;
        self.effectView.hidden = YES;
    } else {
        self.wallpaperView.layer.contents = nil;
        self.wallpaperView.hidden = YES;
        self.scrimView.hidden = YES;
        self.effectView.hidden = NO;
    }
}

- (void)layout {
    [super layout];
    [self updateCollectionViewDocumentSize];
}

- (void)appearanceDidChange:(NSNotification *)notification {
    (void)notification;
    BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
    self.cachedIconSize = appearance.iconSize;
    self.cachedHorizontalSpacing = appearance.horizontalSpacing;
    self.cachedVerticalSpacing = appearance.verticalSpacing;
    [self applyAppearanceToVisibleCells];
    self.lastLayoutWidth = 0;
    [self setNeedsLayout:YES];
}

- (void)applyAppearanceToVisibleCells {
    CGFloat iconSize = self.cachedIconSize;
    for (NSCollectionViewItem *item in self.collectionView.visibleItems) {
        if ([item isKindOfClass:[BrowserShortcutCellView class]]) {
            [(BrowserShortcutCellView *)item applyIconSize:iconSize];
        }
    }
}

- (void)updateGridLayoutForWidth:(CGFloat)width {
    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:self.cachedIconSize];
    CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:self.cachedIconSize];
    CGFloat hSpacing = self.cachedHorizontalSpacing;
    CGFloat vSpacing = self.cachedVerticalSpacing;

    NSInteger columns = (NSInteger)floor((width - hSpacing) / (cellWidth + hSpacing));
    columns = MAX((NSInteger)1, columns);
    CGFloat usedWidth = columns * cellWidth + (columns - 1) * hSpacing;
    CGFloat sideInset = MAX(hSpacing, (width - usedWidth) / 2.0);

    self.flowLayout.itemSize = NSMakeSize(cellWidth, cellHeight);
    self.flowLayout.minimumInteritemSpacing = hSpacing;
    self.flowLayout.minimumLineSpacing = vSpacing;
    self.flowLayout.sectionInset = NSEdgeInsetsMake(vSpacing, sideInset, vSpacing, sideInset);
}

- (void)updateCollectionViewDocumentSize {
    NSClipView *clipView = self.scrollView.contentView;
    CGFloat width = NSWidth(clipView.bounds);
    if (width <= 0) {
        return;
    }

    BOOL widthChanged = fabs(width - self.lastLayoutWidth) > 0.5;
    if (widthChanged) {
        self.lastLayoutWidth = width;
        [self updateGridLayoutForWidth:width];
        [self.flowLayout invalidateLayout];
    }

    [self.collectionView layoutSubtreeIfNeeded];
    NSSize contentSize = self.flowLayout.collectionViewContentSize;
    CGFloat height = MAX(contentSize.height, NSHeight(clipView.bounds));
    NSRect frame = NSMakeRect(0, 0, width, height);
    if (!NSEqualRects(self.collectionView.frame, frame)) {
        self.collectionView.frame = frame;
        if (!widthChanged) {
            [self.flowLayout invalidateLayout];
            [self.collectionView layoutSubtreeIfNeeded];
            contentSize = self.flowLayout.collectionViewContentSize;
            height = MAX(contentSize.height, NSHeight(clipView.bounds));
            self.collectionView.frame = NSMakeRect(0, 0, width, height);
        }
    }
}

- (void)reloadShortcuts {
    [self.mutableShortcuts setArray:[BrowserShortcutStore loadShortcuts]];
    [self refreshDisplayShortcuts];
    [self reloadCollectionView];
    if (self.folderOverlay.folder) {
        BrowserShortcutItem *folder = [BrowserShortcutStore shortcutWithID:self.folderOverlay.folder.itemID
                                                               inShortcuts:self.mutableShortcuts];
        if (folder && folder.isFolder) {
            [self.folderOverlay reloadChildren:[BrowserShortcutStore childrenOfFolderID:folder.itemID
                                                                            inShortcuts:self.mutableShortcuts]];
        } else {
            [self dismissFolderOverlayAnimated:NO];
        }
    }
}

- (void)refreshDisplayShortcuts {
    self.displayShortcuts = [BrowserShortcutStore topLevelShortcuts:self.mutableShortcuts];
}

- (void)reloadCollectionView {
    [self refreshDisplayShortcuts];
    [self.collectionView reloadData];
    self.lastLayoutWidth = 0;
    [self setNeedsLayout:YES];
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

#pragma mark - Appearance Popover

- (void)toggleAppearancePopover:(id)sender {
    (void)sender;
    if (self.appearancePopover.isShown) {
        [self.appearancePopover close];
        return;
    }

    NSSize panelSize = [BrowserLaunchpadAppearancePanel preferredPanelSize];
    BrowserLaunchpadAppearancePanel *panel =
        [[BrowserLaunchpadAppearancePanel alloc] initWithFrame:NSMakeRect(0, 0, panelSize.width, panelSize.height)];
    [panel reloadFromAppearance];
    self.appearancePanel = panel;

    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = panel;
    controller.preferredContentSize = panelSize;

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = controller;
    popover.contentSize = panelSize;
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.delegate = self;
    self.appearancePopover = popover;
    [popover showRelativeToRect:self.settingsButton.bounds
                         ofView:self.settingsButton
                  preferredEdge:NSRectEdgeMinY];
}

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
    self.appearancePopover = nil;
}

- (void)showAppearanceSettings {
    if (!self.appearancePopover.isShown) {
        [self toggleAppearancePopover:self.settingsButton];
    }
}

#pragma mark - Keyboard

- (void)installEscapeMonitor {
    if (self.escapeMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.escapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                               handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53 && weakSelf.folderOverlay.folder) {
            [weakSelf dismissFolderOverlayAnimated:YES];
            return nil;
        }
        return event;
    }];
}

- (void)removeEscapeMonitor {
    if (self.escapeMonitor) {
        [NSEvent removeMonitor:self.escapeMonitor];
        self.escapeMonitor = nil;
    }
}

- (BOOL)isDraggingShortcut {
    return self.draggingItemID.length > 0;
}

/// 单元格槽位内、与真实图标同尺寸的圆角正方形（不含标题区）。
- (NSRect)launchpadIconSlotFrameInCellFrame:(NSRect)cellFrame {
    CGFloat iconSize = self.cachedIconSize;
    CGFloat shadowInset = [BrowserLaunchpadAppearance iconShadowInsetForIconSize:iconSize];
    CGFloat x = NSMinX(cellFrame) + (NSWidth(cellFrame) - iconSize) * 0.5;
    CGFloat y = NSMinY(cellFrame) + shadowInset;
    return NSMakeRect(x, y, iconSize, iconSize);
}

- (BOOL)launchpadBeginDraggingShortcut:(BrowserShortcutItem *)shortcut
                              fromView:(NSView *)view
                                 event:(NSEvent *)event {
    if (!shortcut || shortcut.itemID.length == 0 || !view || !event) {
        return NO;
    }
    if (self.folderOverlay.folder) {
        return NO;
    }

    self.draggingItemID = shortcut.itemID;
    self.dropDidCommit = NO;
    [self clearMergeState];
    self.dropPlaceholderIndex = NSNotFound;
    self.dropPlaceholderView.hidden = YES;
    // 立即收起源图标占位，后续插入时再挤开空位。
    [self invalidateLaunchpadReflowAnimated:YES];

    NSPasteboardItem *pasteboardItem = [[NSPasteboardItem alloc] init];
    [pasteboardItem setString:shortcut.itemID forType:kBrowserShortcutDragType];

    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboardItem];
    // 半透明图标影子；frame 必须在 beginDraggingSession 的 view（collectionView）坐标系内。
    NSImage *image = [BrowserShortcutCellView draggingProxyImageFromContentView:view alpha:0.72];
    NSRect dragFrame = [BrowserShortcutCellView draggingProxyFrameFromContentView:view
                                                                           inView:self.collectionView];
    if (!image || NSIsEmptyRect(dragFrame)) {
        NSRect bounds = view.bounds;
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:bounds];
        if (rep) {
            [view cacheDisplayInRect:bounds toBitmapImageRep:rep];
            image = [[NSImage alloc] initWithSize:bounds.size];
            [image addRepresentation:rep];
        }
        dragFrame = [view convertRect:bounds toView:self.collectionView];
    }
    [draggingItem setDraggingFrame:dragFrame contents:image];

    // source 用 launchpad 自身，便可收到 movedToPoint 持续更新占位符。
    NSDraggingSession *session = [self.collectionView beginDraggingSessionWithItems:@[draggingItem]
                                                                              event:event
                                                                             source:self];
    if (!session) {
        [self launchpadDraggingSessionDidEnd];
        return NO;
    }
    // 松手后不要把拖影弹回原位；排序成功时格子已就位，弹回会造成「收回」错觉。
    session.animatesToStartingPositionsOnCancelOrFail = NO;
    return YES;
}

- (void)launchpadDraggingSessionDidEnd {
    self.draggingItemID = nil;
    self.dropDidCommit = NO;
    [self clearMergeState];
    self.dropPlaceholderIndex = NSNotFound;
    self.dropPlaceholderView.hidden = YES;
    [self invalidateLaunchpadReflowAnimated:YES];
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session;
    if (context == NSDraggingContextOutsideApplication) {
        return NSDragOperationNone;
    }
    return NSDragOperationMove;
}

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
    (void)session;
    if (self.draggingItemID.length == 0 || !self.window) {
        return;
    }
    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    NSPoint location = [self.collectionView convertPoint:windowPoint fromView:nil];
    BrowserShortcutItem *source = [BrowserShortcutStore shortcutWithID:self.draggingItemID
                                                           inShortcuts:self.mutableShortcuts];
    if (source) {
        [self launchpadUpdateDropFeedbackAtPoint:location source:source];
    }
}

- (void)draggingSession:(NSDraggingSession *)session
           endedAtPoint:(NSPoint)screenPoint
              operation:(NSDragOperation)operation {
    (void)session;
    (void)operation;
    // destination 常不回调 performDragOperation：松手时若仍在网格内则按占位符提交。
    if (!self.dropDidCommit && self.draggingItemID.length > 0) {
        [self launchpadCommitDropAtScreenPoint:screenPoint];
    }
    [self launchpadDraggingSessionDidEnd];
}

#pragma mark - Helpers

- (NSInteger)totalItemCount {
    // 末尾常驻「添加」cell
    return (NSInteger)self.displayShortcuts.count + 1;
}

- (BOOL)isAddIndexPath:(NSIndexPath *)indexPath {
    return indexPath.item == (NSInteger)self.displayShortcuts.count;
}

- (nullable BrowserShortcutItem *)shortcutAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isAddIndexPath:indexPath]) {
        return nil;
    }
    if (indexPath.item < 0 || indexPath.item >= (NSInteger)self.displayShortcuts.count) {
        return nil;
    }
    return self.displayShortcuts[(NSUInteger)indexPath.item];
}

- (void)openShortcut:(BrowserShortcutItem *)shortcut inNewTab:(BOOL)inNewTab {
    if (shortcut.isFolder) {
        [self presentFolder:shortcut];
        return;
    }
    NSURL *url = [NSURL URLWithString:shortcut.urlString];
    if (!url || !self.delegate) {
        return;
    }
    if (inNewTab) {
        [self.delegate launchpadView:self openURLInNewTab:url];
    } else {
        [self.delegate launchpadView:self openURL:url];
    }
}

- (void)presentFolder:(BrowserShortcutItem *)folder {
    if (!folder.isFolder) {
        return;
    }
    NSArray<BrowserShortcutItem *> *children =
        [BrowserShortcutStore childrenOfFolderID:folder.itemID inShortcuts:self.mutableShortcuts];

    NSRect anchor = NSMakeRect(NSMidX(self.bounds) - 20, NSMidY(self.bounds) - 20, 40, 40);
    for (NSUInteger i = 0; i < self.displayShortcuts.count; i++) {
        if ([self.displayShortcuts[i].itemID isEqualToString:folder.itemID]) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:(NSInteger)i inSection:0];
            NSCollectionViewItem *item = [self.collectionView itemAtIndexPath:path];
            if (item.view) {
                anchor = [self convertRect:item.view.bounds fromView:item.view];
            }
            break;
        }
    }

    [self installEscapeMonitor];
    [self.folderOverlay presentFolder:folder
                             children:children
                       fromAnchorRect:anchor
                               inView:self
                             animated:YES];
}

- (void)dismissFolderOverlayAnimated:(BOOL)animated {
    __weak typeof(self) weakSelf = self;
    [self.folderOverlay dismissAnimated:animated completion:^{
        [weakSelf removeEscapeMonitor];
    }];
}

- (void)presentAddShortcutSheet {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BrowserShortcutEditorSheet presentAddingShortcutOnWindow:window completion:^(BrowserShortcutItem *item) {
        if (!item) {
            return;
        }
        [BrowserShortcutStore addShortcutWithTitle:item.title
                                         urlString:item.urlString
                                     iconURLString:item.iconURLString
                                       toShortcuts:weakSelf.mutableShortcuts];
        [weakSelf reloadCollectionView];
    }];
}

- (void)presentEditShortcutSheet:(BrowserShortcutItem *)shortcut {
    if (shortcut.isFolder) {
        [self presentFolder:shortcut];
        [self.folderOverlay beginRenaming];
        return;
    }
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BrowserShortcutEditorSheet presentEditingShortcut:shortcut onWindow:window completion:^(BrowserShortcutItem *item) {
        if (!item) {
            return;
        }
        [BrowserShortcutStore updateShortcutWithID:item.itemID
                                             title:item.title
                                         urlString:item.urlString
                                     iconURLString:item.iconURLString
                                       inShortcuts:weakSelf.mutableShortcuts];
        [weakSelf reloadShortcuts];
    }];
}

- (void)confirmDeleteFolder:(BrowserShortcutItem *)folder {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"删除文件夹「%@」？", folder.title ?: @""];
    alert.informativeText = @"可以选择解散（子项回到顶层）或删除全部内容。";
    [alert addButtonWithTitle:@"解散"];
    [alert addButtonWithTitle:@"删除全部"];
    [alert addButtonWithTitle:@"取消"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [BrowserShortcutStore disbandFolderWithID:folder.itemID inShortcuts:self.mutableShortcuts];
    } else if (response == NSAlertSecondButtonReturn) {
        [BrowserShortcutStore removeFolderWithID:folder.itemID deleteChildren:YES inShortcuts:self.mutableShortcuts];
    } else {
        return;
    }
    if ([self.folderOverlay.folder.itemID isEqualToString:folder.itemID]) {
        [self dismissFolderOverlayAnimated:YES];
    }
    [self reloadCollectionView];
}

- (void)clearMergeState {
    self.mergeTargetItemID = nil;
    [self updateMergeHighlights];
}

- (void)updateMergeHighlights {
    for (NSCollectionViewItem *item in self.collectionView.visibleItems) {
        if (![item isKindOfClass:[BrowserShortcutCellView class]]) {
            continue;
        }
        BrowserShortcutCellView *cell = (BrowserShortcutCellView *)item;
        BOOL highlighted = cell.shortcut.itemID.length > 0
            && [cell.shortcut.itemID isEqualToString:self.mergeTargetItemID];
        cell.mergeHighlighted = highlighted;
    }
}

- (NSInteger)launchpadDraggingSourceIndex {
    if (self.draggingItemID.length == 0) {
        return NSNotFound;
    }
    for (NSUInteger i = 0; i < self.displayShortcuts.count; i++) {
        if ([self.displayShortcuts[i].itemID isEqualToString:self.draggingItemID]) {
            return (NSInteger)i;
        }
    }
    return NSNotFound;
}

- (NSInteger)launchpadDropInsertIndex {
    return self.dropPlaceholderIndex;
}

- (void)invalidateLaunchpadReflowAnimated:(BOOL)animated {
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            context.allowsImplicitAnimation = YES;
            [self.flowLayout invalidateLayout];
            [self.collectionView layoutSubtreeIfNeeded];
        } completionHandler:nil];
    } else {
        [self.flowLayout invalidateLayout];
        [self.collectionView layoutSubtreeIfNeeded];
    }
}

- (void)hideDropPlaceholder {
    BOOL hadPlaceholder = (self.dropPlaceholderIndex != NSNotFound) || !self.dropPlaceholderView.hidden;
    self.dropPlaceholderIndex = NSNotFound;
    self.dropPlaceholderView.hidden = YES;
    if (hadPlaceholder || self.draggingItemID.length > 0) {
        [self invalidateLaunchpadReflowAnimated:self.draggingItemID.length > 0];
    }
}

- (void)updateDropPlaceholderDashPath {
    CAShapeLayer *dash = nil;
    for (CALayer *layer in self.dropPlaceholderView.layer.sublayers) {
        if ([layer.name isEqualToString:@"launchpad.dropPlaceholder.dash"]) {
            dash = (CAShapeLayer *)layer;
            break;
        }
    }
    if (!dash) {
        return;
    }
    CGFloat radius = MAX(self.dropPlaceholderView.layer.cornerRadius - 1.0, 0);
    NSRect bounds = self.dropPlaceholderView.bounds;
    dash.frame = bounds;
    CGRect inset = NSRectToCGRect(NSInsetRect(bounds, 1, 1));
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRoundedRect(path, NULL, inset, radius, radius);
    dash.path = path;
    CGPathRelease(path);
    self.dropPlaceholderView.layer.borderWidth = 0;
    self.dropPlaceholderView.layer.masksToBounds = YES;
}

- (NSRect)launchpadCellSlotFrameForInsertIndex:(NSInteger)index
                                   sourceIndex:(NSInteger)sourceIndex
                                         count:(NSInteger)count {
    NSRect frame = [self.flowLayout launchpadPlaceholderFrameForInsertIndex:index sourceIndex:sourceIndex];
    if (!NSIsEmptyRect(frame)) {
        return frame;
    }
    if (index < count) {
        return [self.flowLayout launchpadBaseFrameForItemAtIndex:index];
    }
    if (count > 0) {
        frame = [self.flowLayout launchpadBaseFrameForItemAtIndex:count - 1];
        CGFloat nextX = NSMaxX(frame) + self.flowLayout.minimumInteritemSpacing;
        CGFloat maxX = NSWidth(self.collectionView.bounds) - self.flowLayout.sectionInset.right - self.flowLayout.itemSize.width;
        if (nextX <= maxX + 0.5) {
            frame.origin.x = nextX;
        } else {
            frame.origin.x = self.flowLayout.sectionInset.left;
            frame.origin.y -= (self.flowLayout.itemSize.height + self.flowLayout.minimumLineSpacing);
        }
        frame.size = self.flowLayout.itemSize;
        return frame;
    }
    NSEdgeInsets inset = self.flowLayout.sectionInset;
    return NSMakeRect(inset.left, inset.bottom, self.flowLayout.itemSize.width, self.flowLayout.itemSize.height);
}

- (void)showDropPlaceholderBeforeIndex:(NSInteger)index {
    NSInteger count = (NSInteger)self.displayShortcuts.count;
    if (index < 0 || index > count) {
        [self hideDropPlaceholder];
        return;
    }

    NSInteger sourceIndex = [self launchpadDraggingSourceIndex];
    // 拖到自己当前位置的前后空隙：不腾空位（等价于无移动）。
    if (sourceIndex != NSNotFound && (index == sourceIndex || index == sourceIndex + 1)) {
        if (self.dropPlaceholderIndex != NSNotFound || !self.dropPlaceholderView.hidden) {
            self.dropPlaceholderIndex = NSNotFound;
            self.dropPlaceholderView.hidden = YES;
            [self invalidateLaunchpadReflowAnimated:YES];
        }
        return;
    }

    BOOL indexChanged = (self.dropPlaceholderIndex != index);
    self.dropPlaceholderIndex = index;
    if (indexChanged) {
        [self invalidateLaunchpadReflowAnimated:YES];
    } else {
        [self.collectionView layoutSubtreeIfNeeded];
    }

    NSRect cellSlot = [self launchpadCellSlotFrameForInsertIndex:index sourceIndex:sourceIndex count:count];
    // 占位符 = 与图标同大的圆角正方形（不是整格竖长矩形）。
    NSRect frame = [self launchpadIconSlotFrameInCellFrame:cellSlot];
    CGFloat radius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:self.cachedIconSize];
    self.dropPlaceholderView.layer.cornerRadius = radius;
    self.dropPlaceholderView.frame = frame;
    self.dropPlaceholderView.hidden = NO;
    [self updateDropPlaceholderDashPath];
    [self.collectionView addSubview:self.dropPlaceholderView positioned:NSWindowAbove relativeTo:nil];
}

#pragma mark - Context Menu

- (nullable NSIndexPath *)layoutIndexPathAtPoint:(NSPoint)point {
    if ([self.collectionView isKindOfClass:[BrowserLaunchpadCollectionView class]]) {
        return [(BrowserLaunchpadCollectionView *)self.collectionView launchpadLayoutIndexPathAtPoint:point];
    }
    return [self.collectionView indexPathForItemAtPoint:point];
}

- (NSMenu *)menuForCollectionEvent:(NSEvent *)event {
    NSPoint point = [self.collectionView convertPoint:event.locationInWindow fromView:nil];
    NSIndexPath *indexPath = [self layoutIndexPathAtPoint:point];
    if (indexPath && ![self isAddIndexPath:indexPath]) {
        return [self shortcutMenuForIndexPath:indexPath];
    }
    return [self backgroundMenu];
}

- (NSMenu *)shortcutMenuForIndexPath:(NSIndexPath *)indexPath {
    BrowserShortcutItem *shortcut = [self shortcutAtIndexPath:indexPath];
    if (!shortcut) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] init];
    if (shortcut.isFolder) {
        [menu addItemWithTitle:@"打开文件夹" action:@selector(contextOpenFolder:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItemWithTitle:@"重命名…" action:@selector(contextRenameFolder:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;
        [menu addItemWithTitle:@"解散文件夹" action:@selector(contextDisbandFolder:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;
        [menu addItemWithTitle:@"删除文件夹…" action:@selector(contextDeleteFolder:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;
    } else {
        [menu addItemWithTitle:@"打开链接" action:@selector(contextOpenLink:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;

        [menu addItemWithTitle:@"在新标签页中打开" action:@selector(contextOpenInNewTab:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;

        [menu addItem:[NSMenuItem separatorItem]];

        [menu addItemWithTitle:@"编辑…" action:@selector(contextEditShortcut:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;

        [menu addItemWithTitle:@"从快捷方式移除" action:@selector(contextRemoveShortcut:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        menu.itemArray.lastObject.representedObject = shortcut;
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"外观与背景…" action:@selector(contextShowAppearance:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;

    return menu;
}

- (NSMenu *)backgroundMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"添加快捷方式…" action:@selector(contextAddShortcut:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"设置背景图片…" action:@selector(contextChooseWallpaper:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    if ([BrowserWallpaperStore sharedStore].hasDisplayFile) {
        [menu addItemWithTitle:@"清除背景" action:@selector(contextClearWallpaper:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
    }
    [menu addItemWithTitle:@"外观与背景…" action:@selector(contextShowAppearance:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    return menu;
}

- (void)contextOpenLink:(NSMenuItem *)sender {
    [self openShortcut:sender.representedObject inNewTab:NO];
}

- (void)contextOpenInNewTab:(NSMenuItem *)sender {
    [self openShortcut:sender.representedObject inNewTab:YES];
}

- (void)contextOpenFolder:(NSMenuItem *)sender {
    [self presentFolder:sender.representedObject];
}

- (void)contextRenameFolder:(NSMenuItem *)sender {
    BrowserShortcutItem *folder = sender.representedObject;
    [self presentFolder:folder];
    [self.folderOverlay beginRenaming];
}

- (void)contextDisbandFolder:(NSMenuItem *)sender {
    BrowserShortcutItem *folder = sender.representedObject;
    [BrowserShortcutStore disbandFolderWithID:folder.itemID inShortcuts:self.mutableShortcuts];
    if ([self.folderOverlay.folder.itemID isEqualToString:folder.itemID]) {
        [self dismissFolderOverlayAnimated:YES];
    }
    [self reloadCollectionView];
}

- (void)contextDeleteFolder:(NSMenuItem *)sender {
    [self confirmDeleteFolder:sender.representedObject];
}

- (void)contextEditShortcut:(NSMenuItem *)sender {
    [self presentEditShortcutSheet:sender.representedObject];
}

- (void)contextRemoveShortcut:(NSMenuItem *)sender {
    BrowserShortcutItem *shortcut = sender.representedObject;
    if (shortcut.isFolder) {
        [self confirmDeleteFolder:shortcut];
        return;
    }
    [BrowserShortcutStore removeShortcutWithID:shortcut.itemID fromShortcuts:self.mutableShortcuts];
    [self reloadCollectionView];
}

- (void)contextAddShortcut:(NSMenuItem *)sender {
    (void)sender;
    [self presentAddShortcutSheet];
}

- (void)contextShowAppearance:(NSMenuItem *)sender {
    (void)sender;
    [self showAppearanceSettings];
}

- (void)contextChooseWallpaper:(NSMenuItem *)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = [NSImage imageTypes];
#pragma clang diagnostic pop
    panel.message = @"选择新标签页背景图片";
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        [[BrowserWallpaperStore sharedStore] importImageFromURL:panel.URL
                                                     completion:^(NSError *error) {
            if (error == nil) {
                return;
            }
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"无法设置背景图片";
            alert.informativeText = error.localizedDescription ?: @"";
            if (weakSelf.window != nil) {
                [alert beginSheetModalForWindow:weakSelf.window completionHandler:nil];
            } else {
                [alert runModal];
            }
        }];
    }];
}

- (void)contextClearWallpaper:(NSMenuItem *)sender {
    (void)sender;
    [[BrowserWallpaperStore sharedStore] clearWallpaper];
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    (void)section;
    return [self totalItemCount];
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    BrowserShortcutCellView *cell = [collectionView makeItemWithIdentifier:@"ShortcutCell" forIndexPath:indexPath];
    [cell applyIconSize:self.cachedIconSize];

    __weak typeof(self) weakSelf = self;
    if ([self isAddIndexPath:indexPath]) {
        [cell configureAsAddCell];
        cell.onAddTapped = ^{
            [weakSelf presentAddShortcutSheet];
        };
        return cell;
    }

    BrowserShortcutItem *shortcut = [self shortcutAtIndexPath:indexPath];
    NSArray<BrowserShortcutItem *> *children = shortcut.isFolder
        ? [BrowserShortcutStore childrenOfFolderID:shortcut.itemID inShortcuts:self.mutableShortcuts]
        : @[];
    [cell configureWithShortcut:shortcut children:children];
    cell.mergeHighlighted = [shortcut.itemID isEqualToString:self.mergeTargetItemID];
    cell.onActivate = ^(BrowserShortcutItem *item, BOOL openInNewTab) {
        [weakSelf openShortcut:item inNewTab:openInNewTab];
    };
    return cell;
}

#pragma mark - Drag and Drop

/// 拖拽重排后的视觉格子（与屏幕上看到的图标位置一致）。
- (NSRect)launchpadVisualFrameForItemAtIndex:(NSInteger)index {
    NSCollectionViewLayoutAttributes *attrs =
        [self.flowLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
    return attrs ? attrs.frame : NSZeroRect;
}

- (nullable BrowserShortcutItem *)mergeTargetAtPoint:(NSPoint)location
                                              source:(BrowserShortcutItem *)source {
    if (!source || source.isFolder) {
        return nil;
    }

    // 必须用挤位后的视觉坐标；否则拖到「文件夹」上看起来命中了，实际测到旧槽位。
    NSInteger count = (NSInteger)self.displayShortcuts.count;
    NSInteger hoverIndex = NSNotFound;
    NSRect frame = NSZeroRect;
    for (NSInteger i = 0; i < count; i++) {
        BrowserShortcutItem *candidateItem = self.displayShortcuts[(NSUInteger)i];
        if ([candidateItem.itemID isEqualToString:source.itemID]) {
            continue; // 源图标透明占位，不参与合并命中
        }
        NSRect candidate = [self launchpadVisualFrameForItemAtIndex:i];
        if (!NSIsEmptyRect(candidate) && NSPointInRect(location, candidate)) {
            hoverIndex = i;
            frame = candidate;
            break;
        }
    }
    if (hoverIndex == NSNotFound) {
        return nil;
    }
    BrowserShortcutItem *target = self.displayShortcuts[(NSUInteger)hoverIndex];
    if (!target) {
        return nil;
    }

    // 文件夹：图标主体区即可归入（更易拖入）；链接：中心约 50% 用于建夹，边缘留给排序。
    if (target.isFolder) {
        NSRect iconSlot = [self launchpadIconSlotFrameInCellFrame:frame];
        if (!NSPointInRect(location, iconSlot)) {
            return nil;
        }
        return target;
    }

    NSRect center = NSInsetRect(frame, frame.size.width * 0.25, frame.size.height * 0.25);
    if (!NSPointInRect(location, center)) {
        return nil;
    }
    return target;
}

/// 根据指针位置计算 DropBefore 插入下标（0...count，count 表示末尾）。
- (NSInteger)insertionIndexAtPoint:(NSPoint)location {
    NSInteger count = (NSInteger)self.displayShortcuts.count;
    if (count == 0) {
        return 0;
    }

    NSInteger bestIndex = count;
    CGFloat bestScore = CGFLOAT_MAX;
    NSInteger sourceIndex = [self launchpadDraggingSourceIndex];

    for (NSInteger i = 0; i < count; i++) {
        if (i == sourceIndex) {
            continue;
        }
        // 视觉坐标与挤位动画一致，保证「拖到文件夹上」不会误判成排序空位。
        NSRect frame = [self launchpadVisualFrameForItemAtIndex:i];
        if (NSIsEmptyRect(frame)) {
            continue;
        }
        BOOL leftHalf = location.x < NSMidX(frame);
        NSInteger candidate = leftHalf ? i : (i + 1);
        NSPoint gapPoint = leftHalf
            ? NSMakePoint(NSMinX(frame), NSMidY(frame))
            : NSMakePoint(NSMaxX(frame), NSMidY(frame));
        CGFloat dx = location.x - gapPoint.x;
        CGFloat dy = location.y - gapPoint.y;
        CGFloat score = dx * dx + dy * dy;
        if (fabs(location.y - NSMidY(frame)) > frame.size.height) {
            score += 100000.0;
        }
        if (score < bestScore) {
            bestScore = score;
            bestIndex = candidate;
        }
    }

    NSInteger addIndex = count;
    NSRect addFrame = [self launchpadVisualFrameForItemAtIndex:addIndex];
    if (!NSIsEmptyRect(addFrame) && NSPointInRect(location, addFrame)) {
        return count;
    }
    return MAX(0, MIN(bestIndex, count));
}

- (nullable NSString *)draggingItemIDFromInfo:(id<NSDraggingInfo>)sender {
    if (self.draggingItemID.length > 0) {
        return self.draggingItemID;
    }
    return [sender.draggingPasteboard stringForType:kBrowserShortcutDragType];
}

- (NSDragOperation)launchpadUpdateDropFeedbackAtPoint:(NSPoint)locationInCollectionView
                                               source:(BrowserShortcutItem *)source {
    if (!source) {
        [self hideDropPlaceholder];
        [self clearMergeState];
        return NSDragOperationNone;
    }
    // Overlay 展开时禁止拖顶层项；夹内项拖出时允许在主网格显示占位。
    if (self.folderOverlay.folder && source.isTopLevel) {
        [self hideDropPlaceholder];
        [self clearMergeState];
        return NSDragOperationNone;
    }

    BrowserShortcutItem *mergeTarget = [self mergeTargetAtPoint:locationInCollectionView source:source];
    if (mergeTarget) {
        [self hideDropPlaceholder];
        self.mergeTargetItemID = mergeTarget.itemID;
        [self updateMergeHighlights];
        return NSDragOperationMove;
    }

    [self clearMergeState];
    NSInteger insertIndex = [self insertionIndexAtPoint:locationInCollectionView];
    [self showDropPlaceholderBeforeIndex:insertIndex];
    return NSDragOperationMove;
}

- (NSDragOperation)launchpadHandleDraggingUpdated:(id<NSDraggingInfo>)sender {
    NSString *itemID = [self draggingItemIDFromInfo:sender];
    BrowserShortcutItem *source = [BrowserShortcutStore shortcutWithID:itemID inShortcuts:self.mutableShortcuts];
    if (!source) {
        [self hideDropPlaceholder];
        [self clearMergeState];
        return NSDragOperationNone;
    }
    NSPoint location = [self.collectionView convertPoint:sender.draggingLocation fromView:nil];
    return [self launchpadUpdateDropFeedbackAtPoint:location source:source];
}

- (void)launchpadHandleDraggingExited {
    // 只收起视觉反馈；保留 index / mergeTarget 供松手兜底提交。
    self.dropPlaceholderView.hidden = YES;
    NSString *mergeID = self.mergeTargetItemID;
    self.mergeTargetItemID = nil;
    [self updateMergeHighlights];
    self.mergeTargetItemID = mergeID;
}

- (BOOL)launchpadCommitDropForSource:(BrowserShortcutItem *)source
                            atPoint:(NSPoint)locationInCollectionView {
    if (!source || self.dropDidCommit) {
        return self.dropDidCommit;
    }

    BrowserShortcutItem *mergeTarget = nil;
    if (self.mergeTargetItemID.length > 0) {
        mergeTarget = [BrowserShortcutStore shortcutWithID:self.mergeTargetItemID
                                               inShortcuts:self.mutableShortcuts];
    }
    if (!mergeTarget) {
        mergeTarget = [self mergeTargetAtPoint:locationInCollectionView source:source];
    }
    if (mergeTarget && !source.isFolder && ![mergeTarget.itemID isEqualToString:source.itemID]) {
        BOOL ok = NO;
        if (mergeTarget.isFolder) {
            ok = [BrowserShortcutStore moveItem:source intoFolder:mergeTarget inShortcuts:self.mutableShortcuts];
        } else {
            ok = [BrowserShortcutStore createFolderWithTitle:@"文件夹"
                                                   fromItem:mergeTarget
                                               droppingItem:source
                                                inShortcuts:self.mutableShortcuts] != nil;
        }
        if (ok) {
            self.dropDidCommit = YES;
            [self reloadShortcuts];
            return YES;
        }
        return NO;
    }

    NSInteger destinationIndex = self.dropPlaceholderIndex;
    if (destinationIndex == NSNotFound) {
        destinationIndex = [self insertionIndexAtPoint:locationInCollectionView];
    }
    destinationIndex = MAX(0, MIN(destinationIndex, (NSInteger)self.displayShortcuts.count));

    // 来自文件夹的项不在顶层列表中：直接升顶层并插到占位位置。
    if (!source.isTopLevel) {
        [BrowserShortcutStore moveItem:source
                     toTopLevelAtOrder:destinationIndex
                           inShortcuts:self.mutableShortcuts];
        self.dropDidCommit = YES;
        [self reloadShortcuts];
        return YES;
    }

    NSMutableArray<BrowserShortcutItem *> *ordered = [self.displayShortcuts mutableCopy];
    NSInteger sourceIndex = NSNotFound;
    for (NSUInteger i = 0; i < ordered.count; i++) {
        if ([ordered[i].itemID isEqualToString:source.itemID]) {
            sourceIndex = (NSInteger)i;
            break;
        }
    }
    if (sourceIndex == NSNotFound) {
        return NO;
    }

    if (destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1) {
        self.dropDidCommit = YES;
        return YES;
    }

    BrowserShortcutItem *item = ordered[(NSUInteger)sourceIndex];
    [ordered removeObjectAtIndex:(NSUInteger)sourceIndex];
    if (destinationIndex > sourceIndex) {
        destinationIndex--;
    }
    destinationIndex = MAX(0, MIN(destinationIndex, (NSInteger)ordered.count));
    [ordered insertObject:item atIndex:(NSUInteger)destinationIndex];

    [BrowserShortcutStore reorderTopLevelItems:ordered inShortcuts:self.mutableShortcuts];
    self.dropDidCommit = YES;
    [self reloadShortcuts];
    return YES;
}

- (BOOL)launchpadCommitDropAtScreenPoint:(NSPoint)screenPoint {
    if (!self.window || self.draggingItemID.length == 0) {
        return NO;
    }
    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    NSPoint location = [self.collectionView convertPoint:windowPoint fromView:nil];
    NSRect hitArea = NSInsetRect(self.collectionView.bounds, -40.0, -40.0);
    if (!NSPointInRect(location, hitArea)) {
        return NO;
    }
    BrowserShortcutItem *source = [BrowserShortcutStore shortcutWithID:self.draggingItemID
                                                           inShortcuts:self.mutableShortcuts];
    return [self launchpadCommitDropForSource:source atPoint:location];
}

- (BOOL)launchpadHandlePerformDragOperation:(id<NSDraggingInfo>)sender {
    NSString *itemID = [self draggingItemIDFromInfo:sender];
    BrowserShortcutItem *source = [BrowserShortcutStore shortcutWithID:itemID inShortcuts:self.mutableShortcuts];
    if (!source) {
        return NO;
    }
    NSPoint location = [self.collectionView convertPoint:sender.draggingLocation fromView:nil];
    return [self launchpadCommitDropForSource:source atPoint:location];
}

#pragma mark - BrowserShortcutFolderOverlayDelegate

- (void)folderOverlayDidRequestClose:(BrowserShortcutFolderOverlay *)overlay {
    (void)overlay;
    [self dismissFolderOverlayAnimated:YES];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
              openURL:(NSURL *)url
             inNewTab:(BOOL)inNewTab {
    (void)overlay;
    __weak typeof(self) weakSelf = self;
    [self.folderOverlay dismissAnimated:YES completion:^{
        if (!weakSelf.delegate || !url) {
            return;
        }
        if (inNewTab) {
            [weakSelf.delegate launchpadView:weakSelf openURLInNewTab:url];
        } else {
            [weakSelf.delegate launchpadView:weakSelf openURL:url];
        }
    }];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
         renameFolder:(BrowserShortcutItem *)folder
                title:(NSString *)title {
    (void)overlay;
    [BrowserShortcutStore renameFolderWithID:folder.itemID title:title inShortcuts:self.mutableShortcuts];
    [self reloadCollectionView];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
       removeShortcut:(BrowserShortcutItem *)shortcut {
    (void)overlay;
    [BrowserShortcutStore removeShortcutWithID:shortcut.itemID fromShortcuts:self.mutableShortcuts];
    [self reloadShortcuts];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
moveShortcutToTopLevel:(BrowserShortcutItem *)shortcut {
    (void)overlay;
    NSInteger order = (NSInteger)self.displayShortcuts.count;
    [BrowserShortcutStore moveItem:shortcut toTopLevelAtOrder:order inShortcuts:self.mutableShortcuts];
    [self reloadShortcuts];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
         editShortcut:(BrowserShortcutItem *)shortcut {
    (void)overlay;
    [self presentEditShortcutSheet:shortcut];
}

- (BOOL)folderOverlayIsEditingMode:(BrowserShortcutFolderOverlay *)overlay {
    (void)overlay;
    return NO;
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
didBeginDraggingChild:(BrowserShortcutItem *)child {
    (void)overlay;
    if (!child || child.itemID.length == 0) {
        return;
    }
    self.draggingItemID = child.itemID;
    self.dropDidCommit = NO;
    [self clearMergeState];
    self.dropPlaceholderIndex = NSNotFound;
    self.dropPlaceholderView.hidden = YES;
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
        draggingChild:(BrowserShortcutItem *)child
    movedToWindowPoint:(NSPoint)windowPoint
         outsidePanel:(BOOL)outsidePanel {
    (void)overlay;
    if (!child) {
        return;
    }
    self.draggingItemID = child.itemID;
    if (!outsidePanel) {
        [self hideDropPlaceholder];
        [self clearMergeState];
        return;
    }
    NSPoint location = [self.collectionView convertPoint:windowPoint fromView:nil];
    [self launchpadUpdateDropFeedbackAtPoint:location source:child];
}

- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
  didEndDraggingChild:(BrowserShortcutItem *)child
        atWindowPoint:(NSPoint)windowPoint
         outsidePanel:(BOOL)outsidePanel {
    (void)overlay;
    if (!child) {
        [self launchpadDraggingSessionDidEnd];
        return;
    }
    self.draggingItemID = child.itemID;
    if (outsidePanel && !self.dropDidCommit) {
        NSPoint location = [self.collectionView convertPoint:windowPoint fromView:nil];
        if (![self launchpadCommitDropForSource:child atPoint:location]) {
            // 落在网格外：追加到顶层末尾。
            NSInteger order = (NSInteger)self.displayShortcuts.count;
            [BrowserShortcutStore moveItem:child toTopLevelAtOrder:order inShortcuts:self.mutableShortcuts];
            self.dropDidCommit = YES;
            [self reloadShortcuts];
        }
    }
    [self launchpadDraggingSessionDidEnd];
}

@end
