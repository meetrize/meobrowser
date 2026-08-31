#import "AssistSidebarController.h"
#import "AssistSidebarSettings.h"
#import "AssistSidebarMemoEditor.h"
#import "AssistSidebarRecipeEditor.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "FormMemo.h"
#import "FormMemoStore.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kResizeHandleWidth = 8.0;
static const CGFloat kDetailResizeHandleHeight = 6.0;
static const CGFloat kDetailMinHeight = 180.0;
static const CGFloat kDetailMaxHeight = 720.0;
/// 列表区下限：可再矮一些，好把详情拖得更高。
static const CGFloat kListMinHeight = 56.0;
static const NSTimeInterval kSearchDebounce = 0.2;

typedef NS_ENUM(NSInteger, AssistSidebarRowKind) {
    AssistSidebarRowKindSection = 0,
    AssistSidebarRowKindRecipe = 1,
    AssistSidebarRowKindMemo = 2,
};

@interface AssistSidebarRow : NSObject
@property (nonatomic, assign) AssistSidebarRowKind kind;
@property (nonatomic, copy, nullable) NSString *sectionTitle;
@property (nonatomic, strong, nullable) LoginRecipe *recipe;
@property (nonatomic, strong, nullable) FormMemo *memo;
@end

@implementation AssistSidebarRow
@end

@interface AssistSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation AssistSidebarResizeView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

/// 窗口开启 movableByWindowBackground 时，空视图默认会把 mouseDown 当成拖窗。
- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

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

    // 本地跟踪循环：吃掉 drag/up，避免事件落到窗口拖移路径。
    while (self.dragging) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next) {
            break;
        }
        if (next.type == NSEventTypeLeftMouseUp) {
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

/// 列表与详情之间的水平分隔：上下拖改详情高度。
@interface AssistSidebarDetailResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaYFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenY;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) NSView *hairline;
@end

@implementation AssistSidebarDetailResizeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _hairline = [[NSView alloc] initWithFrame:NSZeroRect];
        _hairline.translatesAutoresizingMaskIntoConstraints = NO;
        _hairline.wantsLayer = YES;
        [self addSubview:_hairline];
        NSLayoutConstraint *hairlineHeight = [_hairline.heightAnchor constraintEqualToConstant:1];
        // 父视图收起高度为 0 时，勿用 Required 抢高度（RE-4）。
        hairlineHeight.priority = NSLayoutPriorityDefaultLow;
        [NSLayoutConstraint activateConstraints:@[
            [_hairline.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_hairline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_hairline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            hairlineHeight,
        ]];
        [self refreshHairlineColor];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self refreshHairlineColor];
}

- (void)refreshHairlineColor {
    if (@available(macOS 10.14, *)) {
        self.hairline.layer.backgroundColor = [NSColor separatorColor].CGColor;
    } else {
        self.hairline.layer.backgroundColor = [NSColor gridColor].CGColor;
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeUpDownCursor]];
}

- (CGFloat)screenYFromEvent:(NSEvent *)event {
    NSPoint inWindow = event.locationInWindow;
    if (self.window) {
        return [self.window convertPointToScreen:inWindow].y;
    }
    return inWindow.y;
}

- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    self.dragging = YES;
    self.dragStartScreenY = [self screenYFromEvent:event];
    if (self.onDragBegan) {
        self.onDragBegan();
    }
    [[NSCursor resizeUpDownCursor] push];

    while (self.dragging) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next) {
            break;
        }
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        if (next.type == NSEventTypeLeftMouseDragged && self.onDragToOffset) {
            self.onDragToOffset([self screenYFromEvent:next] - self.dragStartScreenY);
        }
    }

    self.dragging = NO;
    [NSCursor pop];
    if (self.onDragEnded) {
        self.onDragEnded();
    }
}

@end

@interface AssistSidebarBackgroundView : NSView
@property (nonatomic, copy, nullable) void (^onAppearanceChange)(void);
@end

@implementation AssistSidebarBackgroundView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onAppearanceChange) {
        self.onAppearanceChange();
    }
}
@end

@interface AssistSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate, AssistSidebarMemoEditorDelegate, AssistSidebarRecipeEditorDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSButton *addRecipeButton;
@property (nonatomic, strong) NSButton *addMemoButton;
@property (nonatomic, strong) NSSegmentedControl *scopeControl;
@property (nonatomic, strong) NSSegmentedControl *typeControl;
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSView *emptyContainer;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyDetailLabel;
@property (nonatomic, strong) NSButton *emptyNewRecipeButton;
@property (nonatomic, strong) NSButton *emptyNewMemoButton;
@property (nonatomic, strong) NSView *detailContainer;
@property (nonatomic, strong) NSLayoutConstraint *detailHeightConstraint;
@property (nonatomic, strong) AssistSidebarDetailResizeView *detailResizeHandle;
@property (nonatomic, strong) NSLayoutConstraint *detailResizeHandleHeightConstraint;
@property (nonatomic, strong) AssistSidebarMemoEditor *memoEditor;
@property (nonatomic, strong) AssistSidebarRecipeEditor *recipeEditor;
@property (nonatomic, strong) NSButton *advancedSettingsButton;
@property (nonatomic, strong) AssistSidebarResizeView *resizeHandle;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) CGFloat dragStartDetailHeight;
@property (nonatomic, assign) CGFloat dragStartFlexibleSpan;
@property (nonatomic, strong) NSArray<AssistSidebarRow *> *rows;
@property (nonatomic, strong, nullable) dispatch_block_t searchDebounceBlock;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, copy, nullable) NSString *pendingRevealRecipeID;
@property (nonatomic, copy, nullable) NSString *pendingRevealMemoID;
@property (nonatomic, copy, nullable) NSString *selectedRecipeID;
@property (nonatomic, copy, nullable) NSString *selectedMemoID;
@property (nonatomic, assign) BOOL suppressingSelectionLoad;
@end

