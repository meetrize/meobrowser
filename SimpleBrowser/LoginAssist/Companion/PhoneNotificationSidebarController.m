#import "PhoneNotificationSidebarController.h"
#import "PhoneNotificationInboxSettings.h"
#import "PhoneNotificationInboxStore.h"
#import "PhoneNotificationItem.h"
#import "PhoneAppIconCache.h"
#import "CompanionChannel.h"
#import "BrowserTransientToast.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kResizeHandleWidth = 8.0;
static const NSTimeInterval kAutoMarkReadDelay = 0.5;
static const NSTimeInterval kSearchDebounce = 0.25;
static const NSTimeInterval kSyncPullTimeout = 20.0;

typedef NS_ENUM(NSInteger, PhoneNotificationSidebarRowKind) {
    PhoneNotificationSidebarRowKindSection = 0,
    PhoneNotificationSidebarRowKindItem = 1,
};

@interface PhoneNotificationSidebarRow : NSObject
@property (nonatomic, assign) PhoneNotificationSidebarRowKind kind;
@property (nonatomic, copy, nullable) NSString *sectionTitle;
@property (nonatomic, strong, nullable) PhoneNotificationItem *item;
@end

@implementation PhoneNotificationSidebarRow
@end

/// 左侧拖宽条：按 mouseDown 时绝对坐标计算宽度，避免增量漂移与夹紧死区。
@interface PhoneNotificationSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation PhoneNotificationSidebarResizeView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragging = YES;
    self.dragStartScreenX = [self screenXFromEvent:event];
    if (self.onDragBegan) {
        self.onDragBegan();
    }
    // 拖拽期间锁住指针为左右拉伸光标
    [[NSCursor resizeLeftRightCursor] push];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) {
        return;
    }
    CGFloat nowX = [self screenXFromEvent:event];
    // 正值 = 鼠标右移；左侧边缘右移 → 侧栏变窄
    CGFloat deltaFromStart = nowX - self.dragStartScreenX;
    if (self.onDragToOffset) {
        self.onDragToOffset(deltaFromStart);
    }
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!self.dragging) {
        return;
    }
    self.dragging = NO;
    [NSCursor pop];
    if (self.onDragEnded) {
        self.onDragEnded();
    }
}

- (CGFloat)screenXFromEvent:(NSEvent *)event {
    NSPoint inWindow = event.locationInWindow;
    if (self.window) {
        return [self.window convertPointToScreen:inWindow].x;
    }
    return inWindow.x;
}

@end

@interface PhoneNotificationSidebarBackgroundView : NSView
@property (nonatomic, copy, nullable) void (^onAppearanceChange)(void);
@end

@implementation PhoneNotificationSidebarBackgroundView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onAppearanceChange) {
        self.onAppearanceChange();
    }
}
@end

@interface PhoneNotificationSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *headerBar;
@property (nonatomic, strong) NSView *headerBottomSep;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *syncButton;
@property (nonatomic, strong) NSButton *categoryButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSSegmentedControl *bucketControl;
@property (nonatomic, strong) NSView *filterBar;
@property (nonatomic, strong) NSLayoutConstraint *filterBarHeightConstraint;
@property (nonatomic, strong) NSTextField *filterBarLabel;
@property (nonatomic, strong) NSButton *clearFilterButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSView *emptyContainer;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyDetailLabel;
@property (nonatomic, strong) NSButton *emptyActionButton;
@property (nonatomic, strong) NSButton *markAllReadButton;
@property (nonatomic, strong) NSButton *purgeReadButton;
@property (nonatomic, strong) PhoneNotificationSidebarResizeView *resizeHandle;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, strong) NSArray<PhoneNotificationSidebarRow *> *rows;
@property (nonatomic, copy, nullable) NSString *packageFilter;
@property (nonatomic, copy, nullable) NSString *packageFilterLabel;
@property (nonatomic, strong, nullable) dispatch_block_t searchDebounceBlock;
@property (nonatomic, strong, nullable) dispatch_block_t autoMarkReadBlock;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, copy, nullable) NSString *pendingRevealItemID;
@property (nonatomic, strong, nullable) NSView *highlightFlashView;
@property (nonatomic, assign) BOOL syncInFlight;
@property (nonatomic, copy, nullable) NSString *pendingSyncRequestID;
@property (nonatomic, strong, nullable) dispatch_block_t syncTimeoutBlock;
@end

