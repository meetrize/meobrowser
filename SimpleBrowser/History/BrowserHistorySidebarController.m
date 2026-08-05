#import "BrowserHistorySidebarController.h"
#import "BrowserHistorySettings.h"
#import "BrowserHistoryStore.h"
#import "BrowserHistoryEntry.h"
#import "BrowserFaviconService.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kResizeHandleWidth = 8.0;
static const CGFloat kEntryRowHeight = 54.0;
static const CGFloat kSectionRowHeight = 28.0;
static const NSTimeInterval kSearchDebounce = 0.2;

typedef NS_ENUM(NSInteger, BrowserHistoryScope) {
    BrowserHistoryScopeAll = 0,
    BrowserHistoryScopeToday = 1,
    BrowserHistoryScopeSevenDays = 2,
};

typedef NS_ENUM(NSInteger, BrowserHistorySidebarRowKind) {
    BrowserHistorySidebarRowKindSection = 0,
    BrowserHistorySidebarRowKindEntry = 1,
};

@interface BrowserHistorySidebarRow : NSObject
@property (nonatomic, assign) BrowserHistorySidebarRowKind kind;
@property (nonatomic, copy, nullable) NSString *sectionTitle;
@property (nonatomic, strong, nullable) BrowserHistoryEntry *entry;
@end
@implementation BrowserHistorySidebarRow
@end

@interface BrowserHistorySidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation BrowserHistorySidebarResizeView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}
- (CGFloat)screenXFromEvent:(NSEvent *)event {
    NSPoint inWindow = event.locationInWindow;
    if (self.window) {
        return [self.window convertPointToScreen:inWindow].x;
    }
    return inWindow.x;
}
- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    self.dragging = YES;
    self.dragStartScreenX = [self screenXFromEvent:event];
    if (self.onDragBegan) {
        self.onDragBegan();
    }
    [[NSCursor resizeLeftRightCursor] push];
    while (self.dragging) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next || next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        if (next.type == NSEventTypeLeftMouseDragged && self.onDragToOffset) {
            self.onDragToOffset([self screenXFromEvent:next] - self.dragStartScreenX);
        }
    }
    self.dragging = NO;
    [NSCursor pop];
    if (self.onDragEnded) {
        self.onDragEnded();
    }
}
@end

@interface BrowserHistorySidebarBackgroundView : NSView
@property (nonatomic, copy, nullable) void (^onAppearanceChange)(void);
@end
@implementation BrowserHistorySidebarBackgroundView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onAppearanceChange) {
        self.onAppearanceChange();
    }
}
@end

@interface BrowserHistoryEntryCellView : NSTableCellView
@property (nonatomic, strong) NSImageView *faviconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSTextField *timeLabel;
@property (nonatomic, copy) NSString *loadToken;
@end

@implementation BrowserHistoryEntryCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _faviconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _faviconView.translatesAutoresizingMaskIntoConstraints = NO;
        _faviconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _faviconView.wantsLayer = YES;
        _faviconView.layer.cornerRadius = 4.0;
        _faviconView.layer.masksToBounds = YES;
        [self addSubview:_faviconView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [NSFont systemFontOfSize:11];
        _subtitleLabel.textColor = [NSColor secondaryLabelColor];
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        _timeLabel = [NSTextField labelWithString:@""];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        _timeLabel.textColor = [NSColor tertiaryLabelColor];
        _timeLabel.alignment = NSTextAlignmentRight;
        [_timeLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_faviconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_faviconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_faviconView.widthAnchor constraintEqualToConstant:22],
            [_faviconView.heightAnchor constraintEqualToConstant:22],

            [_timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_timeLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_timeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:36],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_faviconView.trailingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(BrowserHistoryEntry *)entry relativeTime:(NSString *)relativeTime {
    self.titleLabel.stringValue = entry.title.length > 0 ? entry.title : entry.url;
    self.subtitleLabel.stringValue = entry.displayHost;
    self.timeLabel.stringValue = relativeTime ?: @"";
    self.toolTip = entry.url;
    self.faviconView.image = nil;

    NSString *token = entry.url ?: @"";
    self.loadToken = token;
    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] imageForPageURLString:entry.url
                                                 preferredIconURL:nil
                                                      triggerFetch:NO
                                                        completion:^(NSImage *image) {
        BrowserHistoryEntryCellView *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.loadToken isEqualToString:token]) {
            return;
        }
        if (image) {
            strongSelf.faviconView.image = image;
        } else if (@available(macOS 11.0, *)) {
            strongSelf.faviconView.image = [NSImage imageWithSystemSymbolName:@"globe"
                                                     accessibilityDescription:nil];
            if (@available(macOS 10.14, *)) {
                strongSelf.faviconView.contentTintColor = [NSColor secondaryLabelColor];
            }
        }
    }];
}

