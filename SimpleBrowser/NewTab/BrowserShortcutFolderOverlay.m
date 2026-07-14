#import "BrowserShortcutFolderOverlay.h"
#import "BrowserShortcutItem.h"
#import "BrowserShortcutCellView.h"
#import "BrowserLaunchpadAppearance.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static const NSTimeInterval kOverlayAnimationDuration = 0.28;
static NSPasteboardType const kFolderChildDragType = @"com.meobrowser.shortcut-item-id";
/// 展开层至少按 Launchpad 风格预留的列数/行数，避免只有两三项时面板过小。
static const NSUInteger kFolderOverlayMinColumns = 4;
static const NSUInteger kFolderOverlayMaxColumns = 5;
static const NSUInteger kFolderOverlayMinRows = 2;
static const CGFloat kFolderOverlayMinWidth = 560.0;
static const CGFloat kFolderOverlayMinHeight = 380.0;

@interface BrowserShortcutFolderOverlay () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate, NSDraggingSource>
@property (nonatomic, strong) NSView *dimmingView;
@property (nonatomic, strong) NSVisualEffectView *panelView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) SBTextField *titleField;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSCollectionViewFlowLayout *flowLayout;
@property (nonatomic, strong, nullable) NSLayoutConstraint *panelWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *panelHeightConstraint;
@property (nonatomic, strong, readwrite, nullable) BrowserShortcutItem *folder;
@property (nonatomic, copy) NSArray<BrowserShortcutItem *> *children;
@property (nonatomic, assign) NSRect anchorRectInHost;
@property (nonatomic, assign) BOOL renaming;
@property (nonatomic, copy, nullable) NSString *draggingChildID;
@end

@implementation BrowserShortcutFolderOverlay

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _children = @[];
        self.wantsLayer = YES;
        self.hidden = YES;
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
}

- (void)appearanceDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.folder) {
        [self updateChildLayout];
        [self.collectionView reloadData];
    }
}

- (void)setupViews {
    _dimmingView = [[NSView alloc] initWithFrame:NSZeroRect];
    _dimmingView.wantsLayer = YES;
    _dimmingView.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.35].CGColor;
    _dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_dimmingView];

    NSClickGestureRecognizer *dimClick =
        [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(dimmingClicked:)];
    [_dimmingView addGestureRecognizer:dimClick];

    _panelView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    if (@available(macOS 10.14, *)) {
        _panelView.material = NSVisualEffectMaterialSheet;
    } else {
        _panelView.material = NSVisualEffectMaterialPopover;
    }
    _panelView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _panelView.state = NSVisualEffectStateActive;
    _panelView.wantsLayer = YES;
    _panelView.layer.cornerRadius = 30.0;
    _panelView.layer.masksToBounds = YES;
    if (@available(macOS 10.15, *)) {
        _panelView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _panelView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_panelView];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSClickGestureRecognizer *titleClick =
        [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(titleClicked:)];
    [_titleLabel addGestureRecognizer:titleClick];
    [_panelView addSubview:_titleLabel];

    _titleField = [SBTextField standardField];
    _titleField.font = [NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];
    _titleField.alignment = NSTextAlignmentCenter;
    _titleField.delegate = self;
    _titleField.hidden = YES;
    _titleField.translatesAutoresizingMaskIntoConstraints = NO;
    _titleField.target = self;
    _titleField.action = @selector(titleEditingCommitted:);
    [_panelView addSubview:_titleField];

    _flowLayout = [[NSCollectionViewFlowLayout alloc] init];
    _flowLayout.scrollDirection = NSCollectionViewScrollDirectionVertical;
    BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
    _flowLayout.minimumInteritemSpacing = appearance.horizontalSpacing;
    _flowLayout.minimumLineSpacing = appearance.verticalSpacing;
    _flowLayout.sectionInset = NSEdgeInsetsMake(appearance.verticalSpacing,
                                                appearance.horizontalSpacing,
                                                appearance.verticalSpacing,
                                                appearance.horizontalSpacing);

    _collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _collectionView.collectionViewLayout = _flowLayout;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.backgroundColors = @[[NSColor clearColor]];
    _collectionView.selectable = NO;
    [_collectionView registerClass:[BrowserShortcutCellView class] forItemWithIdentifier:@"FolderChildCell"];
    [_collectionView registerForDraggedTypes:@[kFolderChildDragType]];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.documentView = _collectionView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panelView addSubview:_scrollView];

    _panelWidthConstraint = [_panelView.widthAnchor constraintEqualToConstant:kFolderOverlayMinWidth];
    _panelHeightConstraint = [_panelView.heightAnchor constraintEqualToConstant:kFolderOverlayMinHeight];

    [NSLayoutConstraint activateConstraints:@[
        [_dimmingView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_dimmingView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_dimmingView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_dimmingView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_panelView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_panelView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_panelView.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.88],
        [_panelView.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.86],
        _panelWidthConstraint,
        _panelHeightConstraint,

        [_titleLabel.topAnchor constraintEqualToAnchor:_panelView.topAnchor constant:28],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor constant:40],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor constant:-40],
        [_titleLabel.heightAnchor constraintEqualToConstant:34],

        [_titleField.topAnchor constraintEqualToAnchor:_titleLabel.topAnchor],
        [_titleField.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_titleField.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_titleField.heightAnchor constraintEqualToConstant:34],

        [_scrollView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:20],
        [_scrollView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_panelView.bottomAnchor],
    ]];
}