@implementation PhoneNotificationSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [PhoneNotificationInboxSettings sharedSettings].sidebarWidth;
        _rows = @[];
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inboxOrChannelDidChange:)
                                                     name:PhoneNotificationInboxDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inboxOrChannelDidChange:)
                                                     name:CompanionChannelStateDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inboxOrChannelDidChange:)
                                                     name:PhoneAppIconCacheDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(phoneNotificationPullDidFinish:)
                                                     name:CompanionPhoneNotificationPullDidFinishNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
    [self cancelSyncTimeout];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;

    PhoneNotificationSidebarBackgroundView *background = [[PhoneNotificationSidebarBackgroundView alloc] initWithFrame:NSZeroRect];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.wantsLayer = YES;
    __weak typeof(self) weakSelfForAppearance = self;
    background.onAppearanceChange = ^{
        [weakSelfForAppearance applySidebarChromeColors];
        if (weakSelfForAppearance.visible) {
            [weakSelfForAppearance.tableView reloadData];
        }
    };
    [root addSubview:background];

    NSView *headerBar = [[NSView alloc] initWithFrame:NSZeroRect];
    headerBar.translatesAutoresizingMaskIntoConstraints = NO;
    headerBar.wantsLayer = YES;

    NSView *headerBottomSep = [[NSView alloc] initWithFrame:NSZeroRect];
    headerBottomSep.translatesAutoresizingMaskIntoConstraints = NO;
    headerBottomSep.wantsLayer = YES;
    headerBottomSep.identifier = @"headerBottomSep";

    NSTextField *title = [NSTextField labelWithString:@"手机通知"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    title.textColor = [NSColor labelColor];

    NSButton *close = [NSButton buttonWithTitle:@"⟩" target:self action:@selector(closeClicked:)];
    NSImage *closeImage = [self symbolNamed:@"sidebar.trailing"];
    if (closeImage) {
        close.image = closeImage;
        close.imagePosition = NSImageOnly;
        close.title = @"";
    }
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.bezelStyle = NSBezelStyleInline;
    close.bordered = NO;
    close.toolTip = @"关闭侧栏";
    if (@available(macOS 10.14, *)) {
        close.contentTintColor = [NSColor secondaryLabelColor];
    }

    NSButton *category = [NSButton buttonWithTitle:@"分类" target:self action:@selector(categoryButtonClicked:)];
    NSImage *categoryImage = [self symbolNamed:@"square.grid.2x2"];
    if (!categoryImage) {
        categoryImage = [self symbolNamed:@"rectangle.3.group"];
    }
    if (categoryImage) {
        category.image = categoryImage;
        category.imagePosition = NSImageOnly;
        category.title = @"";
    }
    category.translatesAutoresizingMaskIntoConstraints = NO;
    category.bezelStyle = NSBezelStyleInline;
    category.bordered = NO;
    category.toolTip = @"按 App 分类查看";
    if (@available(macOS 10.14, *)) {
        category.contentTintColor = [NSColor secondaryLabelColor];
    }

    NSButton *sync = [NSButton buttonWithTitle:@"同步" target:self action:@selector(syncButtonClicked:)];
    NSImage *syncImage = [self symbolNamed:@"arrow.triangle.2.circlepath"];
    if (!syncImage) {
        syncImage = [self symbolNamed:@"arrow.clockwise"];
    }
    if (syncImage) {
        sync.image = syncImage;
        sync.imagePosition = NSImageOnly;
        sync.title = @"";
    }
    sync.translatesAutoresizingMaskIntoConstraints = NO;
    sync.bezelStyle = NSBezelStyleInline;
    sync.bordered = NO;
    sync.toolTip = @"同步手机通知栏中仍可见的通知（断线期间已划掉的无法找回）";
    if (@available(macOS 10.14, *)) {
        sync.contentTintColor = [NSColor secondaryLabelColor];
    }

    [headerBar addSubview:title];
    [headerBar addSubview:sync];
    [headerBar addSubview:category];
    [headerBar addSubview:close];
    [headerBar addSubview:headerBottomSep];

    SBTextField *search = [SBTextField standardField];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.placeholderString = @"搜索通知…";
    search.delegate = self;
    search.usesCompactVerticalTextInsets = YES;

    NSSegmentedControl *bucket = [NSSegmentedControl segmentedControlWithLabels:@[@"全部", @"未读", @"验证码", @"今日", @"钉选"]
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:@selector(bucketChanged:)];
    bucket.translatesAutoresizingMaskIntoConstraints = NO;
    bucket.segmentStyle = NSSegmentStyleRounded;
    bucket.selectedSegment = 0;
    [bucket setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *filterBar = [[NSView alloc] initWithFrame:NSZeroRect];
    filterBar.translatesAutoresizingMaskIntoConstraints = NO;
    filterBar.hidden = YES;
    filterBar.wantsLayer = YES;
    filterBar.layer.cornerRadius = 8.0;

    NSTextField *filterLabel = [NSTextField labelWithString:@""];
    filterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    filterLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    filterLabel.textColor = [NSColor secondaryLabelColor];
    filterLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSButton *clearFilter = [NSButton buttonWithTitle:@"全部" target:self action:@selector(clearPackageFilterClicked:)];
    clearFilter.translatesAutoresizingMaskIntoConstraints = NO;
    clearFilter.bezelStyle = NSBezelStyleInline;
    clearFilter.bordered = NO;
    clearFilter.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    if (@available(macOS 10.14, *)) {
        clearFilter.contentTintColor = [NSColor systemBlueColor];
    }
    [filterBar addSubview:filterLabel];
    [filterBar addSubview:clearFilter];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.backgroundColor = [NSColor clearColor];
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.contentInsets = NSEdgeInsetsZero;
    if (@available(macOS 11.0, *)) {
        scroll.scrollerInsets = NSEdgeInsetsZero;
    }

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.backgroundColor = [NSColor clearColor];
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsEmptySelection = YES;
    table.rowHeight = 72;
    table.intercellSpacing = NSMakeSize(0, 0);
    if (@available(macOS 11.0, *)) {
        table.style = NSTableViewStylePlain;
    }
    table.target = self;
    table.doubleAction = @selector(tableDoubleClicked:);
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = 280;
    [table addTableColumn:col];
    table.dataSource = self;
    table.delegate = self;
    table.menu = [self buildContextMenu];
    scroll.documentView = table;

    NSView *empty = [[NSView alloc] initWithFrame:NSZeroRect];
    empty.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *emptyTitle = [NSTextField wrappingLabelWithString:@""];
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    emptyTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;

    NSTextField *emptyDetail = [NSTextField wrappingLabelWithString:@""];
    emptyDetail.translatesAutoresizingMaskIntoConstraints = NO;
    emptyDetail.font = [NSFont systemFontOfSize:12];
    emptyDetail.textColor = [NSColor tertiaryLabelColor];
    emptyDetail.alignment = NSTextAlignmentCenter;

    NSButton *emptyAction = [NSButton buttonWithTitle:@"打开互联设置" target:self action:@selector(emptyActionClicked:)];
    emptyAction.translatesAutoresizingMaskIntoConstraints = NO;
    emptyAction.bezelStyle = NSBezelStyleRounded;
    emptyAction.hidden = YES;

    [empty addSubview:emptyTitle];
    [empty addSubview:emptyDetail];
    [empty addSubview:emptyAction];

    NSButton *markAll = [NSButton buttonWithTitle:@"全部已读" target:self action:@selector(markAllReadClicked:)];
    markAll.translatesAutoresizingMaskIntoConstraints = NO;
    markAll.bezelStyle = NSBezelStyleInline;
    markAll.bordered = NO;
    markAll.font = [NSFont systemFontOfSize:12];

    NSButton *purge = [NSButton buttonWithTitle:@"清空已读" target:self action:@selector(purgeReadClicked:)];
    purge.translatesAutoresizingMaskIntoConstraints = NO;
    purge.bezelStyle = NSBezelStyleInline;
    purge.bordered = NO;
    purge.font = [NSFont systemFontOfSize:12];

    PhoneNotificationSidebarResizeView *handle = [[PhoneNotificationSidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
        weakSelf.isResizingWidth = YES;
    };
    handle.onDragToOffset = ^(CGFloat mouseDeltaXFromStart) {
        // 鼠标右移 → 左侧边缘右移 → 宽度减小
        [weakSelf applyWidth:weakSelf.dragStartWidth - mouseDeltaXFromStart];
    };
    handle.onDragEnded = ^{
        weakSelf.isResizingWidth = NO;
        [weakSelf persistWidth];
    };

    NSView *edgeSeparator = [[NSView alloc] initWithFrame:NSZeroRect];
    edgeSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    edgeSeparator.wantsLayer = YES;
    edgeSeparator.identifier = @"edgeSep";

    [background addSubview:headerBar];
    [background addSubview:search];
    [background addSubview:bucket];
    [background addSubview:filterBar];
    [background addSubview:scroll];
    [background addSubview:empty];
    [background addSubview:markAll];
    [background addSubview:purge];
    [root addSubview:handle];
    [root addSubview:edgeSeparator];

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;
    NSLayoutConstraint *filterHeight = [filterBar.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:root.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],

        [edgeSeparator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [edgeSeparator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edgeSeparator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edgeSeparator.widthAnchor constraintEqualToConstant:1],

        [headerBar.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [headerBar.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [headerBar.topAnchor constraintEqualToAnchor:background.topAnchor],
        [headerBar.heightAnchor constraintEqualToConstant:44],

        [title.leadingAnchor constraintEqualToAnchor:headerBar.leadingAnchor constant:14],
        [title.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:headerBar.trailingAnchor constant:-10],
        [close.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],
        [category.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-2],
        [category.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [category.widthAnchor constraintEqualToConstant:28],
        [category.heightAnchor constraintEqualToConstant:28],
        [sync.trailingAnchor constraintEqualToAnchor:category.leadingAnchor constant:-2],
        [sync.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [sync.widthAnchor constraintEqualToConstant:28],
        [sync.heightAnchor constraintEqualToConstant:28],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:sync.leadingAnchor constant:-8],

        [headerBottomSep.leadingAnchor constraintEqualToAnchor:headerBar.leadingAnchor],
        [headerBottomSep.trailingAnchor constraintEqualToAnchor:headerBar.trailingAnchor],
        [headerBottomSep.bottomAnchor constraintEqualToAnchor:headerBar.bottomAnchor],
        [headerBottomSep.heightAnchor constraintEqualToConstant:1],

        [search.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:12],
        [search.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-12],
        [search.topAnchor constraintEqualToAnchor:headerBar.bottomAnchor constant:10],
        [search.heightAnchor constraintEqualToConstant:26],

        [bucket.leadingAnchor constraintEqualToAnchor:search.leadingAnchor],
        [bucket.trailingAnchor constraintEqualToAnchor:search.trailingAnchor],
        [bucket.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],

        [filterBar.leadingAnchor constraintEqualToAnchor:search.leadingAnchor],
        [filterBar.trailingAnchor constraintEqualToAnchor:search.trailingAnchor],
        [filterBar.topAnchor constraintEqualToAnchor:bucket.bottomAnchor constant:6],
        filterHeight,

        [filterLabel.leadingAnchor constraintEqualToAnchor:filterBar.leadingAnchor constant:10],
        [filterLabel.centerYAnchor constraintEqualToAnchor:filterBar.centerYAnchor],
        [filterLabel.trailingAnchor constraintLessThanOrEqualToAnchor:clearFilter.leadingAnchor constant:-8],
        [clearFilter.trailingAnchor constraintEqualToAnchor:filterBar.trailingAnchor constant:-8],
        [clearFilter.centerYAnchor constraintEqualToAnchor:filterBar.centerYAnchor],

        [scroll.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:filterBar.bottomAnchor constant:6],
        [scroll.bottomAnchor constraintEqualToAnchor:markAll.topAnchor constant:-6],

        [empty.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [empty.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [empty.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [empty.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],

        [emptyTitle.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor constant:20],
        [emptyTitle.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor constant:-20],
        [emptyTitle.centerYAnchor constraintEqualToAnchor:empty.centerYAnchor constant:-28],
        [emptyDetail.leadingAnchor constraintEqualToAnchor:emptyTitle.leadingAnchor],
        [emptyDetail.trailingAnchor constraintEqualToAnchor:emptyTitle.trailingAnchor],
        [emptyDetail.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:8],
        [emptyAction.topAnchor constraintEqualToAnchor:emptyDetail.bottomAnchor constant:14],
        [emptyAction.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],

        [markAll.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:12],
        [markAll.bottomAnchor constraintEqualToAnchor:background.bottomAnchor constant:-10],
        [purge.leadingAnchor constraintEqualToAnchor:markAll.trailingAnchor constant:12],
        [purge.centerYAnchor constraintEqualToAnchor:markAll.centerYAnchor],
    ]];

    self.view = root;
    self.backgroundView = background;
    self.headerBar = headerBar;
    self.headerBottomSep = headerBottomSep;
    self.titleLabel = title;
    self.syncButton = sync;
    self.categoryButton = category;
    self.closeButton = close;
    self.searchField = search;
    self.bucketControl = bucket;
    self.filterBar = filterBar;
    self.filterBarHeightConstraint = filterHeight;
    self.filterBarLabel = filterLabel;
    self.clearFilterButton = clearFilter;
    self.scrollView = scroll;
    self.tableView = table;
    self.emptyContainer = empty;
    self.emptyTitleLabel = emptyTitle;
    self.emptyDetailLabel = emptyDetail;
    self.emptyActionButton = emptyAction;
    self.markAllReadButton = markAll;
    self.purgeReadButton = purge;
    self.resizeHandle = handle;

    [self applySidebarChromeColors];
    [self reloadList];
    [self updateSyncButtonState];
}

- (void)applySidebarChromeColors {
    // 浅色：纯白，让灰色分隔线更清晰；深色：略抬升的内容底，避免发灰糊成一片
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName match = [self.backgroundView.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        dark = (match == NSAppearanceNameDarkAqua);
    }
    NSColor *bg = dark ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0] : [NSColor whiteColor];
    NSColor *edge = dark
        ? [NSColor colorWithCalibratedWhite:0.28 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.86 alpha:1.0];
    self.backgroundView.layer.backgroundColor = bg.CGColor;
    NSView *edgeSep = nil;
    for (NSView *sub in self.view.subviews) {
        if ([sub.identifier isEqualToString:@"edgeSep"]) {
            edgeSep = sub;
            break;
        }
    }
    edgeSep.layer.backgroundColor = edge.CGColor;

    // 标题栏浅底：比内容区略灰一点，区分工具区与列表
    NSColor *headerBG = dark
        ? [NSColor colorWithCalibratedWhite:0.20 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.955 alpha:1.0];
    NSColor *headerLine = dark
        ? [NSColor colorWithCalibratedWhite:0.30 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    self.headerBar.layer.backgroundColor = headerBG.CGColor;
    self.headerBottomSep.layer.backgroundColor = headerLine.CGColor;

    if (self.filterBar.wantsLayer) {
        NSColor *chip = dark
            ? [NSColor colorWithCalibratedWhite:0.22 alpha:1.0]
            : [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
        self.filterBar.layer.backgroundColor = chip.CGColor;
    }
}

- (void)viewAppearanceChanged {
    [self applySidebarChromeColors];
    if (self.visible) {
        [self.tableView reloadData];
    }
}

- (nullable NSImage *)symbolNamed:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return image ? [image imageWithSymbolConfiguration:config] : nil;
    }
    return nil;
}

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"通知"];
    [menu addItemWithTitle:@"复制正文" action:@selector(copyBodyClicked:) keyEquivalent:@""];
    [menu addItemWithTitle:@"复制验证码" action:@selector(copyOTPClicked:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"钉选 / 取消钉选" action:@selector(togglePinClicked:) keyEquivalent:@""];
    [menu addItemWithTitle:@"标记已读" action:@selector(markReadClicked:) keyEquivalent:@""];
    [menu addItemWithTitle:@"删除" action:@selector(deleteClicked:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"静音此 App" action:@selector(muteAppClicked:) keyEquivalent:@""];
    for (NSMenuItem *item in menu.itemArray) {
        item.target = self;
    }
    return menu;
}

#pragma mark - Visibility

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    BOOL already = (self.visible == visible);
    if (already && visible && self.widthConstraint.constant > 1) {
        [self reloadList];
        return;
    }
    if (already && !visible && self.widthConstraint.constant < 1) {
        return;
    }

    self.visible = visible;
    if (visible) {
        self.currentWidth = [PhoneNotificationInboxSettings sharedSettings].sidebarWidth;
        self.view.hidden = NO;
        [self applySidebarChromeColors];
        [self installKeyMonitor];
    } else {
        [self uninstallKeyMonitor];
        [self cancelAutoMarkRead];
    }
    CGFloat target = visible ? self.currentWidth : 0;

    void (^finish)(void) = ^{
        if (!self.visible) {
            self.view.hidden = YES;
        } else {
            [self reloadList];
            if (self.pendingRevealItemID.length > 0) {
                NSString *pending = self.pendingRevealItemID;
                self.pendingRevealItemID = nil;
                [self selectAndHighlightItemID:pending];
            }
        }
    };

    if (animated && self.view.superview) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            self.widthConstraint.animator.constant = target;
        } completionHandler:finish];
    } else {
        self.widthConstraint.constant = target;
        self.view.hidden = !visible;
        finish();
    }
}

- (void)applyWidth:(CGFloat)width {
    if (!self.visible) {
        return;
    }
    CGFloat next = MIN(kSidebarMaxWidth, MAX(kSidebarMinWidth, width));
    if (fabs(next - self.widthConstraint.constant) < 0.01) {
        self.currentWidth = next;
        return;
    }
    self.currentWidth = next;
    // 拖拽时关闭隐式动画，边缘与鼠标同步
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        context.allowsImplicitAnimation = NO;
        self.widthConstraint.constant = next;
        [self.view.superview layoutSubtreeIfNeeded];
    } completionHandler:nil];
    if (self.rows.count > 0) {
        NSIndexSet *all = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.rows.count)];
        [self.tableView noteHeightOfRowsWithIndexesChanged:all];
    }
}