@end

@interface BrowserHistorySectionCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *sectionLabel;
@end

@implementation BrowserHistorySectionCellView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _sectionLabel = [NSTextField labelWithString:@""];
        _sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sectionLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _sectionLabel.textColor = [NSColor secondaryLabelColor];
        [self addSubview:_sectionLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_sectionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_sectionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_sectionLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
    }
    return self;
}
@end

@interface BrowserHistorySidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *headerBar;
@property (nonatomic, strong) NSView *headerBottomSep;
@property (nonatomic, strong) NSView *edgeSeparator;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSSegmentedControl *scopeControl;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSView *emptyContainer;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyDetailLabel;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) BrowserHistorySidebarResizeView *resizeHandle;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, copy) NSArray<BrowserHistorySidebarRow *> *rows;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, assign) BrowserHistoryScope scope;
@property (nonatomic, assign) NSUInteger entryCount;
@property (nonatomic, strong, nullable) dispatch_block_t searchDebounceBlock;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, strong, nullable) id storeObserver;
@end

@implementation BrowserHistorySidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [BrowserHistorySettings sharedSettings].sidebarWidth;
        _rows = @[];
        _currentQuery = @"";
        _scope = BrowserHistoryScopeAll;
        [self buildUI];
        __weak typeof(self) weakSelf = self;
        _storeObserver =
            [[NSNotificationCenter defaultCenter]
                addObserverForName:BrowserHistoryStoreDidChangeNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
                if (weakSelf.visible) {
                    [weakSelf reloadList];
                }
            }];
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
    if (self.storeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.storeObserver];
    }
}