@implementation AssistSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _scope = AssistSidebarScopeMatched;
        _typeFilter = AssistSidebarTypeFilterAll;
        _currentWidth = [AssistSidebarSettings sharedSettings].sidebarWidth;
        _rows = @[];
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeDidChange:)
                                                     name:FormMemoStoreDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)storeDidChange:(NSNotification *)note {
    (void)note;
    if (self.visible) {
        [self reloadList];
    }
}

#pragma mark - UI

- (void)buildUI {
    AssistSidebarBackgroundView *background = [[AssistSidebarBackgroundView alloc] initWithFrame:NSZeroRect];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.wantsLayer = YES;
    __weak typeof(self) weakSelf = self;
    background.onAppearanceChange = ^{
        [weakSelf applyChromeColors];
    };
    self.backgroundView = background;

    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.hidden = YES;
    [root addSubview:background];

    NSView *headerBar = [[NSView alloc] initWithFrame:NSZeroRect];
    headerBar.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [NSTextField labelWithString:@"助手"];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:13];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.closeButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameStopProgressTemplate]
                                          target:self
                                          action:@selector(closeClicked:)];
    self.closeButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    self.closeButton.bordered = NO;
    self.closeButton.toolTip = @"关闭";
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.addRecipeButton = [NSButton buttonWithTitle:@"＋登录"
                                              target:self
                                              action:@selector(beginNewRecipe)];
    self.addRecipeButton.bezelStyle = NSBezelStyleRounded;
    self.addRecipeButton.controlSize = NSControlSizeMini;
    self.addRecipeButton.toolTip = @"新建登录配置";
    self.addRecipeButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.addMemoButton = [NSButton buttonWithTitle:@"＋备忘"
                                            target:self
                                            action:@selector(beginNewMemo)];
    self.addMemoButton.bezelStyle = NSBezelStyleRounded;
    self.addMemoButton.controlSize = NSControlSizeMini;
    self.addMemoButton.toolTip = @"新建站点备忘";
    self.addMemoButton.translatesAutoresizingMaskIntoConstraints = NO;

    [headerBar addSubview:self.titleLabel];
    [headerBar addSubview:self.addRecipeButton];
    [headerBar addSubview:self.addMemoButton];
    [headerBar addSubview:self.closeButton];

    self.scopeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.scopeControl.segmentCount = 2;
    [self.scopeControl setLabel:@"匹配当前" forSegment:0];
    [self.scopeControl setLabel:@"全部" forSegment:1];
    self.scopeControl.selectedSegment = 0;
    self.scopeControl.segmentStyle = NSSegmentStyleRounded;
    self.scopeControl.target = self;
    self.scopeControl.action = @selector(scopeChanged:);

    self.typeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.typeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.typeControl.segmentCount = 3;
    [self.typeControl setLabel:@"全部" forSegment:0];
    [self.typeControl setLabel:@"登录" forSegment:1];
    [self.typeControl setLabel:@"备忘" forSegment:2];
    self.typeControl.selectedSegment = 0;
    self.typeControl.segmentStyle = NSSegmentStyleRounded;
    self.typeControl.target = self;
    self.typeControl.action = @selector(typeChanged:);

    self.searchField = [SBTextField standardField];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholderString = @"搜索标题 / 主机";
    self.searchField.delegate = self;
    [self.searchField.heightAnchor constraintEqualToConstant:22].active = YES;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    self.scrollView = scroll;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.allowsEmptySelection = YES;
    table.allowsMultipleSelection = NO;
    table.backgroundColor = [NSColor clearColor];
    table.delegate = self;
    table.dataSource = self;
    table.target = self;
    table.doubleAction = @selector(tableDoubleClicked:);
    table.menu = [[NSMenu alloc] init];
    table.menu.delegate = (id<NSMenuDelegate>)self;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = 300;
    [table addTableColumn:col];
    scroll.documentView = table;
    self.tableView = table;

    NSView *empty = [[NSView alloc] initWithFrame:NSZeroRect];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    empty.hidden = YES;
    self.emptyContainer = empty;
    self.emptyTitleLabel = [NSTextField labelWithString:@"当前页暂无配置"];
    self.emptyTitleLabel.font = [NSFont boldSystemFontOfSize:13];
    self.emptyTitleLabel.alignment = NSTextAlignmentCenter;
    self.emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyDetailLabel = [NSTextField wrappingLabelWithString:@"可为当前网址新建登录配置或站点备忘。"];
    self.emptyDetailLabel.font = [NSFont systemFontOfSize:12];
    self.emptyDetailLabel.textColor = [NSColor secondaryLabelColor];
    self.emptyDetailLabel.alignment = NSTextAlignmentCenter;
    self.emptyDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyNewRecipeButton = [NSButton buttonWithTitle:@"新建登录…"
                                                   target:self
                                                   action:@selector(emptyNewRecipe:)];
    self.emptyNewRecipeButton.bezelStyle = NSBezelStyleRounded;
    self.emptyNewMemoButton = [NSButton buttonWithTitle:@"新建备忘…"
                                                 target:self
                                                 action:@selector(emptyNewMemo:)];
    self.emptyNewMemoButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *emptyButtons = [NSStackView stackViewWithViews:@[self.emptyNewRecipeButton, self.emptyNewMemoButton]];
    emptyButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    emptyButtons.spacing = 8;
    emptyButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [empty addSubview:self.emptyTitleLabel];
    [empty addSubview:self.emptyDetailLabel];
    [empty addSubview:emptyButtons];

    self.advancedSettingsButton = [NSButton buttonWithTitle:@"高级设置…"
                                                     target:self
                                                     action:@selector(advancedSettingsClicked:)];
    self.advancedSettingsButton.bezelStyle = NSBezelStyleRounded;
    self.advancedSettingsButton.controlSize = NSControlSizeSmall;
    NSStackView *footer = [NSStackView stackViewWithViews:@[self.advancedSettingsButton]];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.spacing = 8;
    footer.translatesAutoresizingMaskIntoConstraints = NO;

    self.detailContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.detailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailHeightConstraint = [self.detailContainer.heightAnchor constraintEqualToConstant:0];

    self.memoEditor = [[AssistSidebarMemoEditor alloc] init];
    self.memoEditor.delegate = self;
    self.memoEditor.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.memoEditor.view.hidden = YES;

    self.recipeEditor = [[AssistSidebarRecipeEditor alloc] init];
    self.recipeEditor.delegate = self;
    self.recipeEditor.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.recipeEditor.view.hidden = YES;

    [self.detailContainer addSubview:self.memoEditor.view];
    [self.detailContainer addSubview:self.recipeEditor.view];
    [NSLayoutConstraint activateConstraints:@[
        [self.memoEditor.view.topAnchor constraintEqualToAnchor:self.detailContainer.topAnchor],
        [self.memoEditor.view.leadingAnchor constraintEqualToAnchor:self.detailContainer.leadingAnchor],
        [self.memoEditor.view.trailingAnchor constraintEqualToAnchor:self.detailContainer.trailingAnchor],
        [self.memoEditor.view.bottomAnchor constraintEqualToAnchor:self.detailContainer.bottomAnchor],
        [self.recipeEditor.view.topAnchor constraintEqualToAnchor:self.detailContainer.topAnchor],
        [self.recipeEditor.view.leadingAnchor constraintEqualToAnchor:self.detailContainer.leadingAnchor],
        [self.recipeEditor.view.trailingAnchor constraintEqualToAnchor:self.detailContainer.trailingAnchor],
        [self.recipeEditor.view.bottomAnchor constraintEqualToAnchor:self.detailContainer.bottomAnchor],
    ]];

    AssistSidebarResizeView *handle = [[AssistSidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
    };
    handle.onDragToOffset = ^(CGFloat delta) {
        // 左缘右移 → 变窄
        [weakSelf applyWidth:weakSelf.dragStartWidth - delta];
    };
    handle.onDragEnded = ^{
        [weakSelf persistWidth];
    };
    self.resizeHandle = handle;

    AssistSidebarDetailResizeView *detailHandle = [[AssistSidebarDetailResizeView alloc] initWithFrame:NSZeroRect];
    detailHandle.translatesAutoresizingMaskIntoConstraints = NO;
    detailHandle.hidden = YES;
    detailHandle.onDragBegan = ^{
        weakSelf.dragStartDetailHeight = weakSelf.detailHeightConstraint.constant;
        weakSelf.dragStartFlexibleSpan = NSHeight(weakSelf.scrollView.frame) + weakSelf.detailHeightConstraint.constant;
    };
    detailHandle.onDragToOffset = ^(CGFloat deltaY) {
        // 分隔条上移（屏幕 Y↑）→ 详情变高
        [weakSelf applyDetailHeight:weakSelf.dragStartDetailHeight + deltaY];
    };
    detailHandle.onDragEnded = ^{
        [weakSelf persistDetailHeight];
    };
    self.detailResizeHandle = detailHandle;
    self.detailResizeHandleHeightConstraint = [detailHandle.heightAnchor constraintEqualToConstant:0];

    NSView *edgeSep = [[NSView alloc] initWithFrame:NSZeroRect];
    edgeSep.translatesAutoresizingMaskIntoConstraints = NO;
    edgeSep.wantsLayer = YES;
    if (@available(macOS 10.14, *)) {
        edgeSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    }

    [root addSubview:headerBar];
    [root addSubview:self.scopeControl];
    [root addSubview:self.typeControl];
    [root addSubview:self.searchField];
    [root addSubview:scroll];
    [root addSubview:empty];
    [root addSubview:detailHandle];
    [root addSubview:self.detailContainer];
    [root addSubview:footer];
    [root addSubview:edgeSep];
    [root addSubview:handle];

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;
    self.detailHeightConstraint.active = YES;
    self.detailResizeHandleHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:root.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],

        [edgeSep.leadingAnchor constraintEqualToAnchor:handle.trailingAnchor],
        [edgeSep.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edgeSep.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edgeSep.widthAnchor constraintEqualToConstant:1],

        [headerBar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [headerBar.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor],
        [headerBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [headerBar.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:headerBar.leadingAnchor constant:12],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:headerBar.trailingAnchor constant:-10],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:22],
        [self.closeButton.heightAnchor constraintEqualToConstant:22],
        [self.addMemoButton.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-6],
        [self.addMemoButton.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],
        [self.addRecipeButton.trailingAnchor constraintEqualToAnchor:self.addMemoButton.leadingAnchor constant:-4],
        [self.addRecipeButton.centerYAnchor constraintEqualToAnchor:headerBar.centerYAnchor],

        [self.scopeControl.topAnchor constraintEqualToAnchor:headerBar.bottomAnchor constant:8],
        [self.scopeControl.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor constant:10],
        [self.scopeControl.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-10],

        [self.typeControl.topAnchor constraintEqualToAnchor:self.scopeControl.bottomAnchor constant:6],
        [self.typeControl.leadingAnchor constraintEqualToAnchor:self.scopeControl.leadingAnchor],
        [self.typeControl.trailingAnchor constraintEqualToAnchor:self.scopeControl.trailingAnchor],

        [self.searchField.topAnchor constraintEqualToAnchor:self.typeControl.bottomAnchor constant:8],
        [self.searchField.leadingAnchor constraintEqualToAnchor:self.scopeControl.leadingAnchor],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.scopeControl.trailingAnchor],

        [scroll.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:detailHandle.topAnchor],

        [empty.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [empty.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [empty.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [empty.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],

        [self.emptyTitleLabel.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],
        [self.emptyTitleLabel.centerYAnchor constraintEqualToAnchor:empty.centerYAnchor constant:-36],
        [self.emptyDetailLabel.topAnchor constraintEqualToAnchor:self.emptyTitleLabel.bottomAnchor constant:6],
        [self.emptyDetailLabel.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor constant:24],
        [self.emptyDetailLabel.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor constant:-24],
        [emptyButtons.topAnchor constraintEqualToAnchor:self.emptyDetailLabel.bottomAnchor constant:12],
        [emptyButtons.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],

        [detailHandle.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor],
        [detailHandle.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [detailHandle.bottomAnchor constraintEqualToAnchor:self.detailContainer.topAnchor],

        [self.detailContainer.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor],
        [self.detailContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.detailContainer.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-6],

        [footer.leadingAnchor constraintEqualToAnchor:edgeSep.trailingAnchor constant:10],
        [footer.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-10],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-10],
    ]];

    self.view = root;
    [self applyChromeColors];
}