- (void)updateAppearanceForEffectiveAppearance {
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        NSString *match = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua,
            NSAppearanceNameDarkAqua,
        ]];
        dark = [match isEqualToString:NSAppearanceNameDarkAqua];
    }
    // 略加深遮罩，突出中央大面板（贴近 Launchpad 展开层次）。
    CGFloat alpha = dark ? 0.52 : 0.40;
    self.dimmingView.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:alpha].CGColor;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateAppearanceForEffectiveAppearance];
}

- (void)presentFolder:(BrowserShortcutItem *)folder
             children:(NSArray<BrowserShortcutItem *> *)children
       fromAnchorRect:(NSRect)anchorRect
               inView:(NSView *)hostView
             animated:(BOOL)animated {
    self.folder = folder;
    self.children = children ?: @[];
    self.anchorRectInHost = anchorRect;
    self.titleLabel.stringValue = folder.title ?: @"文件夹";
    self.titleField.stringValue = self.titleLabel.stringValue;
    self.renaming = NO;
    self.titleLabel.hidden = NO;
    self.titleField.hidden = YES;
    [self updateAppearanceForEffectiveAppearance];

    if (self.superview != hostView) {
        self.translatesAutoresizingMaskIntoConstraints = YES;
        self.frame = hostView.bounds;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [hostView addSubview:self positioned:NSWindowAbove relativeTo:nil];
    } else {
        self.frame = hostView.bounds;
    }

    // 先铺满宿主再算面板尺寸，避免 bounds 为 0 时只能落在最小尺寸。
    [self updateChildLayout];
    [self.collectionView reloadData];

    self.hidden = NO;
    self.alphaValue = 0.0;
    self.panelView.layer.transform = CATransform3DMakeScale(0.88, 0.88, 1.0);

    void (^apply)(void) = ^{
        self.alphaValue = 1.0;
        self.panelView.layer.transform = CATransform3DIdentity;
    };

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = kOverlayAnimationDuration;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            context.allowsImplicitAnimation = YES;
            apply();
        } completionHandler:nil];
    } else {
        apply();
    }
}