#pragma mark - UI

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;

    BrowserHistorySidebarBackgroundView *background = [[BrowserHistorySidebarBackgroundView alloc] initWithFrame:NSZeroRect];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.wantsLayer = YES;
    __weak typeof(self) weakSelf = self;
    background.onAppearanceChange = ^{
        [weakSelf applySidebarChromeColors];
        if (weakSelf.visible) {
            [weakSelf.tableView reloadData];
        }
    };
    [root addSubview:background];

    NSView *headerBar = [[NSView alloc] initWithFrame:NSZeroRect];
    headerBar.translatesAutoresizingMaskIntoConstraints = NO;
    headerBar.wantsLayer = YES;

    NSView *headerBottomSep = [[NSView alloc] initWithFrame:NSZeroRect];
    headerBottomSep.translatesAutoresizingMaskIntoConstraints = NO;
    headerBottomSep.wantsLayer = YES;

    NSTextField *title = [NSTextField labelWithString:@"历史记录"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    title.textColor = [NSColor labelColor];

    NSTextField *count = [NSTextField labelWithString:@""];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    count.textColor = [NSColor tertiaryLabelColor];

    NSButton *clear = [NSButton buttonWithTitle:@"清除" target:self action:@selector(clearClicked:)];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    clear.bezelStyle = NSBezelStyleInline;
    clear.bordered = NO;
    clear.font = [NSFont systemFontOfSize:12];
    clear.toolTip = @"清除浏览历史";
    if (@available(macOS 10.14, *)) {
        clear.contentTintColor = [NSColor secondaryLabelColor];
    }

    NSButton *close = [NSButton buttonWithTitle:@"" target:self action:@selector(closeClicked:)];
    NSImage *closeImage = [self symbolNamed:@"sidebar.trailing"];
    if (closeImage) {
        close.image = closeImage;
        close.imagePosition = NSImageOnly;
    } else {
        close.title = @"⟩";
    }
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.bezelStyle = NSBezelStyleInline;
    close.bordered = NO;
    close.toolTip = @"关闭侧栏";
    if (@available(macOS 10.14, *)) {
        close.contentTintColor = [NSColor secondaryLabelColor];
    }

    [headerBar addSubview:title];
    [headerBar addSubview:count];
    [headerBar addSubview:clear];
    [headerBar addSubview:close];
    [headerBar addSubview:headerBottomSep];

    SBTextField *search = [SBTextField standardField];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.placeholderString = @"搜索标题或网址…";
    search.delegate = self;
    search.usesCompactVerticalTextInsets = YES;

    NSSegmentedControl *scope = [NSSegmentedControl segmentedControlWithLabels:@[@"全部", @"今天", @"7 天"]
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:@selector(scopeChanged:)];
    scope.translatesAutoresizingMaskIntoConstraints = NO;
    scope.segmentStyle = NSSegmentStyleRounded;
    scope.selectedSegment = 0;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.backgroundColor = [NSColor clearColor];

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.backgroundColor = [NSColor clearColor];
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsEmptySelection = YES;
    table.rowHeight = kEntryRowHeight;
    table.intercellSpacing = NSMakeSize(0, 0);
    if (@available(macOS 11.0, *)) {
        table.style = NSTableViewStylePlain;
    }
    table.target = self;
    table.doubleAction = @selector(tableDoubleClicked:);
    table.action = @selector(tableSingleClicked:);
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = 300;
    [table addTableColumn:col];
    table.dataSource = self;
    table.delegate = self;
    table.menu = [self buildContextMenu];
    scroll.documentView = table;

    NSView *empty = [[NSView alloc] initWithFrame:NSZeroRect];
    empty.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *emptyTitle = [NSTextField wrappingLabelWithString:@"暂无浏览记录"];
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    emptyTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;

    NSTextField *emptyDetail = [NSTextField wrappingLabelWithString:@"访问网页后，记录会出现在这里。\n也可在地址栏输入时从历史补全。"];
    emptyDetail.translatesAutoresizingMaskIntoConstraints = NO;
    emptyDetail.font = [NSFont systemFontOfSize:12];
    emptyDetail.textColor = [NSColor tertiaryLabelColor];
    emptyDetail.alignment = NSTextAlignmentCenter;
    emptyDetail.preferredMaxLayoutWidth = 240;

    [empty addSubview:emptyTitle];
    [empty addSubview:emptyDetail];

    NSTextField *footer = [NSTextField labelWithString:@""];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.font = [NSFont systemFontOfSize:11];
    footer.textColor = [NSColor tertiaryLabelColor];
    footer.alignment = NSTextAlignmentCenter;

    BrowserHistorySidebarResizeView *handle = [[BrowserHistorySidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
        weakSelf.isResizingWidth = YES;
    };
    handle.onDragToOffset = ^(CGFloat mouseDeltaXFromStart) {
        [weakSelf applyWidth:weakSelf.dragStartWidth - mouseDeltaXFromStart];
    };
    handle.onDragEnded = ^{
        weakSelf.isResizingWidth = NO;
        [weakSelf persistWidth];
    };

    NSView *edgeSeparator = [[NSView alloc] initWithFrame:NSZeroRect];
    edgeSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    edgeSeparator.wantsLayer = YES;

    [background addSubview:headerBar];
    [background addSubview:search];
    [background addSubview:scope];
    [background addSubview:scroll];
    [background addSubview:empty];
    [background addSubview:footer];
    [root addSubview:handle];
    [root addSubview:edgeSeparator];

    self.view = root;
    self.backgroundView = background;
    self.headerBar = headerBar;
    self.headerBottomSep = headerBottomSep;
    self.edgeSeparator = edgeSeparator;
    self.titleLabel = title;
    self.countLabel = count;
    self.clearButton = clear;
    self.closeButton = close;
    self.searchField = search;
    self.scopeControl = scope;
    self.scrollView = scroll;
    self.tableView = table;
    self.emptyContainer = empty;
    self.emptyTitleLabel = emptyTitle;
    self.emptyDetailLabel = emptyDetail;
    self.footerLabel = footer;
    self.resizeHandle = handle;

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:root.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [headerBar.topAnchor constraintEqualToAnchor:background.topAnchor],
        [headerBar.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [headerBar.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [headerBar.heightAnchor constraintEqualToConstant:44],

        [title.leadingAnchor constraintEqualToAnchor:headerBar.leadingAnchor constant:14],
        [title.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [count.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:8],
        [count.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [close.trailingAnchor constraintEqualToAnchor:headerBar.trailingAnchor constant:-8],
        [close.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],

        [clear.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-2],
        [clear.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],

        [headerBottomSep.leadingAnchor constraintEqualToAnchor:headerBar.leadingAnchor],
        [headerBottomSep.trailingAnchor constraintEqualToAnchor:headerBar.trailingAnchor],
        [headerBottomSep.bottomAnchor constraintEqualToAnchor:headerBar.bottomAnchor],
        [headerBottomSep.heightAnchor constraintEqualToConstant:1],

        [search.topAnchor constraintEqualToAnchor:headerBar.bottomAnchor constant:10],
        [search.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:12],
        [search.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-12],
        [search.heightAnchor constraintEqualToConstant:26],

        [scope.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],
        [scope.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:12],
        [scope.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-12],
        [scope.heightAnchor constraintEqualToConstant:24],

        [scroll.topAnchor constraintEqualToAnchor:scope.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-4],

        [empty.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [empty.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],
        [empty.widthAnchor constraintLessThanOrEqualToAnchor:scroll.widthAnchor constant:-24],
        [emptyTitle.topAnchor constraintEqualToAnchor:empty.topAnchor],
        [emptyTitle.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor],
        [emptyTitle.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor],
        [emptyDetail.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:6],
        [emptyDetail.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor],
        [emptyDetail.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor],
        [emptyDetail.bottomAnchor constraintEqualToAnchor:empty.bottomAnchor],

        [footer.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:12],
        [footer.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-12],
        [footer.bottomAnchor constraintEqualToAnchor:background.bottomAnchor constant:-8],
        [footer.heightAnchor constraintEqualToConstant:16],

        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],

        [edgeSeparator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [edgeSeparator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edgeSeparator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edgeSeparator.widthAnchor constraintEqualToConstant:1],
    ]];

    [self applySidebarChromeColors];
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

- (void)applySidebarChromeColors {
    NSColor *bg = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        if ([name isEqualToString:NSAppearanceNameDarkAqua]) {
            return [NSColor colorWithCalibratedWhite:0.14 alpha:1.0];
        }
        return [NSColor colorWithCalibratedWhite:0.97 alpha:1.0];
    }];
    self.backgroundView.layer.backgroundColor = bg.CGColor;
    self.headerBar.layer.backgroundColor = bg.CGColor;
    self.headerBottomSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    self.edgeSeparator.layer.backgroundColor = [NSColor separatorColor].CGColor;
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
        self.currentWidth = [BrowserHistorySettings sharedSettings].sidebarWidth;
        self.view.hidden = NO;
        [self applySidebarChromeColors];
        [self installKeyMonitor];
    } else {
        [self uninstallKeyMonitor];
    }
    CGFloat target = visible ? self.currentWidth : 0;

    void (^finish)(void) = ^{
        if (!self.visible) {
            self.view.hidden = YES;
        } else {
            [self reloadList];
            [self.view.window makeFirstResponder:self.searchField];
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
    self.currentWidth = next;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        self.widthConstraint.animator.constant = next;
    } completionHandler:nil];
}

- (void)persistWidth {
    [BrowserHistorySettings sharedSettings].sidebarWidth = self.currentWidth;
    [self.delegate historySidebar:self didChangeWidth:self.currentWidth];
}

#pragma mark - Data

- (NSTimeInterval)scopeCutoff {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    switch (self.scope) {
        case BrowserHistoryScopeToday:
            return [[calendar startOfDayForDate:[NSDate date]] timeIntervalSince1970];
        case BrowserHistoryScopeSevenDays:
            return [[NSDate date] timeIntervalSince1970] - 7.0 * 24.0 * 3600.0;
        case BrowserHistoryScopeAll:
        default:
            return 0;
    }
}

- (NSString *)sectionTitleForVisitTime:(NSTimeInterval)visitTime {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:visitTime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        return @"今天";
    }
    if ([calendar isDateInYesterday:date]) {
        return @"昨天";
    }
    NSDateComponents *components = [calendar components:NSCalendarUnitDay fromDate:date toDate:[NSDate date] options:0];
    if (components.day >= 0 && components.day < 7) {
        return @"本周";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy年M月";
    return [formatter stringFromDate:date] ?: @"更早";
}

- (NSString *)relativeTimeForVisitTime:(NSTimeInterval)visitTime {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:visitTime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm";
        return [formatter stringFromDate:date];
    }
    if ([calendar isDateInYesterday:date]) {
        return @"昨天";
    }
    NSDateComponents *components = [calendar components:NSCalendarUnitDay fromDate:date toDate:[NSDate date] options:0];
    if (components.day > 0 && components.day < 7) {
        return [NSString stringWithFormat:@"%ld天前", (long)components.day];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"M/d";
    return [formatter stringFromDate:date];
}

- (void)reloadList {
    NSArray<BrowserHistoryEntry *> *entries =
        [[BrowserHistoryStore sharedStore] entriesMatchingQuery:self.currentQuery limit:0];
    NSTimeInterval cutoff = [self scopeCutoff];
    if (cutoff > 0) {
        NSMutableArray<BrowserHistoryEntry *> *filtered = [NSMutableArray array];
        for (BrowserHistoryEntry *entry in entries) {
            if (entry.visitTime >= cutoff) {
                [filtered addObject:entry];
            }
        }
        entries = filtered;
    }

    NSMutableArray<BrowserHistorySidebarRow *> *rows = [NSMutableArray array];
    NSString *lastSection = nil;
    for (BrowserHistoryEntry *entry in entries) {
        NSString *section = [self sectionTitleForVisitTime:entry.visitTime];
        if (![section isEqualToString:lastSection]) {
            BrowserHistorySidebarRow *sectionRow = [[BrowserHistorySidebarRow alloc] init];
            sectionRow.kind = BrowserHistorySidebarRowKindSection;
            sectionRow.sectionTitle = section;
            [rows addObject:sectionRow];
            lastSection = section;
        }
        BrowserHistorySidebarRow *entryRow = [[BrowserHistorySidebarRow alloc] init];
        entryRow.kind = BrowserHistorySidebarRowKindEntry;
        entryRow.entry = entry;
        [rows addObject:entryRow];
    }
    self.rows = rows;
    self.entryCount = entries.count;

    BOOL empty = entries.count == 0;
    self.emptyContainer.hidden = !empty;
    self.scrollView.hidden = empty;
    self.clearButton.enabled = ([[BrowserHistoryStore sharedStore] activeEntriesSortedByVisitTime].count > 0);

    if (empty) {
        if (self.currentQuery.length > 0) {
            self.emptyTitleLabel.stringValue = @"无匹配结果";
            self.emptyDetailLabel.stringValue = @"试试其他关键词，或切换时间范围。";
        } else if (self.scope != BrowserHistoryScopeAll) {
            self.emptyTitleLabel.stringValue = @"该时间范围内无记录";
            self.emptyDetailLabel.stringValue = @"切换到「全部」查看更多历史。";
        } else {
            self.emptyTitleLabel.stringValue = @"暂无浏览记录";
            self.emptyDetailLabel.stringValue = @"访问网页后，记录会出现在这里。\n也可在地址栏输入时从历史补全。";
        }
    }

    if (self.entryCount > 0) {
        self.countLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.entryCount];
        self.footerLabel.stringValue = @"双击打开 · ⌘双击新标签 · ⌘⌫ 删除";
    } else {
        self.countLabel.stringValue = @"";
        self.footerLabel.stringValue = @"";
    }

    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.delegate historySidebarDidRequestClose:self];
}