- (void)applyChromeColors {
    if (@available(macOS 10.14, *)) {
        self.backgroundView.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    } else {
        self.backgroundView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    }
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
        self.currentWidth = [AssistSidebarSettings sharedSettings].sidebarWidth;
        self.view.hidden = NO;
        [self applyChromeColors];
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
            [self consumePendingReveal];
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
        context.allowsImplicitAnimation = NO;
        self.widthConstraint.constant = next;
        [self.view.superview layoutSubtreeIfNeeded];
    } completionHandler:nil];
}

- (void)persistWidth {
    [AssistSidebarSettings sharedSettings].sidebarWidth = self.currentWidth;
    if ([self.delegate respondsToSelector:@selector(assistSidebar:didChangeWidth:)]) {
        [self.delegate assistSidebar:self didChangeWidth:self.currentWidth];
    }
}

- (CGFloat)clampedDetailHeight:(CGFloat)proposed usingFlexibleSpan:(CGFloat)flexibleSpan {
    CGFloat maxByList = flexibleSpan - kListMinHeight;
    CGFloat minH = kDetailMinHeight;
    CGFloat maxH = MIN(kDetailMaxHeight, maxByList);
    if (maxH < minH) {
        // 侧栏整体过矮：尽量保住列表，允许详情低于常规下限。
        maxH = MAX(80.0, maxByList);
        minH = MIN(minH, maxH);
    }
    return MIN(maxH, MAX(minH, proposed));
}