- (void)dismissAnimated:(BOOL)animated completion:(nullable dispatch_block_t)completion {
    if (self.hidden) {
        if (completion) {
            completion();
        }
        return;
    }

    void (^finish)(void) = ^{
        self.hidden = YES;
        self.folder = nil;
        self.children = @[];
        [self removeFromSuperview];
        if (completion) {
            completion();
        }
    };

    if (!animated) {
        finish();
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = kOverlayAnimationDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        context.allowsImplicitAnimation = YES;
        self.alphaValue = 0.0;
        self.panelView.layer.transform = CATransform3DMakeScale(0.92, 0.92, 1.0);
    } completionHandler:finish];
}

- (void)reloadChildren:(NSArray<BrowserShortcutItem *> *)children {
    self.children = children ?: @[];
    [self updateChildLayout];
    [self.collectionView reloadData];
}

- (void)beginRenaming {
    self.renaming = YES;
    self.titleLabel.hidden = YES;
    self.titleField.hidden = NO;
    self.titleField.stringValue = self.folder.title ?: @"";
    [self.window makeFirstResponder:self.titleField];
}

- (void)updateChildLayout {
    BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
    CGFloat iconSize = appearance.iconSize;
    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:iconSize];
    CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:iconSize];
    // 与主网格完全一致：图标大小、左右间距、上下间距。
    self.flowLayout.itemSize = NSMakeSize(cellWidth, cellHeight);
    self.flowLayout.minimumInteritemSpacing = appearance.horizontalSpacing;
    self.flowLayout.minimumLineSpacing = appearance.verticalSpacing;
    self.flowLayout.sectionInset = NSEdgeInsetsMake(appearance.verticalSpacing,
                                                    appearance.horizontalSpacing,
                                                    appearance.verticalSpacing,
                                                    appearance.horizontalSpacing);

    NSUInteger count = self.children.count;
    NSUInteger columns = kFolderOverlayMinColumns;
    if (count > kFolderOverlayMinColumns) {
        columns = MIN(kFolderOverlayMaxColumns, count);
    }

    CGFloat hSpacing = self.flowLayout.minimumInteritemSpacing;
    CGFloat vSpacing = self.flowLayout.minimumLineSpacing;
    NSEdgeInsets inset = self.flowLayout.sectionInset;
    CGFloat contentWidth = columns * cellWidth + (columns - 1) * hSpacing + inset.left + inset.right;
    NSUInteger contentRows = count == 0 ? 1 : (count + columns - 1) / columns;
    NSUInteger rows = MAX(kFolderOverlayMinRows, contentRows);
    CGFloat titleBlock = 28.0 + 34.0 + 20.0;
    CGFloat contentHeight = titleBlock + rows * cellHeight + MAX((NSInteger)rows - 1, 0) * vSpacing
        + inset.top + inset.bottom;

    CGFloat maxWidth = MAX(kFolderOverlayMinWidth, NSWidth(self.bounds) * 0.88);
    CGFloat maxHeight = MAX(kFolderOverlayMinHeight, NSHeight(self.bounds) * 0.86);
    CGFloat width = MAX(kFolderOverlayMinWidth, MIN(contentWidth, maxWidth));
    CGFloat height = MAX(kFolderOverlayMinHeight, MIN(contentHeight, maxHeight));

    self.panelWidthConstraint.constant = width;
    self.panelHeightConstraint.constant = height;
    [self.panelView layoutSubtreeIfNeeded];
}

- (void)dimmingClicked:(NSClickGestureRecognizer *)recognizer {
    (void)recognizer;
    if (self.renaming) {
        [self commitRenameIfNeeded];
        return;
    }
    [self.delegate folderOverlayDidRequestClose:self];
}

- (void)titleClicked:(NSClickGestureRecognizer *)recognizer {
    (void)recognizer;
    [self beginRenaming];
}

- (void)titleEditingCommitted:(id)sender {
    (void)sender;
    [self commitRenameIfNeeded];
}