- (void)persistWidth {
    [PhoneNotificationInboxSettings sharedSettings].sidebarWidth = self.currentWidth;
    if ([self.delegate respondsToSelector:@selector(notificationSidebar:didChangeWidth:)]) {
        [self.delegate notificationSidebar:self didChangeWidth:self.currentWidth];
    }
}

- (void)installKeyMonitor {
    if (self.localKeyMonitor) return;
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                 handler:^NSEvent * _Nullable(NSEvent *event) {
        if (event.keyCode == 53 && weakSelf.visible) { // Esc
            NSResponder *first = weakSelf.view.window.firstResponder;
            if ([first isKindOfClass:[NSTextView class]] || [first isKindOfClass:[NSTextField class]]) {
                return event;
            }
            [weakSelf closeClicked:nil];
            return nil;
        }
        return event;
    }];
}

- (void)uninstallKeyMonitor {
    if (self.localKeyMonitor) {
        [NSEvent removeMonitor:self.localKeyMonitor];
        self.localKeyMonitor = nil;
    }
}

#pragma mark - Data

- (PhoneNotificationInboxBucket)selectedBucket {
    switch (self.bucketControl.selectedSegment) {
        case 1: return PhoneNotificationInboxBucketUnread;
        case 2: return PhoneNotificationInboxBucketOTP;
        case 3: return PhoneNotificationInboxBucketToday;
        case 4: return PhoneNotificationInboxBucketPinned;
        default: return PhoneNotificationInboxBucketAll;
    }
}

