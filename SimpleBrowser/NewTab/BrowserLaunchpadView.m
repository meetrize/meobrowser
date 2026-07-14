#import "BrowserLaunchpadView.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutCellView.h"
#import "BrowserShortcutEditorSheet.h"
#import "BrowserLaunchpadAppearance.h"
#import "BrowserLaunchpadAppearancePanel.h"

@class BrowserLaunchpadView;

@interface BrowserLaunchpadView (ContextMenu)
- (NSMenu *)menuForCollectionEvent:(NSEvent *)event;
@end

@interface BrowserLaunchpadView (EditingInteraction)
@property (nonatomic, readonly, getter=isEditingMode) BOOL editingMode;
- (void)enterEditingMode;
- (void)exitEditingModeFromBackgroundClick;
@end

@interface BrowserLaunchpadCollectionView : NSCollectionView
@property (nonatomic, weak) BrowserLaunchpadView *launchpadHost;
@end

@implementation BrowserLaunchpadCollectionView

- (void)mouseDown:(NSEvent *)event {
    if (self.launchpadHost.isEditingMode) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (![self indexPathForItemAtPoint:point]) {
            [self.launchpadHost exitEditingModeFromBackgroundClick];
        }
    }
    [super mouseDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.launchpadHost) {
        return [self.launchpadHost menuForCollectionEvent:event];
    }
    return [super menuForEvent:event];
}

@end

@interface BrowserLaunchpadView () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSPopoverDelegate>
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) BrowserLaunchpadCollectionView *collectionView;
@property (nonatomic, strong) NSCollectionViewFlowLayout *flowLayout;
@property (nonatomic, strong) NSMutableArray<BrowserShortcutItem *> *mutableShortcuts;
@property (nonatomic, assign, getter=isEditingMode) BOOL editingMode;
@property (nonatomic, strong, nullable) id escapeMonitor;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@property (nonatomic, strong) NSButton *settingsButton;
@property (nonatomic, strong, nullable) NSPopover *appearancePopover;
@property (nonatomic, strong) BrowserLaunchpadAppearancePanel *appearancePanel;
@property (nonatomic, assign) CGFloat cachedIconSize;
@property (nonatomic, assign) CGFloat cachedHorizontalSpacing;
@property (nonatomic, assign) CGFloat cachedVerticalSpacing;
@end

@implementation BrowserLaunchpadView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _mutableShortcuts = [[NSMutableArray alloc] init];
        BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
        _cachedIconSize = appearance.iconSize;
        _cachedHorizontalSpacing = appearance.horizontalSpacing;
        _cachedVerticalSpacing = appearance.verticalSpacing;
        [self setupViews];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appearanceDidChange:)
                                                     name:BrowserLaunchpadAppearanceDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeEscapeMonitor];
}