- (void)applyDetailHeight:(CGFloat)height {
    CGFloat span = self.dragStartFlexibleSpan;
    if (span < 1) {
        span = NSHeight(self.scrollView.frame) + MAX(self.detailHeightConstraint.constant, 0);
    }
    CGFloat next = [self clampedDetailHeight:height usingFlexibleSpan:span];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        context.allowsImplicitAnimation = NO;
        self.detailHeightConstraint.constant = next;
        [self.view layoutSubtreeIfNeeded];
    } completionHandler:nil];
}

- (void)persistDetailHeight {
    CGFloat height = self.detailHeightConstraint.constant;
    if (height < 1) {
        return;
    }
    [AssistSidebarSettings sharedSettings].detailHeight = height;
}

- (void)expandDetailPanel {
    CGFloat remembered = [AssistSidebarSettings sharedSettings].detailHeight;
    CGFloat span = NSHeight(self.scrollView.frame) + MAX(self.detailHeightConstraint.constant, 0);
    if (span < 1) {
        // 首次展开时尚无布局：先用记忆值，下一轮 layout 再钳制。
        span = remembered + kListMinHeight;
    }
    CGFloat height = [self clampedDetailHeight:remembered usingFlexibleSpan:MAX(span, remembered + kListMinHeight)];
    self.detailResizeHandle.hidden = NO;
    self.detailResizeHandleHeightConstraint.constant = kDetailResizeHandleHeight;
    self.detailHeightConstraint.constant = height;
}

- (void)collapseDetailPanel {
    self.detailResizeHandle.hidden = YES;
    self.detailResizeHandleHeightConstraint.constant = 0;
    self.detailHeightConstraint.constant = 0;
}

- (void)installKeyMonitor {
    if (self.localKeyMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                 handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53 && weakSelf.visible) {
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

- (void)closeClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(assistSidebarDidRequestClose:)]) {
        [self.delegate assistSidebarDidRequestClose:self];
    }
}

#pragma mark - Filters

- (void)setScope:(AssistSidebarScope)scope {
    _scope = scope;
    self.scopeControl.selectedSegment = (NSInteger)scope;
    if (self.visible) {
        [self reloadList];
    }
}

- (void)setTypeFilter:(AssistSidebarTypeFilter)typeFilter {
    _typeFilter = typeFilter;
    self.typeControl.selectedSegment = (NSInteger)typeFilter;
    if (self.visible) {
        [self reloadList];
    }
}

- (void)scopeChanged:(id)sender {
    (void)sender;
    self.scope = (AssistSidebarScope)self.scopeControl.selectedSegment;
}

- (void)typeChanged:(id)sender {
    (void)sender;
    self.typeFilter = (AssistSidebarTypeFilter)self.typeControl.selectedSegment;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != self.searchField) {
        return;
    }
    if (self.searchDebounceBlock) {
        dispatch_block_cancel(self.searchDebounceBlock);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf reloadList];
    });
    self.searchDebounceBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSearchDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

#pragma mark - Data

- (nullable NSURL *)currentURL {
    if ([self.delegate respondsToSelector:@selector(assistSidebarCurrentURL:)]) {
        return [self.delegate assistSidebarCurrentURL:self];
    }
    return nil;
}

- (BOOL)rowMatchesSearch:(NSString *)title host:(NSString *)host path:(NSString *)path {
    NSString *q = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (q.length == 0) {
        return YES;
    }
    NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", title ?: @"", host ?: @"", path ?: @""] lowercaseString];
    return [hay containsString:q.lowercaseString];
}