- (void)scopeChanged:(id)sender {
    (void)sender;
    self.scope = (BrowserHistoryScope)self.scopeControl.selectedSegment;
    [self reloadList];
}

- (void)clearClicked:(id)sender {
    (void)sender;
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *today = [[NSMenuItem alloc] initWithTitle:@"清除今天"
                                                   action:@selector(clearToday:)
                                            keyEquivalent:@""];
    today.target = self;
    [menu addItem:today];
    NSMenuItem *week = [[NSMenuItem alloc] initWithTitle:@"清除最近 7 天"
                                                  action:@selector(clearLastSevenDays:)
                                           keyEquivalent:@""];
    week.target = self;
    [menu addItem:week];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *all = [[NSMenuItem alloc] initWithTitle:@"清除全部历史…"
                                                 action:@selector(clearAllConfirmed:)
                                          keyEquivalent:@""];
    all.target = self;
    [menu addItem:all];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(self.clearButton.bounds)) inView:self.clearButton];
}

- (void)clearToday:(id)sender {
    (void)sender;
    [[BrowserHistoryStore sharedStore] clearVisitedToday];
}

- (void)clearLastSevenDays:(id)sender {
    (void)sender;
    NSTimeInterval since = [[NSDate date] timeIntervalSince1970] - 7.0 * 24.0 * 3600.0;
    [[BrowserHistoryStore sharedStore] clearVisitedSince:since];
}