- (void)reloadList {
    PhoneNotificationFilter *filter = [[PhoneNotificationFilter alloc] init];
    filter.bucket = [self selectedBucket];
    filter.query = self.searchField.stringValue;
    filter.packageName = self.packageFilter;
    NSArray<PhoneNotificationItem *> *items = [[PhoneNotificationInboxStore sharedStore] itemsMatchingFilter:filter];
    self.rows = [self buildRowsFromItems:items];
    [self updatePackageFilterChrome];
    [self.tableView reloadData];
    [self refreshEmptyState];
    [self scheduleAutoMarkRead];
}

- (void)updatePackageFilterChrome {
    BOOL active = self.packageFilter.length > 0;
    self.filterBar.hidden = !active;
    self.filterBarHeightConstraint.constant = active ? 28.0 : 0.0;
    if (active) {
        NSString *name = self.packageFilterLabel.length > 0 ? self.packageFilterLabel : self.packageFilter;
        self.filterBarLabel.stringValue = [NSString stringWithFormat:@"正在查看 · %@", name];
    }
    if (@available(macOS 10.14, *)) {
        self.categoryButton.contentTintColor = active ? [NSColor systemBlueColor] : [NSColor secondaryLabelColor];
    }
    self.categoryButton.toolTip = active
        ? [NSString stringWithFormat:@"当前：%@（点击切换分类）", self.packageFilterLabel ?: self.packageFilter]
        : @"按 App 分类查看";
}

- (NSArray<PhoneNotificationSidebarRow *> *)buildRowsFromItems:(NSArray<PhoneNotificationItem *> *)items {
    // 默认时间序平铺，不再按 App 分 section
    NSMutableArray<PhoneNotificationSidebarRow *> *rows = [NSMutableArray arrayWithCapacity:items.count];
    for (PhoneNotificationItem *item in items) {
        PhoneNotificationSidebarRow *row = [[PhoneNotificationSidebarRow alloc] init];
        row.kind = PhoneNotificationSidebarRowKindItem;
        row.item = item;
        [rows addObject:row];
    }
    return rows;
}

/// 收件箱中出现过的 App（按当前分桶+搜索，不含 package 过滤），用于分类菜单。
- (NSArray<NSDictionary *> *)appCategoryEntries {
    PhoneNotificationFilter *filter = [[PhoneNotificationFilter alloc] init];
    filter.bucket = [self selectedBucket];
    filter.query = self.searchField.stringValue;
    filter.packageName = nil;
    NSArray<PhoneNotificationItem *> *items = [[PhoneNotificationInboxStore sharedStore] itemsMatchingFilter:filter];

    NSMutableDictionary<NSString *, NSMutableDictionary *> *map = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (PhoneNotificationItem *item in items) {
        NSString *pkg = item.packageName.length > 0 ? item.packageName : @"unknown";
        NSMutableDictionary *entry = map[pkg];
        if (!entry) {
            entry = [@{
                @"packageName": pkg,
                @"label": item.appLabel.length > 0 ? item.appLabel : pkg,
                @"count": @0,
            } mutableCopy];
            map[pkg] = entry;
            [order addObject:pkg];
        }
        entry[@"count"] = @([entry[@"count"] integerValue] + 1);
        if (item.appLabel.length > 0) {
            entry[@"label"] = item.appLabel;
        }
    }

    [order sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *la = map[a][@"label"] ?: a;
        NSString *lb = map[b][@"label"] ?: b;
        return [la localizedStandardCompare:lb];
    }];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *pkg in order) {
        [result addObject:[map[pkg] copy]];
    }
    return result;
}