- (void)setupViews {
    self.wantsLayer = YES;

    _effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    _effectView.material = NSVisualEffectMaterialContentBackground;
    _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _effectView.state = NSVisualEffectStateActive;
    _effectView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_effectView];

    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:self.cachedIconSize];
    _flowLayout = [[NSCollectionViewFlowLayout alloc] init];
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
    _collectionView.selectable = NO;
    _collectionView.clipsToBounds = NO;
    [_collectionView registerClass:[BrowserShortcutCellView class] forItemWithIdentifier:@"ShortcutCell"];
    [_collectionView registerForDraggedTypes:@[NSPasteboardTypeString]];

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
    _settingsButton.toolTip = @"快捷方式外观";
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        NSImage *gear = [NSImage imageWithSystemSymbolName:@"gearshape"
                                  accessibilityDescription:@"快捷方式外观"];
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

    [NSLayoutConstraint activateConstraints:@[
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
    [self reloadCollectionView];
}

- (void)reloadCollectionView {
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

    // 每次新建面板，避免复用视图在 Popover 容器里残留错误布局。
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
    // 实测：底部齿轮用 MinY 会向上展开；MaxY 反而向下，窗口靠下时会出屏。
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

#pragma mark - Edit Mode

- (void)setEditingMode:(BOOL)editingMode {
    if (_editingMode == editingMode) {
        return;
    }
    _editingMode = editingMode;
    if (editingMode) {
        [self installEscapeMonitor];
    } else {
        [self removeEscapeMonitor];
    }
    [self reloadCollectionView];
}

- (void)installEscapeMonitor {
    if (self.escapeMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.escapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                               handler:^NSEvent *(NSEvent *event) {
        if (weakSelf.isEditingMode && event.keyCode == 53) {
            weakSelf.editingMode = NO;
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

- (void)enterEditingMode {
    self.editingMode = YES;
}

- (void)exitEditingModeFromBackgroundClick {
    if (self.isEditingMode) {
        self.editingMode = NO;
    }
}

#pragma mark - Helpers

- (NSInteger)totalItemCount {
    NSInteger count = (NSInteger)self.mutableShortcuts.count;
    return self.isEditingMode ? count + 1 : count;
}

- (BOOL)isAddIndexPath:(NSIndexPath *)indexPath {
    return self.isEditingMode && indexPath.item == (NSInteger)self.mutableShortcuts.count;
}

- (nullable BrowserShortcutItem *)shortcutAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isAddIndexPath:indexPath]) {
        return nil;
    }
    if (indexPath.item < 0 || indexPath.item >= (NSInteger)self.mutableShortcuts.count) {
        return nil;
    }
    return self.mutableShortcuts[(NSUInteger)indexPath.item];
}

- (void)openShortcut:(BrowserShortcutItem *)shortcut inNewTab:(BOOL)inNewTab {
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
        [weakSelf reloadCollectionView];
    }];
}

#pragma mark - Context Menu

- (NSMenu *)menuForCollectionEvent:(NSEvent *)event {
    NSPoint point = [self.collectionView convertPoint:event.locationInWindow fromView:nil];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
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

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *editTitle = self.isEditingMode ? @"完成编辑" : @"编辑快捷方式…";
    [menu addItemWithTitle:editTitle action:@selector(contextToggleEditMode:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"快捷方式外观…" action:@selector(contextShowAppearance:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;

    return menu;
}

- (NSMenu *)backgroundMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSString *editTitle = self.isEditingMode ? @"完成编辑" : @"编辑快捷方式…";
    [menu addItemWithTitle:editTitle action:@selector(contextToggleEditMode:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    if (!self.isEditingMode) {
        [menu addItemWithTitle:@"添加快捷方式…" action:@selector(contextAddShortcut:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"快捷方式外观…" action:@selector(contextShowAppearance:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    return menu;
}

- (void)contextOpenLink:(NSMenuItem *)sender {
    BrowserShortcutItem *shortcut = sender.representedObject;
    [self openShortcut:shortcut inNewTab:NO];
}

- (void)contextOpenInNewTab:(NSMenuItem *)sender {
    BrowserShortcutItem *shortcut = sender.representedObject;
    [self openShortcut:shortcut inNewTab:YES];
}

- (void)contextEditShortcut:(NSMenuItem *)sender {
    BrowserShortcutItem *shortcut = sender.representedObject;
    [self presentEditShortcutSheet:shortcut];
}

- (void)contextRemoveShortcut:(NSMenuItem *)sender {
    BrowserShortcutItem *shortcut = sender.representedObject;
    [BrowserShortcutStore removeShortcutWithID:shortcut.itemID fromShortcuts:self.mutableShortcuts];
    [self reloadCollectionView];
}

- (void)contextToggleEditMode:(NSMenuItem *)sender {
    (void)sender;
    self.editingMode = !self.isEditingMode;
}

- (void)contextAddShortcut:(NSMenuItem *)sender {
    (void)sender;
    [self presentAddShortcutSheet];
}

- (void)contextShowAppearance:(NSMenuItem *)sender {
    (void)sender;
    [self showAppearanceSettings];
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
    cell.editingMode = self.isEditingMode;
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
    [cell configureWithShortcut:shortcut];
    cell.onActivate = ^(BrowserShortcutItem *item, BOOL openInNewTab) {
        [weakSelf openShortcut:item inNewTab:openInNewTab];
    };
    cell.onDelete = ^(BrowserShortcutItem *item) {
        [BrowserShortcutStore removeShortcutWithID:item.itemID fromShortcuts:weakSelf.mutableShortcuts];
        [weakSelf reloadCollectionView];
    };
    cell.onRequestEditMode = ^{
        [weakSelf enterEditingMode];
    };
    return cell;
}

#pragma mark - Drag and Drop

- (BOOL)collectionView:(NSCollectionView *)collectionView canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    (void)collectionView;
    if (!self.isEditingMode) {
        return NO;
    }
    for (NSIndexPath *indexPath in indexPaths) {
        if ([self isAddIndexPath:indexPath]) {
            return NO;
        }
    }
    return YES;
}

- (nullable id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
                    pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath {
    (void)collectionView;
    BrowserShortcutItem *shortcut = [self shortcutAtIndexPath:indexPath];
    return shortcut.itemID;
}

- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
                     draggingSession:(NSDraggingSession *)session
sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)collectionView;
    (void)session;
    (void)context;
    return self.isEditingMode ? NSDragOperationMove : NSDragOperationNone;
}

- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
                      validateDrop:(id<NSDraggingInfo>)draggingInfo
                 proposedIndexPath:(NSIndexPath * _Nullable *)proposedDropIndexPath
                    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation {
    (void)collectionView;
    (void)draggingInfo;
    if (!self.isEditingMode || !proposedDropIndexPath || !*proposedDropIndexPath) {
        return NSDragOperationNone;
    }

    NSIndexPath *indexPath = *proposedDropIndexPath;
    if ([self isAddIndexPath:indexPath]) {
        *proposedDropIndexPath = [NSIndexPath indexPathForItem:(NSInteger)self.mutableShortcuts.count - 1 inSection:0];
    }
    *proposedDropOperation = NSCollectionViewDropBefore;
    return NSDragOperationMove;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
            acceptDrop:(id<NSDraggingInfo>)draggingInfo
             indexPath:(NSIndexPath *)indexPath
         dropOperation:(NSCollectionViewDropOperation)dropOperation {
    (void)collectionView;
    (void)dropOperation;
    if (!self.isEditingMode) {
        return NO;
    }

    NSString *itemID = [draggingInfo.draggingPasteboard stringForType:NSPasteboardTypeString];
    if (itemID.length == 0) {
        return NO;
    }

    NSInteger sourceIndex = NSNotFound;
    for (NSUInteger i = 0; i < self.mutableShortcuts.count; i++) {
        if ([self.mutableShortcuts[i].itemID isEqualToString:itemID]) {
            sourceIndex = (NSInteger)i;
            break;
        }
    }
    if (sourceIndex == NSNotFound) {
        return NO;
    }

    NSInteger destinationIndex = indexPath.item;
    if (destinationIndex >= (NSInteger)self.mutableShortcuts.count) {
        destinationIndex = (NSInteger)self.mutableShortcuts.count - 1;
    }

    BrowserShortcutItem *item = self.mutableShortcuts[(NSUInteger)sourceIndex];
    [self.mutableShortcuts removeObjectAtIndex:(NSUInteger)sourceIndex];
    if (destinationIndex > sourceIndex) {
        destinationIndex--;
    }
    destinationIndex = MAX(0, MIN(destinationIndex, (NSInteger)self.mutableShortcuts.count));
    [self.mutableShortcuts insertObject:item atIndex:(NSUInteger)destinationIndex];

    [BrowserShortcutStore saveShortcuts:self.mutableShortcuts];
    [self reloadCollectionView];
    return YES;
}

@end