- (void)clearAllConfirmed:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"清除全部浏览历史？";
    alert.informativeText = @"此操作无法撤销。";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"清除"];
    [alert addButtonWithTitle:@"取消"];
    NSWindow *window = self.view.window;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [[BrowserHistoryStore sharedStore] clearAll];
        }
    }];
}

- (nullable BrowserHistoryEntry *)selectedEntry {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return nil;
    }
    BrowserHistorySidebarRow *item = self.rows[row];
    return item.kind == BrowserHistorySidebarRowKindEntry ? item.entry : nil;
}

- (void)openSelectedInNewTab:(BOOL)inNewTab {
    BrowserHistoryEntry *entry = [self selectedEntry];
    if (!entry) {
        return;
    }
    NSURL *url = [NSURL URLWithString:entry.url];
    if (!url) {
        return;
    }
    [self.delegate historySidebar:self openURL:url inNewTab:inNewTab];
}

- (void)tableDoubleClicked:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    BrowserHistorySidebarRow *item = self.rows[row];
    if (item.kind != BrowserHistorySidebarRowKindEntry || !item.entry) {
        return;
    }
    NSURL *url = [NSURL URLWithString:item.entry.url];
    if (!url) {
        return;
    }
    BOOL newTab = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagCommand) != 0;
    [self.delegate historySidebar:self openURL:url inNewTab:newTab];
}