- (void)refreshEmptyState {
    BOOL inboxOn = [PhoneNotificationInboxSettings sharedSettings].inboxEnabled;
    CompanionChannelState state = [CompanionChannel sharedChannel].state;
    NSUInteger storeCount = [[PhoneNotificationInboxStore sharedStore] itemCount];
    BOOL hasRows = self.rows.count > 0;

    BOOL showEmpty = NO;
    self.emptyActionButton.hidden = YES;

    if (!inboxOn) {
        showEmpty = YES;
        self.emptyTitleLabel.stringValue = @"收件箱已关闭";
        self.emptyDetailLabel.stringValue = @"可在登录助手 › 通知镜像中重新开启「保存到收件箱」。";
    } else if (storeCount == 0) {
        showEmpty = YES;
        if (state != CompanionChannelStateConnected) {
            self.emptyTitleLabel.stringValue = @"互联未连接";
            self.emptyDetailLabel.stringValue = @"配对手机后，通知会显示在这里。";
            self.emptyActionButton.hidden = NO;
        } else {
            self.emptyTitleLabel.stringValue = @"等待手机通知…";
            self.emptyDetailLabel.stringValue = @"手机 Companion 设为「全部通知」后消息会出现在此；验证码默认也会入库。";
        }
    } else if (!hasRows) {
        showEmpty = YES;
        self.emptyTitleLabel.stringValue = @"无匹配结果";
        self.emptyDetailLabel.stringValue = self.packageFilter.length > 0
            ? @"该 App 下暂无匹配通知，可点「全部」清除分类。"
            : @"试试其他分桶或清空搜索。";
    }

    self.emptyContainer.hidden = !showEmpty;
    self.scrollView.hidden = showEmpty;
    BOOL footerEnabled = storeCount > 0 && inboxOn;
    self.markAllReadButton.enabled = footerEnabled;
    self.purgeReadButton.enabled = footerEnabled;
}

- (nullable PhoneNotificationItem *)itemAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.rows.count) return nil;
    PhoneNotificationSidebarRow *r = self.rows[(NSUInteger)row];
    return r.kind == PhoneNotificationSidebarRowKindItem ? r.item : nil;
}

- (nullable PhoneNotificationItem *)clickedOrSelectedItem {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) row = self.tableView.selectedRow;
    return [self itemAtRow:row];
}

- (nullable NSString *)selectedItemID {
    return [self itemAtRow:self.tableView.selectedRow].itemID;
}

- (void)revealItemID:(NSString *)itemID {
    if (!self.visible) {
        self.pendingRevealItemID = itemID;
        [self setVisible:YES animated:YES];
        return;
    }
    [self reloadList];
    [self selectAndHighlightItemID:itemID];
}

- (void)selectAndHighlightItemID:(nullable NSString *)itemID {
    if (itemID.length == 0) {
        self.bucketControl.selectedSegment = 0;
        [self reloadList];
        return;
    }

    NSString *resolvedID = itemID;
    if ([itemID hasPrefix:@"otp-code:"]) {
        NSString *code = [itemID substringFromIndex:@"otp-code:".length];
        resolvedID = [self latestOTPItemIDForCode:code] ?: itemID;
        self.bucketControl.selectedSegment = 2; // 验证码
        [self reloadList];
    } else {
        self.bucketControl.selectedSegment = 0;
        [self reloadList];
    }

    NSInteger targetRow = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        PhoneNotificationItem *item = [self itemAtRow:i];
        if (item && [item.itemID isEqualToString:resolvedID]) {
            targetRow = i;
            break;
        }
        // otp-code 回退：按 code 匹配
        if ([itemID hasPrefix:@"otp-code:"] && item.otpCode.length > 0) {
            NSString *code = [itemID substringFromIndex:@"otp-code:".length];
            if ([item.otpCode isEqualToString:code]) {
                targetRow = i;
                break;
            }
        }
    }
    if (targetRow == NSNotFound) {
        return;
    }
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)targetRow] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:targetRow];
    [self flashHighlightAtRow:targetRow];
}

- (nullable NSString *)latestOTPItemIDForCode:(NSString *)code {
    if (code.length == 0) return nil;
    PhoneNotificationFilter *filter = [[PhoneNotificationFilter alloc] init];
    filter.bucket = PhoneNotificationInboxBucketOTP;
    NSArray<PhoneNotificationItem *> *items = [[PhoneNotificationInboxStore sharedStore] itemsMatchingFilter:filter];
    for (PhoneNotificationItem *item in items) {
        if ([item.otpCode isEqualToString:code]) {
            return item.itemID;
        }
    }
    return nil;
}

- (void)flashHighlightAtRow:(NSInteger)row {
    NSRect rowRect = [self.tableView rectOfRow:row];
    if (NSIsEmptyRect(rowRect)) return;
    NSView *flash = [[NSView alloc] initWithFrame:rowRect];
    flash.wantsLayer = YES;
    flash.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.22].CGColor;
    flash.layer.cornerRadius = 6;
    [self.tableView addSubview:flash];
    self.highlightFlashView = flash;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.7;
        flash.animator.alphaValue = 0;
    } completionHandler:^{
        [flash removeFromSuperview];
        if (self.highlightFlashView == flash) {
            self.highlightFlashView = nil;
        }
    }];
}

#pragma mark - Auto mark read

- (void)cancelAutoMarkRead {
    if (self.autoMarkReadBlock) {
        dispatch_block_cancel(self.autoMarkReadBlock);
        self.autoMarkReadBlock = nil;
    }
}

- (void)scheduleAutoMarkRead {
    [self cancelAutoMarkRead];
    if (!self.visible || ![PhoneNotificationInboxSettings sharedSettings].autoMarkReadOnVisible) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf performAutoMarkRead];
    });
    self.autoMarkReadBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAutoMarkReadDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)performAutoMarkRead {
    if (!self.visible) return;
    PhoneNotificationInboxStore *store = [PhoneNotificationInboxStore sharedStore];
    for (PhoneNotificationSidebarRow *row in self.rows) {
        if (row.kind == PhoneNotificationSidebarRowKindItem && row.item && !row.item.read) {
            [store setRead:YES forId:row.item.itemID];
        }
    }
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.rows.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    PhoneNotificationSidebarRow *r = self.rows[(NSUInteger)row];
    if (r.kind == PhoneNotificationSidebarRowKindSection) return 26;
    return [self heightForItem:r.item tableWidth:MAX(180.0, tableView.bounds.size.width)];
}

- (CGFloat)contentTextWidthForTableWidth:(CGFloat)tableWidth {
    // leading 10 + icon 28 + gap 6 + trailing 10
    return MAX(120.0, tableWidth - 10 - 28 - 6 - 10);
}

- (CGFloat)heightForWrappedText:(NSString *)text font:(NSFont *)font width:(CGFloat)width {
    if (text.length == 0 || width < 1) {
        return 0;
    }
    NSRect bounds = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                    attributes:@{NSFontAttributeName: font}];
    return ceil(MAX(font.pointSize + 2.0, bounds.size.height));
}