- (void)reloadList {
    NSURL *url = [self currentURL];
    NSMutableArray<AssistSidebarRow *> *rows = [NSMutableArray array];

    BOOL showRecipes = (self.typeFilter == AssistSidebarTypeFilterAll ||
                        self.typeFilter == AssistSidebarTypeFilterRecipes);
    BOOL showMemos = (self.typeFilter == AssistSidebarTypeFilterAll ||
                      self.typeFilter == AssistSidebarTypeFilterMemos);

    NSArray<LoginRecipe *> *recipes = @[];
    NSArray<FormMemo *> *memos = @[];
    if (self.scope == AssistSidebarScopeMatched) {
        if (url) {
            recipes = [[LoginRecipeStore sharedStore] recipesMatchingURL:url];
            memos = [[FormMemoStore sharedStore] memosMatchingURL:url];
        }
    } else {
        recipes = [[LoginRecipeStore sharedStore] allRecipes];
        memos = [[FormMemoStore sharedStore] allMemos];
    }

    if (showRecipes) {
        NSMutableArray<LoginRecipe *> *filtered = [NSMutableArray array];
        for (LoginRecipe *recipe in recipes) {
            if ([self rowMatchesSearch:recipe.title host:recipe.host path:recipe.pathPrefix ?: @""]) {
                [filtered addObject:recipe];
            }
        }
        if (filtered.count > 0) {
            AssistSidebarRow *section = [[AssistSidebarRow alloc] init];
            section.kind = AssistSidebarRowKindSection;
            section.sectionTitle = [NSString stringWithFormat:@"登录（%lu）", (unsigned long)filtered.count];
            [rows addObject:section];
            for (LoginRecipe *recipe in filtered) {
                AssistSidebarRow *row = [[AssistSidebarRow alloc] init];
                row.kind = AssistSidebarRowKindRecipe;
                row.recipe = recipe;
                [rows addObject:row];
            }
        }
    }

    if (showMemos) {
        NSMutableArray<FormMemo *> *filtered = [NSMutableArray array];
        for (FormMemo *memo in memos) {
            if ([self rowMatchesSearch:memo.title host:memo.host path:memo.pathPrefix ?: @""]) {
                [filtered addObject:memo];
            }
        }
        if (filtered.count > 0) {
            AssistSidebarRow *section = [[AssistSidebarRow alloc] init];
            section.kind = AssistSidebarRowKindSection;
            section.sectionTitle = [NSString stringWithFormat:@"站点备忘（%lu）", (unsigned long)filtered.count];
            [rows addObject:section];
            for (FormMemo *memo in filtered) {
                AssistSidebarRow *row = [[AssistSidebarRow alloc] init];
                row.kind = AssistSidebarRowKindMemo;
                row.memo = memo;
                [rows addObject:row];
            }
        }
    }

    self.rows = rows;
    [self.tableView reloadData];
    [self restoreSelection];
    [self refreshEmptyState];
    [self updateEditButtonEnabled];

    // 编辑中保留表单，避免 Store 通知把未保存/刚保存的输入冲掉（RE-0）。
    BOOL editingNewMemo = (!self.memoEditor.view.hidden && self.memoEditor.editingMemoID.length == 0);
    BOOL editingNewRecipe = (!self.recipeEditor.view.hidden && self.recipeEditor.editingRecipeID.length == 0);
    BOOL preservingRecipeEditor =
        (!self.recipeEditor.view.hidden &&
         self.recipeEditor.editingRecipeID.length > 0 &&
         [self.recipeEditor.editingRecipeID isEqualToString:self.selectedRecipeID]);
    BOOL preservingMemoEditor =
        (!self.memoEditor.view.hidden &&
         self.memoEditor.editingMemoID.length > 0 &&
         [self.memoEditor.editingMemoID isEqualToString:self.selectedMemoID]);
    if (editingNewMemo || editingNewRecipe || preservingRecipeEditor || preservingMemoEditor) {
        return;
    }
    if (self.selectedMemoID.length > 0) {
        FormMemo *memo = [[FormMemoStore sharedStore] memoWithID:self.selectedMemoID];
        if (memo) {
            [self showMemoEditorLoading:memo];
        } else {
            [self hideDetailEditors];
        }
    } else if (self.selectedRecipeID.length > 0) {
        LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:self.selectedRecipeID];
        if (recipe) {
            [self showRecipeEditorLoading:recipe];
        } else {
            [self hideDetailEditors];
        }
    }
}

- (void)refreshEmptyState {
    BOOL empty = YES;
    for (AssistSidebarRow *row in self.rows) {
        if (row.kind != AssistSidebarRowKindSection) {
            empty = NO;
            break;
        }
    }
    self.emptyContainer.hidden = !empty;
    self.scrollView.hidden = empty;
    if (self.scope == AssistSidebarScopeMatched) {
        self.emptyTitleLabel.stringValue = @"当前页暂无配置";
        self.emptyDetailLabel.stringValue = @"可为当前网址新建登录配置或站点备忘。也可切换到「全部」查看已有条目。";
    } else {
        self.emptyTitleLabel.stringValue = @"没有匹配的条目";
        self.emptyDetailLabel.stringValue = @"调整类型过滤或搜索词，或新建登录 / 备忘。";
    }
}

- (void)restoreSelection {
    if (self.selectedRecipeID.length > 0) {
        for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
            AssistSidebarRow *row = self.rows[i];
            if (row.kind == AssistSidebarRowKindRecipe &&
                [row.recipe.recipeID isEqualToString:self.selectedRecipeID]) {
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                return;
            }
        }
    }
    if (self.selectedMemoID.length > 0) {
        for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
            AssistSidebarRow *row = self.rows[i];
            if (row.kind == AssistSidebarRowKindMemo &&
                [row.memo.memoID isEqualToString:self.selectedMemoID]) {
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                return;
            }
        }
    }
}

- (void)consumePendingReveal {
    if (self.pendingRevealRecipeID.length > 0) {
        NSString *rid = self.pendingRevealRecipeID;
        self.pendingRevealRecipeID = nil;
        [self selectRecipeID:rid];
        return;
    }
    if (self.pendingRevealMemoID.length > 0) {
        NSString *mid = self.pendingRevealMemoID;
        self.pendingRevealMemoID = nil;
        [self selectMemoID:mid];
    }
}