- (void)tableSingleClicked:(id)sender {
    (void)sender;
    NSEvent *event = NSApp.currentEvent;
    if (event.buttonNumber == 2) {
        NSInteger row = self.tableView.clickedRow;
        if (row < 0 || row >= (NSInteger)self.rows.count) {
            return;
        }
        BrowserHistorySidebarRow *item = self.rows[row];
        if (item.kind != BrowserHistorySidebarRowKindEntry || !item.entry) {
            return;
        }
        NSURL *url = [NSURL URLWithString:item.entry.url];
        if (url) {
            [self.delegate historySidebar:self openURL:url inNewTab:YES];
        }
    }
}

- (void)deleteSelectedEntry {
    BrowserHistoryEntry *entry = [self selectedEntry];
    if (!entry) {
        return;
    }
    [[BrowserHistoryStore sharedStore] deleteEntryWithID:entry.entryID];
}

#pragma mark - Context menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"历史"];
    [menu addItemWithTitle:@"打开" action:@selector(menuOpen:) keyEquivalent:@""];
    [menu addItemWithTitle:@"在新标签页中打开" action:@selector(menuOpenInNewTab:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"复制链接" action:@selector(menuCopyURL:) keyEquivalent:@""];
    [menu addItemWithTitle:@"复制 Markdown 链接" action:@selector(menuCopyMarkdown:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"删除此项" action:@selector(menuDelete:) keyEquivalent:@""];
    [menu addItemWithTitle:@"删除该域名全部记录" action:@selector(menuDeleteHost:) keyEquivalent:@""];
    for (NSMenuItem *item in menu.itemArray) {
        item.target = self;
    }
    return menu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    BrowserHistoryEntry *entry = [self selectedEntry];
    if (!entry) {
        NSInteger row = self.tableView.clickedRow;
        if (row >= 0 && row < (NSInteger)self.rows.count) {
            BrowserHistorySidebarRow *item = self.rows[row];
            entry = item.entry;
        }
    }
    if (menuItem.action == @selector(menuDeleteHost:)) {
        return entry.displayHost.length > 0;
    }
    return entry != nil;
}

- (nullable BrowserHistoryEntry *)entryForMenuAction {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) {
        row = self.tableView.selectedRow;
    }
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return nil;
    }
    BrowserHistorySidebarRow *item = self.rows[row];
    return item.kind == BrowserHistorySidebarRowKindEntry ? item.entry : nil;
}