- (CGFloat)heightForItem:(PhoneNotificationItem *)item tableWidth:(CGFloat)tableWidth {
    if (!item) return 64;
    CGFloat textW = [self contentTextWidthForTableWidth:tableWidth];
    // 时间列约占 44pt
    CGFloat titleW = MAX(80.0, textW - 48.0);

    NSString *meta = [self metaLineForItem:item];
    NSString *title = [self displayTitleForItem:item];
    NSString *body = [self displayBodyForItem:item];

    NSFont *metaFont = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    NSFont *titleFont = [NSFont systemFontOfSize:13 weight:item.read ? NSFontWeightMedium : NSFontWeightSemibold];
    NSFont *bodyFont = (item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0)
        ? [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold]
        : [NSFont systemFontOfSize:12];

    CGFloat top = 10.0;
    CGFloat metaH = [self heightForWrappedText:meta font:metaFont width:titleW];
    CGFloat titleH = [self heightForWrappedText:title font:titleFont width:textW];
    CGFloat bodyH = [self heightForWrappedText:body font:bodyFont width:textW];
    CGFloat otpBtn = (item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0) ? 30.0 : 0.0;
    CGFloat gaps = 4.0 + (bodyH > 0 ? 4.0 : 0.0) + (otpBtn > 0 ? 4.0 : 0.0);
    CGFloat bottom = 12.0;
    CGFloat contentH = top + metaH + gaps + titleH + bodyH + otpBtn + bottom;
    CGFloat iconMin = 10.0 + 28.0 + 12.0;
    return MAX(iconMin, contentH);
}

- (NSString *)metaLineForItem:(PhoneNotificationItem *)item {
    NSString *app = item.appLabel.length > 0 ? item.appLabel
        : (item.packageName.length > 0 ? item.packageName : @"通知");
    if (item.pinned) {
        return [NSString stringWithFormat:@"📌 %@", app];
    }
    return app;
}

- (NSString *)displayTitleForItem:(PhoneNotificationItem *)item {
    if (item.title.length > 0) {
        return item.title;
    }
    if (item.kind == PhoneNotificationItemKindOTP) {
        return @"验证码";
    }
    return item.appLabel.length > 0 ? item.appLabel : @"通知";
}