- (void)revealRecipeID:(NSString *)recipeID {
    self.typeFilter = AssistSidebarTypeFilterRecipes;
    if (recipeID.length > 0) {
        self.pendingRevealRecipeID = recipeID;
    }
    if (self.visible) {
        [self reloadList];
        [self consumePendingReveal];
    } else {
        [self setVisible:YES animated:YES];
    }
}

- (void)revealMemoID:(NSString *)memoID {
    self.typeFilter = AssistSidebarTypeFilterMemos;
    if (memoID.length > 0) {
        self.pendingRevealMemoID = memoID;
    }
    if (self.visible) {
        [self reloadList];
        [self consumePendingReveal];
    } else {
        [self setVisible:YES animated:YES];
    }
}

- (void)selectRecipeID:(NSString *)recipeID {
    self.selectedRecipeID = recipeID;
    self.selectedMemoID = nil;
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:recipeID];
    if (recipe) {
        [self showRecipeEditorLoading:recipe];
    } else {
        [self hideDetailEditors];
    }
    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        AssistSidebarRow *row = self.rows[i];
        if (row.kind == AssistSidebarRowKindRecipe &&
            [row.recipe.recipeID isEqualToString:recipeID]) {
            self.suppressingSelectionLoad = YES;
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self.tableView scrollRowToVisible:i];
            self.suppressingSelectionLoad = NO;
            [self updateEditButtonEnabled];
            return;
        }
    }
    [self updateEditButtonEnabled];
}

- (void)selectMemoID:(NSString *)memoID {
    self.selectedMemoID = memoID;
    self.selectedRecipeID = nil;
    FormMemo *memo = [[FormMemoStore sharedStore] memoWithID:memoID];
    if (memo) {
        [self showMemoEditorLoading:memo];
    } else {
        [self hideDetailEditors];
    }
    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        AssistSidebarRow *row = self.rows[i];
        if (row.kind == AssistSidebarRowKindMemo &&
            [row.memo.memoID isEqualToString:memoID]) {
            self.suppressingSelectionLoad = YES;
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self.tableView scrollRowToVisible:i];
            self.suppressingSelectionLoad = NO;
            [self updateEditButtonEnabled];
            return;
        }
    }
    [self updateEditButtonEnabled];
}

- (void)beginNewMemo {
    self.typeFilter = AssistSidebarTypeFilterMemos;
    self.selectedRecipeID = nil;
    self.selectedMemoID = nil;
    self.suppressingSelectionLoad = YES;
    [self.tableView deselectAll:nil];
    self.suppressingSelectionLoad = NO;
    [self showMemoEditorForNew];
    [self updateEditButtonEnabled];
}

- (void)beginNewRecipe {
    self.typeFilter = AssistSidebarTypeFilterRecipes;
    self.selectedRecipeID = nil;
    self.selectedMemoID = nil;
    self.suppressingSelectionLoad = YES;
    [self.tableView deselectAll:nil];
    self.suppressingSelectionLoad = NO;
    [self showRecipeEditorForNew];
    [self updateEditButtonEnabled];
}

- (void)showMemoEditorLoading:(FormMemo *)memo {
    self.recipeEditor.view.hidden = YES;
    [self.recipeEditor clear];
    self.memoEditor.view.hidden = NO;
    [self expandDetailPanel];
    [self.memoEditor loadMemo:memo];
}

- (void)showMemoEditorForNew {
    self.recipeEditor.view.hidden = YES;
    [self.recipeEditor clear];
    self.memoEditor.view.hidden = NO;
    [self expandDetailPanel];
    [self.memoEditor beginNewMemoPrefillingFromCurrentURL];
}

- (void)showRecipeEditorLoading:(LoginRecipe *)recipe {
    self.memoEditor.view.hidden = YES;
    [self.memoEditor clear];
    self.recipeEditor.view.hidden = NO;
    [self expandDetailPanel];
    [self.recipeEditor loadRecipe:recipe];
}

- (void)showRecipeEditorForNew {
    self.memoEditor.view.hidden = YES;
    [self.memoEditor clear];
    self.recipeEditor.view.hidden = NO;
    [self expandDetailPanel];
    [self.recipeEditor beginNewRecipePrefillingFromCurrentURL];
}

- (void)hideDetailEditors {
    [self.memoEditor clear];
    [self.recipeEditor clear];
    self.memoEditor.view.hidden = YES;
    self.recipeEditor.view.hidden = YES;
    [self collapseDetailPanel];
}