- (void)commitRenameIfNeeded {
    if (!self.renaming || !self.folder) {
        return;
    }
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.renaming = NO;
    self.titleField.hidden = YES;
    self.titleLabel.hidden = NO;
    if (title.length > 0) {
        self.titleLabel.stringValue = title;
        [self.delegate folderOverlay:self renameFolder:self.folder title:title];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;
    if (commandSelector == @selector(insertNewline:) || commandSelector == @selector(cancelOperation:)) {
        [self commitRenameIfNeeded];
        return YES;
    }
    return NO;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

#pragma mark - Collection

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    (void)section;
    return (NSInteger)self.children.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    BrowserShortcutCellView *cell = [collectionView makeItemWithIdentifier:@"FolderChildCell" forIndexPath:indexPath];
    BrowserShortcutItem *child = self.children[(NSUInteger)indexPath.item];
    [cell applyIconSize:[BrowserLaunchpadAppearance current].iconSize];
    [cell configureWithShortcut:child];

    __weak typeof(self) weakSelf = self;
    cell.onActivate = ^(BrowserShortcutItem *item, BOOL openInNewTab) {
        NSURL *url = [NSURL URLWithString:item.urlString];
        if (!url) {
            return;
        }
        [weakSelf.delegate folderOverlay:weakSelf openURL:url inNewTab:openInNewTab];
    };
    return cell;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint point = [self.collectionView convertPoint:event.locationInWindow fromView:nil];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath || indexPath.item < 0 || indexPath.item >= (NSInteger)self.children.count) {
        NSMenu *menu = [[NSMenu alloc] init];
        [menu addItemWithTitle:@"关闭" action:@selector(contextClose:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        [menu addItemWithTitle:@"重命名…" action:@selector(contextRename:) keyEquivalent:@""];
        menu.itemArray.lastObject.target = self;
        return menu;
    }

    BrowserShortcutItem *child = self.children[(NSUInteger)indexPath.item];
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"打开链接" action:@selector(contextOpenChild:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    menu.itemArray.lastObject.representedObject = child;
    [menu addItemWithTitle:@"在新标签页中打开" action:@selector(contextOpenChildInNewTab:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    menu.itemArray.lastObject.representedObject = child;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"编辑…" action:@selector(contextEditChild:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    menu.itemArray.lastObject.representedObject = child;
    [menu addItemWithTitle:@"移出文件夹" action:@selector(contextMoveOut:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    menu.itemArray.lastObject.representedObject = child;
    [menu addItemWithTitle:@"从快捷方式移除" action:@selector(contextRemoveChild:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    menu.itemArray.lastObject.representedObject = child;
    return menu;
}

- (void)contextClose:(id)sender {
    (void)sender;
    [self.delegate folderOverlayDidRequestClose:self];
}

- (void)contextRename:(id)sender {
    (void)sender;
    [self beginRenaming];
}

- (void)contextOpenChild:(NSMenuItem *)sender {
    BrowserShortcutItem *item = sender.representedObject;
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (url) {
        [self.delegate folderOverlay:self openURL:url inNewTab:NO];
    }
}

- (void)contextOpenChildInNewTab:(NSMenuItem *)sender {
    BrowserShortcutItem *item = sender.representedObject;
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (url) {
        [self.delegate folderOverlay:self openURL:url inNewTab:YES];
    }
}

- (void)contextEditChild:(NSMenuItem *)sender {
    BrowserShortcutItem *item = sender.representedObject;
    [self.delegate folderOverlay:self editShortcut:item];
}

- (void)contextMoveOut:(NSMenuItem *)sender {
    BrowserShortcutItem *item = sender.representedObject;
    [self.delegate folderOverlay:self moveShortcutToTopLevel:item];
}

- (void)contextRemoveChild:(NSMenuItem *)sender {
    BrowserShortcutItem *item = sender.representedObject;
    [self.delegate folderOverlay:self removeShortcut:item];
}

#pragma mark - Drag out

- (BOOL)beginDraggingChild:(BrowserShortcutItem *)child
                  fromView:(NSView *)view
                     event:(NSEvent *)event {
    if (!child || child.itemID.length == 0 || child.isFolder || !view || !event) {
        return NO;
    }
    if (self.folder == nil || self.renaming) {
        return NO;
    }
    BOOL found = NO;
    for (BrowserShortcutItem *item in self.children) {
        if ([item.itemID isEqualToString:child.itemID]) {
            found = YES;
            break;
        }
    }
    if (!found) {
        return NO;
    }

    self.draggingChildID = child.itemID;

    NSPasteboardItem *pasteboardItem = [[NSPasteboardItem alloc] init];
    [pasteboardItem setString:child.itemID forType:kFolderChildDragType];

    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboardItem];
    NSImage *image = [BrowserShortcutCellView draggingProxyImageFromContentView:view alpha:0.72];
    NSRect dragFrame = [BrowserShortcutCellView draggingProxyFrameFromContentView:view inView:self.collectionView];
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

    NSDraggingSession *session = [self.collectionView beginDraggingSessionWithItems:@[draggingItem]
                                                                              event:event
                                                                             source:self];
    if (!session) {
        self.draggingChildID = nil;
        return NO;
    }
    session.animatesToStartingPositionsOnCancelOrFail = NO;
    if ([self.delegate respondsToSelector:@selector(folderOverlay:didBeginDraggingChild:)]) {
        [self.delegate folderOverlay:self didBeginDraggingChild:child];
    }
    return YES;
}

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
    if (self.draggingChildID.length == 0 || !self.window) {
        return;
    }
    BrowserShortcutItem *child = nil;
    for (BrowserShortcutItem *item in self.children) {
        if ([item.itemID isEqualToString:self.draggingChildID]) {
            child = item;
            break;
        }
    }
    if (!child) {
        return;
    }

    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    // panel 即便 hidden 仍保留 frame，用来判断是否拖出面板区域。
    NSPoint localPoint = [self convertPoint:windowPoint fromView:nil];
    BOOL outsidePanel = !NSPointInRect(localPoint, self.panelView.frame);

    if (outsidePanel) {
        self.panelView.hidden = YES;
        self.dimmingView.hidden = YES;
    } else {
        self.panelView.hidden = NO;
        self.dimmingView.hidden = NO;
    }

    if ([self.delegate respondsToSelector:@selector(folderOverlay:draggingChild:movedToWindowPoint:outsidePanel:)]) {
        [self.delegate folderOverlay:self
                       draggingChild:child
                   movedToWindowPoint:windowPoint
                        outsidePanel:outsidePanel];
    }
}

- (void)draggingSession:(NSDraggingSession *)session
           endedAtPoint:(NSPoint)screenPoint
              operation:(NSDragOperation)operation {
    (void)session;
    (void)operation;
    if (self.draggingChildID.length == 0) {
        return;
    }

    BrowserShortcutItem *child = nil;
    for (BrowserShortcutItem *item in self.children) {
        if ([item.itemID isEqualToString:self.draggingChildID]) {
            child = item;
            break;
        }
    }
    self.draggingChildID = nil;

    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    NSPoint localPoint = [self convertPoint:windowPoint fromView:nil];
    BOOL outsidePanel = !NSPointInRect(localPoint, self.panelView.frame);

    self.panelView.hidden = NO;
    self.dimmingView.hidden = NO;

    if (child && [self.delegate respondsToSelector:@selector(folderOverlay:didEndDraggingChild:atWindowPoint:outsidePanel:)]) {
        [self.delegate folderOverlay:self
                 didEndDraggingChild:child
                       atWindowPoint:windowPoint
                        outsidePanel:outsidePanel];
    } else if (outsidePanel && child) {
        [self.delegate folderOverlay:self moveShortcutToTopLevel:child];
    }
}

@end