- (NSString *)displayBodyForItem:(PhoneNotificationItem *)item {
    if (item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0) {
        return item.otpCode;
    }
    return item.body.length > 0 ? item.body : @"";
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    (void)tableView;
    return [self itemAtRow:row] != nil;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    PhoneNotificationSidebarRow *r = self.rows[(NSUInteger)row];
    if (r.kind == PhoneNotificationSidebarRowKindSection) {
        NSTextField *label = [tableView makeViewWithIdentifier:@"section" owner:self];
        if (!label) {
            label = [NSTextField labelWithString:@""];
            label.identifier = @"section";
            label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
            label.textColor = [NSColor secondaryLabelColor];
        }
        label.stringValue = [NSString stringWithFormat:@"  %@", r.sectionTitle ?: @""];
        return label;
    }

    PhoneNotificationItem *item = r.item;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"item.v9" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"item.v9";

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.identifier = @"appIcon";
        icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        icon.wantsLayer = YES;
        icon.layer.cornerRadius = 7.0;
        icon.layer.masksToBounds = YES;

        // 未读点叠在图标左上角，不额外占左右 padding
        NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.wantsLayer = YES;
        dot.layer.cornerRadius = 3.5;
        dot.identifier = @"unreadDot";

        NSTextField *meta = [NSTextField wrappingLabelWithString:@""];
        meta.translatesAutoresizingMaskIntoConstraints = NO;
        meta.identifier = @"meta";
        meta.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        meta.textColor = [NSColor tertiaryLabelColor];
        meta.maximumNumberOfLines = 1;
        meta.cell.lineBreakMode = NSLineBreakByTruncatingTail;

        NSTextField *title = [NSTextField wrappingLabelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.identifier = @"title";
        title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        title.maximumNumberOfLines = 0;
        title.cell.wraps = YES;
        title.cell.usesSingleLineMode = NO;
        title.lineBreakMode = NSLineBreakByWordWrapping;
        [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        [title setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationVertical];

        NSTextField *body = [NSTextField wrappingLabelWithString:@""];
        body.translatesAutoresizingMaskIntoConstraints = NO;
        body.identifier = @"body";
        body.font = [NSFont systemFontOfSize:12];
        body.textColor = [NSColor secondaryLabelColor];
        body.maximumNumberOfLines = 0;
        body.cell.wraps = YES;
        body.cell.usesSingleLineMode = NO;
        body.lineBreakMode = NSLineBreakByWordWrapping;
        [body setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [body setContentHuggingPriority:NSLayoutPriorityDefaultLow
                         forOrientation:NSLayoutConstraintOrientationVertical];

        NSTextField *time = [NSTextField labelWithString:@""];
        time.translatesAutoresizingMaskIntoConstraints = NO;
        time.identifier = @"time";
        time.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        time.textColor = [NSColor tertiaryLabelColor];
        time.alignment = NSTextAlignmentRight;
        [time setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSButton *copyOTP = [NSButton buttonWithTitle:@"复制验证码" target:self action:@selector(copyOTPFromCell:)];
        copyOTP.translatesAutoresizingMaskIntoConstraints = NO;
        copyOTP.identifier = @"copyOTP";
        copyOTP.bezelStyle = NSBezelStyleInline;
        copyOTP.bordered = NO;
        copyOTP.wantsLayer = YES;
        copyOTP.layer.cornerRadius = 5.0;
        copyOTP.layer.masksToBounds = YES;
        copyOTP.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        copyOTP.hidden = YES;

        NSView *sep = [[NSView alloc] initWithFrame:NSZeroRect];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        sep.wantsLayer = YES;
        sep.identifier = @"rowSep";

        [cell addSubview:icon];
        [cell addSubview:dot];
        [cell addSubview:meta];
        [cell addSubview:title];
        [cell addSubview:body];
        [cell addSubview:time];
        [cell addSubview:copyOTP];
        [cell addSubview:sep];
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [icon.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
            [icon.widthAnchor constraintEqualToConstant:28],
            [icon.heightAnchor constraintEqualToConstant:28],
            [dot.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor constant:-1],
            [dot.topAnchor constraintEqualToAnchor:icon.topAnchor constant:-1],
            [dot.widthAnchor constraintEqualToConstant:7],
            [dot.heightAnchor constraintEqualToConstant:7],
            [meta.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6],
            [meta.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
            [meta.trailingAnchor constraintEqualToAnchor:time.leadingAnchor constant:-4],
            [time.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [time.centerYAnchor constraintEqualToAnchor:meta.centerYAnchor],
            [time.widthAnchor constraintGreaterThanOrEqualToConstant:36],
            [title.leadingAnchor constraintEqualToAnchor:meta.leadingAnchor],
            [title.topAnchor constraintEqualToAnchor:meta.bottomAnchor constant:3],
            [title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
            [body.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [copyOTP.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [copyOTP.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:6],
            [copyOTP.heightAnchor constraintEqualToConstant:24],
            [copyOTP.widthAnchor constraintGreaterThanOrEqualToConstant:88],
            [sep.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [sep.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [sep.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor],
            [sep.heightAnchor constraintEqualToConstant:1],
        ]];
    }

    NSView *dot = [self subview:cell id:@"unreadDot"];
    NSImageView *icon = (NSImageView *)[self subview:cell id:@"appIcon"];
    NSTextField *meta = (NSTextField *)[self subview:cell id:@"meta"];
    NSTextField *title = (NSTextField *)[self subview:cell id:@"title"];
    NSTextField *body = (NSTextField *)[self subview:cell id:@"body"];
    NSTextField *time = (NSTextField *)[self subview:cell id:@"time"];
    NSButton *copyOTP = (NSButton *)[self subview:cell id:@"copyOTP"];
    NSView *sep = [self subview:cell id:@"rowSep"];
    if (sep.wantsLayer) {
        BOOL dark = NO;
        if (@available(macOS 10.14, *)) {
            NSAppearanceName match = [cell.effectiveAppearance
                bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            dark = (match == NSAppearanceNameDarkAqua);
        }
        NSColor *sepColor = dark
            ? [NSColor colorWithCalibratedWhite:0.30 alpha:1.0]
            : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];
        sep.layer.backgroundColor = sepColor.CGColor;
    }

    sep.hidden = NO;

    BOOL unread = !item.read;
    dot.hidden = !unread;
    if (@available(macOS 10.14, *)) {
        dot.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
    } else {
        dot.layer.backgroundColor = [NSColor blueColor].CGColor;
    }

    BOOL isOTP = (item.kind == PhoneNotificationItemKindOTP) ||
                 [item.packageName isEqualToString:@"otp"];
    if (isOTP) {
        icon.image = [PhoneAppIconCache otpPlaceholderImage];
    } else {
        NSImage *cached = [[PhoneAppIconCache sharedCache] imageForPackage:item.packageName];
        icon.image = cached ?: [PhoneAppIconCache placeholderImageWithLabel:item.appLabel
                                                                    package:item.packageName];
    }

    meta.stringValue = [self metaLineForItem:item];
    title.stringValue = [self displayTitleForItem:item];
    title.font = [NSFont systemFontOfSize:13 weight:unread ? NSFontWeightSemibold : NSFontWeightMedium];
    title.textColor = [NSColor labelColor];

    NSString *bodyText = [self displayBodyForItem:item];
    if (item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0) {
        body.stringValue = bodyText;
        body.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold];
        body.textColor = [NSColor labelColor];
        copyOTP.hidden = NO;
        copyOTP.tag = row;
        [self applyCopyOTPButtonStyle:copyOTP appearance:cell.effectiveAppearance];
    } else {
        body.stringValue = bodyText;
        body.font = [NSFont systemFontOfSize:12];
        body.textColor = [NSColor secondaryLabelColor];
        copyOTP.hidden = YES;
    }
    body.hidden = (bodyText.length == 0);

    time.stringValue = [self formatTime:item.postTimeMs];
    cell.objectValue = item.itemID;
    return cell;
}

- (void)applyCopyOTPButtonStyle:(NSButton *)button appearance:(NSAppearance *)appearance {
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName match = [appearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        dark = (match == NSAppearanceNameDarkAqua);
    }
    // 加深蓝底白字，比 inline 链接更醒目
    NSColor *fill = dark
        ? [NSColor colorWithCalibratedRed:0.18 green:0.40 blue:0.88 alpha:1.0]
        : [NSColor colorWithCalibratedRed:0.10 green:0.36 blue:0.86 alpha:1.0];
    button.wantsLayer = YES;
    button.layer.backgroundColor = fill.CGColor;
    button.layer.cornerRadius = 5.0;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    button.attributedTitle = [[NSAttributedString alloc] initWithString:@"复制验证码" attributes:attrs];
}

- (nullable NSView *)subview:(NSView *)parent id:(NSString *)identifier {
    for (NSView *v in parent.subviews) {
        if ([v.identifier isEqualToString:identifier]) return v;
    }
    return nil;
}

- (NSString *)formatTime:(long long)postTimeMs {
    if (postTimeMs <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:postTimeMs / 1000.0];
    NSCalendar *cal = [NSCalendar currentCalendar];
    if ([cal isDateInToday:date]) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm";
        return [fmt stringFromDate:date];
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"M/d";
    return [fmt stringFromDate:date];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    PhoneNotificationItem *item = [self itemAtRow:self.tableView.selectedRow];
    if (item && !item.read) {
        [[PhoneNotificationInboxStore sharedStore] setRead:YES forId:item.itemID];
    }
}

#pragma mark - Actions

- (void)categoryButtonClicked:(id)sender {
    (void)sender;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"App 分类"];
    menu.autoenablesItems = NO;

    NSMenuItem *all = [[NSMenuItem alloc] initWithTitle:@"全部应用"
                                                 action:@selector(selectAppCategory:)
                                          keyEquivalent:@""];
    all.target = self;
    all.representedObject = @{};
    all.state = (self.packageFilter.length == 0) ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:all];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<NSDictionary *> *entries = [self appCategoryEntries];
    if (entries.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"暂无 App"
                                                       action:nil
                                                keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    } else {
        for (NSDictionary *entry in entries) {
            NSString *pkg = entry[@"packageName"] ?: @"";
            NSString *label = entry[@"label"] ?: pkg;
            NSInteger count = [entry[@"count"] integerValue];
            NSString *title = [NSString stringWithFormat:@"%@（%ld）", label, (long)count];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                          action:@selector(selectAppCategory:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.representedObject = entry;
            item.state = [pkg isEqualToString:self.packageFilter]
                ? NSControlStateValueOn : NSControlStateValueOff;

            BOOL isOTP = [pkg isEqualToString:@"otp"];
            NSImage *icon = isOTP
                ? [PhoneAppIconCache otpPlaceholderImage]
                : ([[PhoneAppIconCache sharedCache] imageForPackage:pkg]
                   ?: [PhoneAppIconCache placeholderImageWithLabel:label package:pkg]);
            if (icon) {
                NSImage *sized = [icon copy];
                sized.size = NSMakeSize(16, 16);
                item.image = sized;
            }
            [menu addItem:item];
        }
    }

    NSPoint point = NSMakePoint(0, self.categoryButton.bounds.size.height + 2);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:self.categoryButton];
}

- (void)selectAppCategory:(NSMenuItem *)sender {
    NSDictionary *entry = [sender.representedObject isKindOfClass:[NSDictionary class]]
        ? sender.representedObject : @{};
    NSString *pkg = entry[@"packageName"];
    if (![pkg isKindOfClass:[NSString class]] || pkg.length == 0) {
        self.packageFilter = nil;
        self.packageFilterLabel = nil;
    } else {
        self.packageFilter = pkg;
        NSString *label = entry[@"label"];
        self.packageFilterLabel = [label isKindOfClass:[NSString class]] ? label : pkg;
    }
    [self reloadList];
}

- (void)clearPackageFilterClicked:(id)sender {
    (void)sender;
    self.packageFilter = nil;
    self.packageFilterLabel = nil;
    [self reloadList];
}

- (void)bucketChanged:(id)sender {
    (void)sender;
    [self reloadList];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != self.searchField) return;
    if (self.searchDebounceBlock) {
        dispatch_block_cancel(self.searchDebounceBlock);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf reloadList];
    });
    self.searchDebounceBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSearchDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)tableDoubleClicked:(id)sender {
    (void)sender;
    [self copyBodyClicked:nil];
}

- (void)copyBodyClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item) return;
    NSString *text = item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0
        ? item.otpCode : (item.body.length > 0 ? item.body : item.title);
    if (text.length == 0) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
}

- (void)copyOTPClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item || item.otpCode.length == 0) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:item.otpCode forType:NSPasteboardTypeString];
}