- (void)hideMemoEditor {
    [self hideDetailEditors];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.rows.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return 28;
    }
    return self.rows[row].kind == AssistSidebarRowKindSection ? 26 : 54;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return NO;
    }
    return self.rows[row].kind != AssistSidebarRowKindSection;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    AssistSidebarRow *item = (row >= 0 && row < (NSInteger)self.rows.count) ? self.rows[row] : nil;
    if (!item) {
        return nil;
    }

    if (item.kind == AssistSidebarRowKindSection) {
        NSString *identifier = @"AssistSection";
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
            cell.identifier = identifier;
            NSTextField *text = [NSTextField labelWithString:@""];
            text.translatesAutoresizingMaskIntoConstraints = NO;
            text.font = [NSFont boldSystemFontOfSize:11];
            text.textColor = [NSColor secondaryLabelColor];
            [cell addSubview:text];
            cell.textField = text;
            [NSLayoutConstraint activateConstraints:@[
                [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
                [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
                [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        cell.textField.stringValue = item.sectionTitle ?: @"";
        return cell;
    }

    NSString *identifier = @"AssistItem";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField *title = [NSTextField labelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:13];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        title.tag = 101;

        NSTextField *subtitle = [NSTextField labelWithString:@""];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.font = [NSFont systemFontOfSize:11];
        subtitle.textColor = [NSColor secondaryLabelColor];
        subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
        subtitle.tag = 102;

        NSButton *action = [NSButton buttonWithTitle:@"执行"
                                              target:self
                                              action:@selector(rowActionClicked:)];
        action.bezelStyle = NSBezelStyleRoundRect;
        action.controlSize = NSControlSizeSmall;
        action.translatesAutoresizingMaskIntoConstraints = NO;
        action.tag = 103;

        [cell addSubview:title];
        [cell addSubview:subtitle];
        [cell addSubview:action];
        cell.textField = title;

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
            [title.trailingAnchor constraintEqualToAnchor:action.leadingAnchor constant:-8],
            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
            [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [action.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [action.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [action.widthAnchor constraintGreaterThanOrEqualToConstant:52],
        ]];
    }

    NSTextField *title = [cell viewWithTag:101];
    NSTextField *subtitle = [cell viewWithTag:102];
    NSButton *action = [cell viewWithTag:103];
    action.identifier = [NSString stringWithFormat:@"%ld", (long)row];

    if (item.kind == AssistSidebarRowKindRecipe) {
        LoginRecipe *recipe = item.recipe;
        NSString *name = recipe.title.length > 0 ? recipe.title : recipe.host;
        title.stringValue = recipe.isDefault ? [NSString stringWithFormat:@"★ %@", name] : name;
        NSMutableString *sub = [NSMutableString stringWithString:recipe.host ?: @""];
        if (recipe.pathPrefix.length > 0) {
            [sub appendFormat:@" · %@", recipe.pathPrefix];
        }
        subtitle.stringValue = sub;
        action.title = @"登录";
    } else {
        FormMemo *memo = item.memo;
        NSString *name = memo.title.length > 0 ? memo.title : memo.host;
        title.stringValue = memo.isDefault ? [NSString stringWithFormat:@"★ %@", name] : name;
        NSMutableString *sub = [NSMutableString stringWithString:memo.host ?: @""];
        if (memo.pathPrefix.length > 0) {
            [sub appendFormat:@" · %@", memo.pathPrefix];
        }
        [sub appendFormat:@" · %lu 字段", (unsigned long)memo.fields.count];
        subtitle.stringValue = sub;
        action.title = @"填入";
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.suppressingSelectionLoad) {
        return;
    }
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        self.selectedRecipeID = nil;
        self.selectedMemoID = nil;
        [self hideDetailEditors];
        [self updateEditButtonEnabled];
        return;
    }
    AssistSidebarRow *item = self.rows[row];
    if (item.kind == AssistSidebarRowKindRecipe) {
        self.selectedRecipeID = item.recipe.recipeID;
        self.selectedMemoID = nil;
        [self showRecipeEditorLoading:item.recipe];
    } else if (item.kind == AssistSidebarRowKindMemo) {
        self.selectedMemoID = item.memo.memoID;
        self.selectedRecipeID = nil;
        [self showMemoEditorLoading:item.memo];
    }
    [self updateEditButtonEnabled];
}

- (void)updateEditButtonEnabled {
    (void)0;
}

#pragma mark - Actions

- (void)rowActionClicked:(NSButton *)sender {
    NSInteger row = sender.identifier.integerValue;
    [self runRowAtIndex:row fillOnly:NO];
}

- (void)tableDoubleClicked:(id)sender {
    (void)sender;
    [self runRowAtIndex:self.tableView.clickedRow fillOnly:NO];
}

- (void)runRowAtIndex:(NSInteger)row fillOnly:(BOOL)fillOnly {
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    AssistSidebarRow *item = self.rows[row];
    if (item.kind == AssistSidebarRowKindRecipe && item.recipe) {
        if ([self.delegate respondsToSelector:@selector(assistSidebar:runRecipe:fillOnly:)]) {
            [self.delegate assistSidebar:self runRecipe:item.recipe fillOnly:fillOnly];
        }
    } else if (item.kind == AssistSidebarRowKindMemo && item.memo) {
        if ([self.delegate respondsToSelector:@selector(assistSidebar:runMemo:)]) {
            [self.delegate assistSidebar:self runMemo:item.memo];
        }
    }
}

- (void)editInSettingsClicked:(id)sender {
    (void)sender;
    [self advancedSettingsClicked:sender];
}

- (void)advancedSettingsClicked:(id)sender {
    (void)sender;
    BOOL preferMemos = (self.typeFilter == AssistSidebarTypeFilterMemos) || self.selectedMemoID.length > 0;
    if ([self.delegate respondsToSelector:@selector(assistSidebarDidRequestAdvancedSettings:preferMemos:)]) {
        [self.delegate assistSidebarDidRequestAdvancedSettings:self preferMemos:preferMemos];
    }
}

- (void)emptyNewRecipe:(id)sender {
    (void)sender;
    [self beginNewRecipe];
}

- (void)emptyNewMemo:(id)sender {
    (void)sender;
    [self beginNewMemo];
}

#pragma mark - Memo editor delegate

- (NSURL *)memoEditorCurrentURL:(AssistSidebarMemoEditor *)editor {
    (void)editor;
    return [self currentURL];
}

- (WKWebView *)memoEditorWebViewForPicking:(AssistSidebarMemoEditor *)editor {
    (void)editor;
    if ([self.delegate respondsToSelector:@selector(assistSidebarWebViewForPicking:)]) {
        return [self.delegate assistSidebarWebViewForPicking:self];
    }
    return nil;
}

- (void)memoEditor:(AssistSidebarMemoEditor *)editor didSaveMemo:(FormMemo *)memo {
    (void)editor;
    self.selectedMemoID = memo.memoID;
    self.selectedRecipeID = nil;
    [self reloadList];
    [self selectMemoID:memo.memoID];
}

- (void)memoEditor:(AssistSidebarMemoEditor *)editor didDeleteMemoID:(NSString *)memoID {
    (void)editor;
    (void)memoID;
    self.selectedMemoID = nil;
    [self hideDetailEditors];
    [self reloadList];
}

- (void)memoEditorDidCancelNew:(AssistSidebarMemoEditor *)editor {
    (void)editor;
    [self hideDetailEditors];
}

#pragma mark - Recipe editor delegate

- (NSURL *)recipeEditorCurrentURL:(AssistSidebarRecipeEditor *)editor {
    (void)editor;
    return [self currentURL];
}

- (WKWebView *)recipeEditorWebViewForPicking:(AssistSidebarRecipeEditor *)editor {
    (void)editor;
    if ([self.delegate respondsToSelector:@selector(assistSidebarWebViewForPicking:)]) {
        return [self.delegate assistSidebarWebViewForPicking:self];
    }
    return nil;
}

- (void)recipeEditor:(AssistSidebarRecipeEditor *)editor didSaveRecipe:(LoginRecipe *)recipe {
    (void)editor;
    self.selectedRecipeID = recipe.recipeID;
    self.selectedMemoID = nil;
    // 凭证已在 editor 内先写入；此处只刷列表并选中。
    // selectRecipeID → loadRecipe 此时可读到新钥匙串/内存缓存，作真源对齐。
    [self reloadList];
    [self selectRecipeID:recipe.recipeID];
}

- (void)recipeEditor:(AssistSidebarRecipeEditor *)editor didDeleteRecipeID:(NSString *)recipeID {
    (void)editor;
    (void)recipeID;
    self.selectedRecipeID = nil;
    [self hideDetailEditors];
    [self reloadList];
}

- (void)recipeEditorDidCancelNew:(AssistSidebarRecipeEditor *)editor {
    (void)editor;
    [self hideDetailEditors];
}

#pragma mark - Context menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) {
        row = self.tableView.selectedRow;
    }
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    AssistSidebarRow *item = self.rows[row];
    if (item.kind == AssistSidebarRowKindSection) {
        return;
    }

    if (item.kind == AssistSidebarRowKindRecipe) {
        NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"一键登录"
                                                     action:@selector(contextRun:)
                                              keyEquivalent:@""];
        run.target = self;
        run.representedObject = @(row);
        [menu addItem:run];
        NSMenuItem *fill = [[NSMenuItem alloc] initWithTitle:@"仅填入"
                                                      action:@selector(contextFillOnly:)
                                               keyEquivalent:@""];
        fill.target = self;
        fill.representedObject = @(row);
        [menu addItem:fill];
        NSMenuItem *def = [[NSMenuItem alloc] initWithTitle:@"设为默认"
                                                     action:@selector(contextSetDefault:)
                                              keyEquivalent:@""];
        def.target = self;
        def.representedObject = @(row);
        [menu addItem:def];
    } else {
        NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"填入备忘"
                                                     action:@selector(contextRun:)
                                              keyEquivalent:@""];
        run.target = self;
        run.representedObject = @(row);
        [menu addItem:run];
        NSMenuItem *def = [[NSMenuItem alloc] initWithTitle:@"设为默认"
                                                     action:@selector(contextSetDefault:)
                                              keyEquivalent:@""];
        def.target = self;
        def.representedObject = @(row);
        [menu addItem:def];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"在侧栏编辑"
                                                  action:@selector(contextEdit:)
                                           keyEquivalent:@""];
    edit.target = self;
    edit.representedObject = @(row);
    [menu addItem:edit];
    NSMenuItem *del = [[NSMenuItem alloc] initWithTitle:@"删除…"
                                                 action:@selector(contextDelete:)
                                          keyEquivalent:@""];
    del.target = self;
    del.representedObject = @(row);
    [menu addItem:del];
}