- (void)menuOpen:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    NSURL *url = [NSURL URLWithString:entry.url];
    if (url) {
        [self.delegate historySidebar:self openURL:url inNewTab:NO];
    }
}

- (void)menuOpenInNewTab:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    NSURL *url = [NSURL URLWithString:entry.url];
    if (url) {
        [self.delegate historySidebar:self openURL:url inNewTab:YES];
    }
}

- (void)menuCopyURL:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    if (!entry.url.length) {
        return;
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:entry.url forType:NSPasteboardTypeString];
}

- (void)menuCopyMarkdown:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    if (!entry) {
        return;
    }
    NSString *title = entry.title.length > 0 ? entry.title : entry.url;
    NSString *markdown = [NSString stringWithFormat:@"[%@](%@)", title, entry.url];
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:markdown forType:NSPasteboardTypeString];
}

- (void)menuDelete:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    if (entry) {
        [[BrowserHistoryStore sharedStore] deleteEntryWithID:entry.entryID];
    }
}

- (void)menuDeleteHost:(id)sender {
    (void)sender;
    BrowserHistoryEntry *entry = [self entryForMenuAction];
    if (entry.displayHost.length > 0) {
        [[BrowserHistoryStore sharedStore] deleteEntriesForHost:entry.displayHost];
    }
}

#pragma mark - Search

- (void)controlTextDidChange:(NSNotification *)obj {
    (void)obj;
    if (self.searchDebounceBlock) {
        dispatch_block_cancel(self.searchDebounceBlock);
        self.searchDebounceBlock = nil;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        BrowserHistorySidebarController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.searchDebounceBlock = nil;
        strongSelf.currentQuery = strongSelf.searchField.stringValue ?: @"";
        [strongSelf reloadList];
    });
    self.searchDebounceBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSearchDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.rows.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return kEntryRowHeight;
    }
    return self.rows[row].kind == BrowserHistorySidebarRowKindSection ? kSectionRowHeight : kEntryRowHeight;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return NO;
    }
    return self.rows[row].kind == BrowserHistorySidebarRowKindSection;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return NO;
    }
    return self.rows[row].kind == BrowserHistorySidebarRowKindEntry;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return nil;
    }
    BrowserHistorySidebarRow *item = self.rows[row];
    if (item.kind == BrowserHistorySidebarRowKindSection) {
        BrowserHistorySectionCellView *cell = [tableView makeViewWithIdentifier:@"history.section" owner:self];
        if (!cell) {
            cell = [[BrowserHistorySectionCellView alloc] initWithFrame:NSZeroRect];
            cell.identifier = @"history.section";
        }
        cell.sectionLabel.stringValue = item.sectionTitle ?: @"";
        return cell;
    }

    BrowserHistoryEntryCellView *cell = [tableView makeViewWithIdentifier:@"history.entry" owner:self];
    if (!cell) {
        cell = [[BrowserHistoryEntryCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"history.entry";
    }
    [cell configureWithEntry:item.entry relativeTime:[self relativeTimeForVisitTime:item.entry.visitTime]];
    return cell;
}

#pragma mark - Keyboard

- (void)installKeyMonitor {
    [self uninstallKeyMonitor];
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                              handler:^NSEvent *(NSEvent *event) {
            BrowserHistorySidebarController *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.visible) {
                return event;
            }
            NSWindow *keyWindow = NSApp.keyWindow;
            if (keyWindow != strongSelf.view.window) {
                return event;
            }
            // Esc：关闭侧栏（搜索框内也生效）
            if (event.keyCode == 53) {
                [strongSelf.delegate historySidebarDidRequestClose:strongSelf];
                return nil;
            }
            BOOL searchFocused = (keyWindow.firstResponder == strongSelf.searchField.currentEditor);
            if (searchFocused) {
                return event;
            }
            if (event.keyCode == 36) { // Return
                BOOL newTab = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
                [strongSelf openSelectedInNewTab:newTab];
                return nil;
            }
            if (event.keyCode == 51 && (event.modifierFlags & NSEventModifierFlagCommand)) { // ⌘⌫
                [strongSelf deleteSelectedEntry];
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

@end