- (void)copyOTPFromCell:(NSButton *)sender {
    PhoneNotificationItem *item = [self itemAtRow:sender.tag];
    if (!item || item.otpCode.length == 0) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:item.otpCode forType:NSPasteboardTypeString];
    sender.title = @"已复制";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.title = @"复制码";
    });
}

- (void)togglePinClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item) return;
    [[PhoneNotificationInboxStore sharedStore] setPinned:!item.pinned forId:item.itemID];
}

- (void)markReadClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item) return;
    [[PhoneNotificationInboxStore sharedStore] setRead:YES forId:item.itemID];
}

- (void)deleteClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item) return;
    [[PhoneNotificationInboxStore sharedStore] deleteId:item.itemID];
}

- (void)muteAppClicked:(id)sender {
    (void)sender;
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    if (!item || item.packageName.length == 0 || [item.packageName isEqualToString:@"otp"]) return;
    [[PhoneNotificationInboxStore sharedStore] setMuted:YES forPackage:item.packageName];
}

- (void)markAllReadClicked:(id)sender {
    (void)sender;
    [[PhoneNotificationInboxStore sharedStore] markAllRead];
}

- (void)purgeReadClicked:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"清空已读通知？";
    alert.informativeText = @"已钉选的条目会保留。此操作不可撤销。";
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[PhoneNotificationInboxStore sharedStore] purgeRead];
    }
}

- (void)closeClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(notificationSidebarDidRequestClose:)]) {
        [self.delegate notificationSidebarDidRequestClose:self];
    }
}

- (void)syncButtonClicked:(id)sender {
    (void)sender;
    if (self.syncInFlight) {
        return;
    }
    CompanionChannel *channel = [CompanionChannel sharedChannel];
    if (channel.state != CompanionChannelStateConnected) {
        [self showSyncToast:@"请先连接手机 Companion"];
        [self updateSyncButtonState];
        return;
    }
    NSString *requestID = [[NSUUID UUID] UUIDString];
    if (![channel requestPhoneNotificationPullWithRequestID:requestID]) {
        [self showSyncToast:@"同步请求发送失败"];
        return;
    }
    self.syncInFlight = YES;
    self.pendingSyncRequestID = requestID;
    [self updateSyncButtonState];
    [self scheduleSyncTimeout];
    [self showSyncToast:@"正在同步手机通知…"];
}

- (void)phoneNotificationPullDidFinish:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo ?: @{};
    NSString *requestID = info[CompanionPhoneNotificationPullRequestIDKey];
    if (self.pendingSyncRequestID.length > 0 &&
        requestID.length > 0 &&
        ![requestID isEqualToString:self.pendingSyncRequestID]) {
        return;
    }
    [self cancelSyncTimeout];
    self.syncInFlight = NO;
    self.pendingSyncRequestID = nil;
    [self updateSyncButtonState];
    [self reloadList];

    NSString *error = info[CompanionPhoneNotificationPullErrorKey];
    NSInteger pushed = [info[CompanionPhoneNotificationPullPushedKey] integerValue];
    NSString *mode = info[CompanionPhoneNotificationPullModeKey] ?: @"";
    if (error.length > 0) {
        NSString *msg = @"同步失败";
        if ([error isEqualToString:@"listener_disabled"]) {
            msg = @"手机未开启通知使用权";
        } else if ([error isEqualToString:@"listener_disconnected"]) {
            msg = @"手机通知监听未连接，请在 Companion 中重试";
        } else if ([error isEqualToString:@"service_unavailable"]) {
            msg = @"手机 Companion 服务未就绪";
        } else {
            msg = [NSString stringWithFormat:@"同步失败：%@", error];
        }
        [self showSyncToast:msg];
        return;
    }
    if (pushed <= 0) {
        if ([mode isEqualToString:@"otp_only"]) {
            [self showSyncToast:@"未发现可同步的验证码通知"];
        } else {
            [self showSyncToast:@"通知栏没有可同步的通知"];
        }
        return;
    }
    [self showSyncToast:[NSString stringWithFormat:@"已同步 %ld 条通知", (long)pushed]];
}

- (void)updateSyncButtonState {
    BOOL connected = [CompanionChannel sharedChannel].state == CompanionChannelStateConnected;
    self.syncButton.enabled = connected && !self.syncInFlight;
    if (self.syncInFlight) {
        self.syncButton.toolTip = @"正在同步…";
    } else if (!connected) {
        self.syncButton.toolTip = @"连接手机后可同步通知栏中仍可见的通知";
    } else {
        self.syncButton.toolTip = @"同步手机通知栏中仍可见的通知（断线期间已划掉的无法找回）";
    }
    if (@available(macOS 10.14, *)) {
        self.syncButton.contentTintColor = self.syncButton.enabled
            ? [NSColor secondaryLabelColor]
            : [NSColor tertiaryLabelColor];
    }
}

- (void)scheduleSyncTimeout {
    [self cancelSyncTimeout];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.syncInFlight) {
            return;
        }
        strongSelf.syncInFlight = NO;
        strongSelf.pendingSyncRequestID = nil;
        [strongSelf updateSyncButtonState];
        [strongSelf showSyncToast:@"同步超时，请确认手机已连接"];
    });
    self.syncTimeoutBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSyncPullTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)cancelSyncTimeout {
    if (self.syncTimeoutBlock) {
        dispatch_block_cancel(self.syncTimeoutBlock);
        self.syncTimeoutBlock = nil;
    }
}

- (void)showSyncToast:(NSString *)message {
    NSWindow *window = self.view.window;
    if (!window || message.length == 0) {
        return;
    }
    [BrowserTransientToast showMessage:message inWindow:window duration:2.4];
}

- (void)emptyActionClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(notificationSidebarDidRequestCompanionSettings:)]) {
        [self.delegate notificationSidebarDidRequestCompanionSettings:self];
    }
}

- (void)inboxOrChannelDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateSyncButtonState];
    if (self.visible) {
        [self reloadList];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    PhoneNotificationItem *item = [self clickedOrSelectedItem];
    SEL action = menuItem.action;
    if (action == @selector(copyOTPClicked:)) {
        return item.otpCode.length > 0;
    }
    if (action == @selector(muteAppClicked:)) {
        return item.packageName.length > 0 && ![item.packageName isEqualToString:@"otp"];
    }
    if (action == @selector(copyBodyClicked:) ||
        action == @selector(togglePinClicked:) ||
        action == @selector(markReadClicked:) ||
        action == @selector(deleteClicked:)) {
        return item != nil;
    }
    return YES;
}

@end