- (void)contextRun:(NSMenuItem *)item {
    [self runRowAtIndex:[item.representedObject integerValue] fillOnly:NO];
}

- (void)contextFillOnly:(NSMenuItem *)item {
    [self runRowAtIndex:[item.representedObject integerValue] fillOnly:YES];
}

- (void)contextSetDefault:(NSMenuItem *)item {
    NSInteger row = [item.representedObject integerValue];
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    AssistSidebarRow *rowItem = self.rows[row];
    if (rowItem.kind == AssistSidebarRowKindRecipe) {
        [[LoginRecipeStore sharedStore] setDefaultRecipeID:rowItem.recipe.recipeID error:nil];
    } else if (rowItem.kind == AssistSidebarRowKindMemo) {
        [[FormMemoStore sharedStore] setDefaultMemoID:rowItem.memo.memoID error:nil];
    }
}

- (void)contextEdit:(NSMenuItem *)item {
    NSInteger row = [item.representedObject integerValue];
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    AssistSidebarRow *rowItem = self.rows[row];
    if (rowItem.kind == AssistSidebarRowKindRecipe) {
        [self selectRecipeID:rowItem.recipe.recipeID];
    } else if (rowItem.kind == AssistSidebarRowKindMemo) {
        [self selectMemoID:rowItem.memo.memoID];
    }
}

- (void)contextDelete:(NSMenuItem *)item {
    NSInteger row = [item.representedObject integerValue];
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return;
    }
    AssistSidebarRow *rowItem = self.rows[row];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if (rowItem.kind == AssistSidebarRowKindRecipe) {
        alert.messageText = @"删除此登录配置？";
        alert.informativeText = @"将同时删除钥匙串中的账号密码。";
        NSString *recipeID = rowItem.recipe.recipeID;
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse code) {
            if (code == NSAlertFirstButtonReturn) {
                [[LoginRecipeStore sharedStore] deleteRecipeWithID:recipeID error:nil];
            }
        }];
    } else if (rowItem.kind == AssistSidebarRowKindMemo) {
        alert.messageText = @"删除此站点备忘？";
        alert.informativeText = @"将删除该备忘下的全部字段文本。";
        NSString *memoID = rowItem.memo.memoID;
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse code) {
            if (code == NSAlertFirstButtonReturn) {
                [[FormMemoStore sharedStore] deleteMemoWithID:memoID error:nil];
            }
        }];
    }
}

@end
