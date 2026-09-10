#import "BrowserScraperSidebarController.h"
#import "BrowserScraperSettings.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserScraperDetector.h"
#import "BrowserScraperEngine.h"
#import "BrowserScraperMySQLWriter.h"
#import "BrowserScraperScheduleManager.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"
#import "SBTextView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320;
static const CGFloat kSidebarAbsoluteMaxWidth = 2400;
static const CGFloat kResizeHandleWidth = 8.0;

@interface BrowserScraperSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation BrowserScraperSidebarResizeView
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
    if (!window) return;
    self.dragging = YES;
    self.dragStartScreenX = [self screenXFromEvent:event];
    if (self.onDragBegan) self.onDragBegan();
    [[NSCursor resizeLeftRightCursor] push];
    while (self.dragging) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next || next.type == NSEventTypeLeftMouseUp) break;
        if (next.type == NSEventTypeLeftMouseDragged && self.onDragToOffset) {
            self.onDragToOffset([self screenXFromEvent:next] - self.dragStartScreenX);
        }
    }
    self.dragging = NO;
    [NSCursor pop];
    if (self.onDragEnded) self.onDragEnded();
}
@end

/// 让 ScrollView 内容从顶部排布（默认非 flipped 会贴底）。
@interface BrowserScraperFlippedView : NSView
@end
@implementation BrowserScraperFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface BrowserScraperSidebarController () <BrowserScraperEngineDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSView *rootView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, strong) BrowserScraperRecipe *draft;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, copy) NSArray<NSDictionary *> *candidates;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewRows;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSSegmentedControl *segment;
@property (nonatomic, strong) NSView *pagesHost;
@property (nonatomic, copy) NSArray<NSView *> *pageViews;
@property (nonatomic, strong) NSPopUpButton *recipePopup;
@property (nonatomic, strong) SBTextField *nameField;
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) SBTextField *containerField;
@property (nonatomic, strong) SBTextField *rowPathField;
@property (nonatomic, strong) NSPopUpButton *paginationPopup;
@property (nonatomic, strong) SBTextField *paginationSelectorField;
@property (nonatomic, strong) SBTextField *maxPagesField;
@property (nonatomic, strong) SBTextField *maxRowsField;
@property (nonatomic, strong) SBTextField *delayField;
@property (nonatomic, strong) NSPopUpButton *sessionPopup;
@property (nonatomic, strong) NSButton *scheduleCheck;
@property (nonatomic, strong) SBTextField *intervalField;
@property (nonatomic, strong) NSPopUpButton *sinkPopup;
@property (nonatomic, strong) SBTextField *filePathField;
@property (nonatomic, strong) SBTextField *mysqlHostField;
@property (nonatomic, strong) SBTextField *mysqlPortField;
@property (nonatomic, strong) SBTextField *mysqlDBField;
@property (nonatomic, strong) SBTextField *mysqlUserField;
@property (nonatomic, strong) SBSecureTextField *mysqlPasswordField;
@property (nonatomic, strong) SBTextField *mysqlTableField;
@property (nonatomic, strong) NSTableView *fieldsTable;
@property (nonatomic, strong) NSTableView *previewTable;
@property (nonatomic, strong) NSTableView *candidatesTable;
@property (nonatomic, strong) SBTextView *logView;
@property (nonatomic, strong) NSTextField *runStatusLabel;
@end

@implementation BrowserScraperSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [BrowserScraperSettings sharedSettings].sidebarWidth;
        _candidates = @[];
        _previewRows = @[];
        _engine = [[BrowserScraperEngine alloc] init];
        _engine.delegate = self;
        _draft = [BrowserScraperRecipe blankRecipeNamed:@"新配方"];
        [self buildUI];
    }
    return self;
}

- (NSView *)view {
    return self.rootView;
}

- (NSTextField *)makeLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)prepareFormControl:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view setContentHuggingPriority:NSLayoutPriorityDefaultLow
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
}

- (NSStackView *)vstack:(NSArray<NSView *> *)views {
    for (NSView *v in views) {
        [self prepareFormControl:v];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(8, 10, 12, 10);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setHuggingPriority:NSLayoutPriorityDefaultLow
               forOrientation:NSLayoutConstraintOrientationVertical];
    // 子视图横向撑满（纵向 stack 的 alignment 不能用 Width）
    for (NSView *v in stack.arrangedSubviews) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    }
    return stack;
}

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    root.hidden = YES;
    self.rootView = root;
    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    __weak typeof(self) weakSelf = self;
    BrowserScraperSidebarResizeView *handle = [[BrowserScraperSidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.wantsLayer = YES;
    handle.layer.backgroundColor = NSColor.separatorColor.CGColor;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
    };
    handle.onDragToOffset = ^(CGFloat delta) {
        [weakSelf applyWidth:weakSelf.dragStartWidth - delta];
    };
    handle.onDragEnded = ^{
        [BrowserScraperSettings sharedSettings].sidebarWidth = weakSelf.currentWidth;
        if ([weakSelf.delegate respondsToSelector:@selector(scraperSidebar:didChangeWidth:)]) {
            [weakSelf.delegate scraperSidebar:weakSelf didChangeWidth:weakSelf.currentWidth];
        }
    };

    NSButton *close = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeClicked:)];
    close.bezelStyle = NSBezelStyleRounded;
    self.titleLabel = [NSTextField labelWithString:@"页面爬虫"];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:13];
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.statusLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *headerSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    headerSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [headerSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [headerSpacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = [NSStackView stackViewWithViews:@[self.titleLabel, self.statusLabel, headerSpacer, close]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 8;
    header.translatesAutoresizingMaskIntoConstraints = NO;

    self.segment = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.segment.segmentCount = 5;
    [self.segment setLabel:@"本页" forSegment:0];
    [self.segment setLabel:@"字段" forSegment:1];
    [self.segment setLabel:@"翻页" forSegment:2];
    [self.segment setLabel:@"任务" forSegment:3];
    [self.segment setLabel:@"保存" forSegment:4];
    self.segment.selectedSegment = 0;
    self.segment.segmentStyle = NSSegmentStyleRounded;
    self.segment.target = self;
    self.segment.action = @selector(segmentChanged:);
    self.segment.translatesAutoresizingMaskIntoConstraints = NO;

    self.pagesHost = [[NSView alloc] initWithFrame:NSZeroRect];
    self.pagesHost.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pagesHost setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [self.pagesHost setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    NSArray<NSView *> *pages = @[
        [self buildPageFormPage],
        [self buildFieldsPage],
        [self wrapScroll:[self buildPaginationFormStack]],
        [self wrapScroll:[self buildTaskFormStack]],
        [self wrapScroll:[self buildSaveFormStack]],
    ];
    self.pageViews = pages;
    for (NSUInteger i = 0; i < pages.count; i++) {
        NSView *page = pages[i];
        page.translatesAutoresizingMaskIntoConstraints = NO;
        page.hidden = (i != 0);
        [self.pagesHost addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:self.pagesHost.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:self.pagesHost.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:self.pagesHost.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:self.pagesHost.bottomAnchor],
        ]];
    }

    self.runStatusLabel = [NSTextField labelWithString:@"就绪"];
    self.runStatusLabel.font = [NSFont systemFontOfSize:11];
    self.runStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *logScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    logScroll.hasVerticalScroller = YES;
    logScroll.borderType = NSBezelBorder;
    self.logView = [SBTextView standardTextView];
    self.logView.editable = NO;
    self.logView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    logScroll.documentView = self.logView;
    [logScroll.heightAnchor constraintEqualToConstant:72].active = YES;

    NSButton *runBtn = [NSButton buttonWithTitle:@"立即运行" target:self action:@selector(runClicked:)];
    NSButton *pauseBtn = [NSButton buttonWithTitle:@"暂停" target:self action:@selector(pauseClicked:)];
    NSButton *stopBtn = [NSButton buttonWithTitle:@"停止" target:self action:@selector(stopClicked:)];
    NSButton *saveBtn = [NSButton buttonWithTitle:@"保存配方" target:self action:@selector(saveRecipeClicked:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[runBtn, pauseBtn, stopBtn, saveBtn]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 6;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *body = [[NSView alloc] initWithFrame:NSZeroRect];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:header];
    [body addSubview:self.segment];
    [body addSubview:self.pagesHost];
    [body addSubview:self.runStatusLabel];
    [body addSubview:logScroll];
    [body addSubview:actions];

    [root addSubview:handle];
    [root addSubview:body];

    [NSLayoutConstraint activateConstraints:@[
        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],

        [body.leadingAnchor constraintEqualToAnchor:handle.trailingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:root.topAnchor],
        [body.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [header.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:10],
        [header.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-10],
        [header.topAnchor constraintEqualToAnchor:body.topAnchor constant:10],

        [self.segment.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:10],
        [self.segment.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-10],
        [self.segment.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],

        [self.pagesHost.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
        [self.pagesHost.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
        [self.pagesHost.topAnchor constraintEqualToAnchor:self.segment.bottomAnchor constant:6],
        [self.pagesHost.bottomAnchor constraintEqualToAnchor:self.runStatusLabel.topAnchor constant:-6],

        [self.runStatusLabel.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:10],
        [self.runStatusLabel.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-10],
        [self.runStatusLabel.bottomAnchor constraintEqualToAnchor:logScroll.topAnchor constant:-4],

        [logScroll.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:10],
        [logScroll.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-10],
        [logScroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-8],

        [actions.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:10],
        [actions.trailingAnchor constraintLessThanOrEqualToAnchor:body.trailingAnchor constant:-10],
        [actions.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-10],
    ]];
}

/// 表单页：ScrollView 铺满 Tab，内容从顶部开始并横向撑满。
- (NSView *)wrapScroll:(NSView *)content {
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.scrollerStyle = NSScrollerStyleOverlay;

    BrowserScraperFlippedView *doc = [[BrowserScraperFlippedView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:content];
    scroll.documentView = doc;

    [container addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:container.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [content.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
        [doc.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];
    return container;
}

- (NSTableView *)makeTable {
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = [[NSTableHeaderView alloc] init];
    table.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    table.delegate = self;
    table.dataSource = self;
    table.translatesAutoresizingMaskIntoConstraints = NO;
    return table;
}

- (NSScrollView *)boxedTableScroll:(NSTableView *)table height:(CGFloat)height {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    if (height > 0) {
        [scroll.heightAnchor constraintEqualToConstant:height].active = YES;
    }
    return scroll;
}

/// 「本页」：上方表单固定，检测候选表纵向撑满贴到日志上方。
- (NSView *)buildPageFormPage {
    NSView *page = [[NSView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;

    self.recipePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.recipePopup.target = self;
    self.recipePopup.action = @selector(recipePopupChanged:);
    self.nameField = [SBTextField standardField];
    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modePopup addItemsWithTitles:@[ @"表格 / 列表", @"单一数据" ]];
    self.containerField = [SBTextField standardField];
    self.rowPathField = [SBTextField standardField];

    NSButton *detect = [NSButton buttonWithTitle:@"智能检测整页" target:self action:@selector(detectClicked:)];
    NSButton *pickContainer = [NSButton buttonWithTitle:@"选择数据区" target:self action:@selector(pickContainerClicked:)];
    NSButton *reanalyze = [NSButton buttonWithTitle:@"识别循环节点" target:self action:@selector(reanalyzeContainerClicked:)];
    NSButton *newRecipe = [NSButton buttonWithTitle:@"新建配方" target:self action:@selector(newRecipeClicked:)];
    NSStackView *actionRow = [NSStackView stackViewWithViews:@[detect, pickContainer, reanalyze]];
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.alignment = NSLayoutAttributeCenterY;
    actionRow.spacing = 6;
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *topStack = [self vstack:@[
        [self makeLabel:@"配方"], self.recipePopup, newRecipe,
        [self makeLabel:@"名称"], self.nameField,
        [self makeLabel:@"模式"], self.modePopup,
        actionRow,
        [self makeLabel:@"容器 path"], self.containerField,
        [self makeLabel:@"行 path（循环节点）"], self.rowPathField,
        [self makeLabel:@"检测候选（表格 / 列表 / 卡片）"],
    ]];
    // vstack 已带 edgeInsets；此处作为顶部块，去掉底部多余空白感
    topStack.edgeInsets = NSEdgeInsetsMake(8, 10, 0, 10);
    [topStack setHuggingPriority:NSLayoutPriorityDefaultHigh
                  forOrientation:NSLayoutConstraintOrientationVertical];
    [topStack setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                         forOrientation:NSLayoutConstraintOrientationVertical];
    [topStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                       forOrientation:NSLayoutConstraintOrientationVertical];

    self.candidatesTable = [self makeTable];
    while (self.candidatesTable.tableColumns.count) {
        [self.candidatesTable removeTableColumn:self.candidatesTable.tableColumns.firstObject];
    }
    NSTableColumn *c0 = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    c0.title = @"类型";
    c0.width = 56;
    NSTableColumn *c1 = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    c1.title = @"候选";
    c1.width = 140;
    NSTableColumn *cScore = [[NSTableColumn alloc] initWithIdentifier:@"score"];
    cScore.title = @"分";
    cScore.width = 36;
    NSTableColumn *c2 = [[NSTableColumn alloc] initWithIdentifier:@"rows"];
    c2.title = @"行";
    c2.width = 40;
    [self.candidatesTable addTableColumn:c0];
    [self.candidatesTable addTableColumn:c1];
    [self.candidatesTable addTableColumn:cScore];
    [self.candidatesTable addTableColumn:c2];
    NSScrollView *candScroll = [self boxedTableScroll:self.candidatesTable height:0];
    [candScroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [candScroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    NSButton *useCandidate = [NSButton buttonWithTitle:@"采用选中候选" target:self action:@selector(useCandidateClicked:)];
    useCandidate.translatesAutoresizingMaskIntoConstraints = NO;
    [useCandidate setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                             forOrientation:NSLayoutConstraintOrientationVertical];

    [page addSubview:topStack];
    [page addSubview:candScroll];
    [page addSubview:useCandidate];

    [NSLayoutConstraint activateConstraints:@[
        [topStack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [topStack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [topStack.topAnchor constraintEqualToAnchor:page.topAnchor],

        [candScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [candScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-10],
        [candScroll.topAnchor constraintEqualToAnchor:topStack.bottomAnchor constant:4],
        [candScroll.bottomAnchor constraintEqualToAnchor:useCandidate.topAnchor constant:-8],
        [candScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],

        [useCandidate.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [useCandidate.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-10],
        [useCandidate.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:-4],
    ]];
    return page;
}

/// 字段页：预览表纵向撑满至日志上方，随 pagesHost / 窗口高度自动伸缩。
- (NSView *)buildFieldsPage {
    NSView *page = [[NSView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;

    self.fieldsTable = [self makeTable];
    while (self.fieldsTable.tableColumns.count) {
        [self.fieldsTable removeTableColumn:self.fieldsTable.tableColumns.firstObject];
    }
    for (NSArray *pair in @[ @[@"enabled", @"开"], @[@"name", @"列名"], @[@"kind", @"类型"], @[@"path", @"path"] ]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:pair[0]];
        col.title = pair[1];
        col.width = [pair[0] isEqualToString:@"enabled"] ? 28 : 100;
        [self.fieldsTable addTableColumn:col];
    }
    NSScrollView *fieldsScroll = [self boxedTableScroll:self.fieldsTable height:140];

    NSButton *addField = [NSButton buttonWithTitle:@"点选添加字段" target:self action:@selector(pickFieldClicked:)];
    NSButton *removeField = [NSButton buttonWithTitle:@"删除选中" target:self action:@selector(removeFieldClicked:)];
    NSButton *preview = [NSButton buttonWithTitle:@"刷新预览" target:self action:@selector(previewClicked:)];
    NSButton *copyPreview = [NSButton buttonWithTitle:@"复制预览" target:self action:@selector(copyPreviewClicked:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[addField, removeField, preview, copyPreview]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.spacing = 6;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [actions setHuggingPriority:NSLayoutPriorityDefaultHigh
                 forOrientation:NSLayoutConstraintOrientationVertical];

    NSTextField *previewLabel = [self makeLabel:@"预览"];

    self.previewTable = [self makeTable];
    NSScrollView *previewScroll = [self boxedTableScroll:self.previewTable height:0];
    [previewScroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [previewScroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    [page addSubview:fieldsScroll];
    [page addSubview:actions];
    [page addSubview:previewLabel];
    [page addSubview:previewScroll];

    [NSLayoutConstraint activateConstraints:@[
        [fieldsScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [fieldsScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-10],
        [fieldsScroll.topAnchor constraintEqualToAnchor:page.topAnchor constant:8],

        [actions.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [actions.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-10],
        [actions.topAnchor constraintEqualToAnchor:fieldsScroll.bottomAnchor constant:8],

        [previewLabel.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [previewLabel.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-10],
        [previewLabel.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:8],

        [previewScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:10],
        [previewScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-10],
        [previewScroll.topAnchor constraintEqualToAnchor:previewLabel.bottomAnchor constant:4],
        [previewScroll.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:-4],
        [previewScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],
    ]];
    return page;
}

- (NSStackView *)buildPaginationFormStack {
    self.paginationPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.paginationPopup addItemsWithTitles:@[ @"无", @"下一页按钮", @"页码", @"Load More", @"无限滚动" ]];
    self.paginationSelectorField = [SBTextField standardField];
    self.maxPagesField = [SBTextField standardField];
    self.maxRowsField = [SBTextField standardField];
    self.delayField = [SBTextField standardField];
    NSButton *pickPag = [NSButton buttonWithTitle:@"点选翻页控件" target:self action:@selector(pickPaginationClicked:)];
    return [self vstack:@[
        [self makeLabel:@"类型"], self.paginationPopup, pickPag,
        [self makeLabel:@"选择器"], self.paginationSelectorField,
        [self makeLabel:@"最大页数"], self.maxPagesField,
        [self makeLabel:@"最大行数"], self.maxRowsField,
        [self makeLabel:@"页间延迟(ms)"], self.delayField
    ]];
}

- (NSStackView *)buildTaskFormStack {
    self.sessionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.sessionPopup addItemsWithTitles:@[ @"共用浏览器 Cookie", @"独立会话" ]];
    self.scheduleCheck = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.scheduleCheck.buttonType = NSButtonTypeSwitch;
    self.scheduleCheck.title = @"启用定时爬取";
    self.intervalField = [SBTextField standardField];
    NSTextField *hint = [self makeLabel:@"定时由独立 MeoScrapeRunner / LaunchAgent 执行，不占用主窗口 WebView。"];
    hint.maximumNumberOfLines = 3;
    return [self vstack:@[
        [self makeLabel:@"会话"], self.sessionPopup,
        self.scheduleCheck,
        [self makeLabel:@"间隔(分钟)"], self.intervalField,
        hint
    ]];
}

- (NSStackView *)buildSaveFormStack {
    self.sinkPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.sinkPopup addItemsWithTitles:@[ @"Excel (xlsx)", @"CSV", @"JSON", @"MySQL" ]];
    self.filePathField = [SBTextField standardField];
    self.filePathField.placeholderString = @"空则写入下载文件夹";
    self.mysqlHostField = [SBTextField standardField];
    self.mysqlPortField = [SBTextField standardField];
    self.mysqlDBField = [SBTextField standardField];
    self.mysqlUserField = [SBTextField standardField];
    self.mysqlPasswordField = [SBSecureTextField standardField];
    self.mysqlTableField = [SBTextField standardField];
    NSButton *testMySQL = [NSButton buttonWithTitle:@"测试 MySQL 连接" target:self action:@selector(testMySQLClicked:)];
    return [self vstack:@[
        [self makeLabel:@"导出目标"], self.sinkPopup,
        [self makeLabel:@"文件路径"], self.filePathField,
        [self makeLabel:@"MySQL Host"], self.mysqlHostField,
        [self makeLabel:@"Port"], self.mysqlPortField,
        [self makeLabel:@"Database"], self.mysqlDBField,
        [self makeLabel:@"User"], self.mysqlUserField,
        [self makeLabel:@"Password"], self.mysqlPasswordField,
        [self makeLabel:@"Table"], self.mysqlTableField,
        testMySQL
    ]];
}

#pragma mark - Visibility

- (CGFloat)maxAllowedSidebarWidth {
    NSWindow *window = self.view.window;
    CGFloat half = 0;
    if (window) {
        half = floor(NSWidth(window.frame) * 0.5);
    } else if (NSScreen.mainScreen) {
        half = floor(NSWidth(NSScreen.mainScreen.visibleFrame) * 0.5);
    }
    if (half < kSidebarMinWidth) half = kSidebarMinWidth;
    if (half > kSidebarAbsoluteMaxWidth) half = kSidebarAbsoluteMaxWidth;
    return half;
}

- (void)applyWidth:(CGFloat)width {
    CGFloat next = width;
    if (next < kSidebarMinWidth) next = kSidebarMinWidth;
    CGFloat maxW = [self maxAllowedSidebarWidth];
    if (next > maxW) next = maxW;
    self.currentWidth = next;
    self.widthConstraint.constant = next;
    [self.view.window invalidateCursorRectsForView:self.view];
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    if (self.visible == visible && ((visible && self.widthConstraint.constant > 0) || (!visible && self.widthConstraint.constant == 0))) {
        return;
    }
    self.visible = visible;
    if (visible) {
        self.currentWidth = [BrowserScraperSettings sharedSettings].sidebarWidth;
        // 按当前窗口半宽再夹一次，避免保存宽度超过半屏
        [self applyWidth:self.currentWidth];
        self.view.hidden = NO;
        [self reloadForCurrentURL];
        [self syncUIFromDraft];
    }
    CGFloat target = visible ? self.currentWidth : 0;
    void (^finish)(void) = ^{
        if (!visible) {
            self.view.hidden = YES;
            [BrowserScraperElementPicker cancelActivePick];
        } else {
            [self.view.window invalidateCursorRectsForView:self.view];
        }
    };
    if (animated && self.view.superview) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            self.widthConstraint.animator.constant = target;
        } completionHandler:finish];
    } else {
        self.widthConstraint.constant = target;
        finish();
    }
}

- (void)closeClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(scraperSidebarDidRequestClose:)]) {
        [self.delegate scraperSidebarDidRequestClose:self];
    }
}

- (void)segmentChanged:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    NSInteger idx = self.segment.selectedSegment;
    if (idx < 0 || idx >= (NSInteger)self.pageViews.count) return;
    for (NSUInteger i = 0; i < self.pageViews.count; i++) {
        self.pageViews[i].hidden = ((NSInteger)i != idx);
    }
    [self.pagesHost setNeedsLayout:YES];
    [self.pagesHost layoutSubtreeIfNeeded];
}

#pragma mark - Sync

- (void)reloadForCurrentURL {
    [self refreshRecipePopup];
    NSURL *url = nil;
    if ([self.delegate respondsToSelector:@selector(scraperSidebarCurrentURL:)]) {
        url = [self.delegate scraperSidebarCurrentURL:self];
    }
    NSArray *matched = url ? [[BrowserScraperRecipeStore sharedStore] recipesMatchingURL:url] : @[];
    if (matched.count > 0) {
        self.draft = [matched.firstObject copy];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"本页配方 %lu", (unsigned long)matched.count];
    } else if (url.host.length > 0) {
        self.statusLabel.stringValue = url.host;
        if (self.draft.match.hosts.count == 0) {
            self.draft.match.hosts = @[ url.host.lowercaseString ];
        }
        if (self.draft.startURL.length == 0) {
            self.draft.startURL = url.absoluteString;
        }
    } else {
        self.statusLabel.stringValue = @"";
    }
    [self syncUIFromDraft];
}

- (void)refreshRecipePopup {
    [self.recipePopup removeAllItems];
    [self.recipePopup addItemWithTitle:@"（当前草稿）"];
    for (BrowserScraperRecipe *r in [BrowserScraperRecipeStore sharedStore].recipes) {
        [self.recipePopup addItemWithTitle:r.name ?: r.recipeID];
        self.recipePopup.lastItem.representedObject = r.recipeID;
    }
}

- (void)syncUIFromDraft {
    self.nameField.stringValue = self.draft.name ?: @"";
    [self.modePopup selectItemAtIndex:self.draft.mode == BrowserScraperModeScalar ? 1 : 0];
    self.containerField.stringValue = self.draft.containerPath ?: @"";
    self.rowPathField.stringValue = self.draft.rowPath ?: @"";
    [self.paginationPopup selectItemAtIndex:(NSInteger)self.draft.pagination.type];
    self.paginationSelectorField.stringValue = self.draft.pagination.selector ?: @"";
    self.maxPagesField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.pagination.maxPages];
    self.maxRowsField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.pagination.maxRows];
    self.delayField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.pagination.pageDelayMs];
    [self.sessionPopup selectItemAtIndex:self.draft.session == BrowserScraperSessionEphemeral ? 1 : 0];
    self.scheduleCheck.state = self.draft.schedule.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.intervalField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.schedule.intervalMinutes];
    [self.sinkPopup selectItemAtIndex:(NSInteger)self.draft.sink.type];
    self.filePathField.stringValue = self.draft.sink.filePath ?: @"";
    BrowserScraperMySQLConfig *mysql = self.draft.sink.mysql ?: [BrowserScraperMySQLConfig configWithDictionary:@{}];
    self.draft.sink.mysql = mysql;
    self.mysqlHostField.stringValue = mysql.host ?: @"";
    self.mysqlPortField.stringValue = [NSString stringWithFormat:@"%ld", (long)mysql.port];
    self.mysqlDBField.stringValue = mysql.database ?: @"";
    self.mysqlUserField.stringValue = mysql.user ?: @"";
    self.mysqlTableField.stringValue = mysql.table ?: @"";
    self.mysqlPasswordField.stringValue = @"";
    [self.fieldsTable reloadData];
    [self rebuildPreviewColumns];
}

- (void)applyUIToDraft {
    self.draft.name = self.nameField.stringValue;
    self.draft.mode = self.modePopup.indexOfSelectedItem == 1 ? BrowserScraperModeScalar : BrowserScraperModeTable;
    self.draft.containerPath = self.containerField.stringValue;
    self.draft.rowPath = self.rowPathField.stringValue;
    self.draft.pagination.type = (BrowserScraperPaginationType)self.paginationPopup.indexOfSelectedItem;
    self.draft.pagination.selector = self.paginationSelectorField.stringValue;
    self.draft.pagination.maxPages = MAX(1, self.maxPagesField.stringValue.integerValue);
    self.draft.pagination.maxRows = MAX(1, self.maxRowsField.stringValue.integerValue);
    self.draft.pagination.pageDelayMs = MAX(0, self.delayField.stringValue.integerValue);
    self.draft.session = self.sessionPopup.indexOfSelectedItem == 1 ? BrowserScraperSessionEphemeral : BrowserScraperSessionReuseProfile;
    self.draft.schedule.enabled = self.scheduleCheck.state == NSControlStateValueOn;
    self.draft.schedule.intervalMinutes = MAX(1, self.intervalField.stringValue.integerValue);
    self.draft.sink.type = (BrowserScraperSinkType)self.sinkPopup.indexOfSelectedItem;
    self.draft.sink.filePath = self.filePathField.stringValue.length > 0 ? self.filePathField.stringValue : nil;
    if (!self.draft.sink.mysql) {
        self.draft.sink.mysql = [BrowserScraperMySQLConfig configWithDictionary:@{}];
    }
    self.draft.sink.mysql.host = self.mysqlHostField.stringValue;
    self.draft.sink.mysql.port = self.mysqlPortField.stringValue.integerValue ?: 3306;
    self.draft.sink.mysql.database = self.mysqlDBField.stringValue;
    self.draft.sink.mysql.user = self.mysqlUserField.stringValue;
    self.draft.sink.mysql.table = self.mysqlTableField.stringValue;
    if (self.draft.sink.mysql.passwordKeychainAccount.length == 0) {
        self.draft.sink.mysql.passwordKeychainAccount = [NSString stringWithFormat:@"scraper.mysql.%@", self.draft.recipeID];
    }
}

#pragma mark - Actions

- (WKWebView *)currentWebView {
    if ([self.delegate respondsToSelector:@selector(scraperSidebarCurrentWebView:)]) {
        return [self.delegate scraperSidebarCurrentWebView:self];
    }
    return nil;
}

- (void)newRecipeClicked:(id)sender {
    (void)sender;
    self.draft = [BrowserScraperRecipe blankRecipeNamed:@"新配方"];
    NSURL *url = [self.delegate scraperSidebarCurrentURL:self];
    if (url.host.length > 0) {
        self.draft.match.hosts = @[ url.host.lowercaseString ];
        self.draft.startURL = url.absoluteString;
    }
    [self syncUIFromDraft];
    [self appendLog:@"已新建配方草稿"];
}

- (void)recipePopupChanged:(id)sender {
    (void)sender;
    NSString *rid = self.recipePopup.selectedItem.representedObject;
    if (![rid isKindOfClass:[NSString class]]) return;
    BrowserScraperRecipe *r = [[BrowserScraperRecipeStore sharedStore] recipeWithID:rid];
    if (r) {
        self.draft = [r copy];
        [self syncUIFromDraft];
    }
}

- (void)applyAnalysisDictionary:(NSDictionary *)analysis {
    if (![analysis isKindOfClass:[NSDictionary class]]) return;
    NSString *type = [analysis[@"type"] isKindOfClass:[NSString class]] ? analysis[@"type"] : @"cards";
    self.draft.mode = [type isEqualToString:@"scalar"] ? BrowserScraperModeScalar : BrowserScraperModeTable;
    NSString *container = [analysis[@"containerPath"] isKindOfClass:[NSString class]] ? analysis[@"containerPath"] : @"";
    NSString *rowPath = [analysis[@"rowPath"] isKindOfClass:[NSString class]] ? analysis[@"rowPath"] : @"";
    if (container.length > 0) {
        self.draft.containerPath = container;
        self.containerField.stringValue = container;
    }
    self.draft.rowPath = rowPath;
    self.rowPathField.stringValue = rowPath ?: @"";

    NSArray *rawFields = [analysis[@"fields"] isKindOfClass:[NSArray class]] ? analysis[@"fields"] : @[];
    NSMutableArray *fields = [NSMutableArray array];
    for (id item in rawFields) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *sf = (NSDictionary *)item;
        NSMutableDictionary *fd = [NSMutableDictionary dictionary];
        fd[@"id"] = [[NSUUID UUID] UUIDString];
        fd[@"enabled"] = @YES;
        fd[@"name"] = [sf[@"name"] isKindOfClass:[NSString class]] ? sf[@"name"] : @"列";
        fd[@"kind"] = [sf[@"kind"] isKindOfClass:[NSString class]] ? sf[@"kind"] : @"text";
        fd[@"path"] = [sf[@"path"] isKindOfClass:[NSString class]] ? sf[@"path"] : @"";
        if ([sf[@"attribute"] isKindOfClass:[NSString class]] && [sf[@"attribute"] length] > 0) {
            fd[@"attribute"] = sf[@"attribute"];
        }
        [fields addObject:[BrowserScraperField fieldWithDictionary:fd]];
    }
    if (fields.count > 0) {
        self.draft.fields = fields;
    }
    NSString *title = [analysis[@"title"] isKindOfClass:[NSString class]] ? analysis[@"title"] : type;
    NSInteger rows = [analysis[@"estimatedRows"] respondsToSelector:@selector(integerValue)]
        ? [analysis[@"estimatedRows"] integerValue] : 0;
    [self appendLog:[NSString stringWithFormat:@"智能识别：%@ · 循环 %@ · 约 %ld 行 · %lu 字段",
                     title, rowPath.length ? rowPath : @"(无)", (long)rows, (unsigned long)fields.count]];
    [self syncUIFromDraft];
    [self previewClicked:nil];
}

- (void)detectClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self currentWebView];
    [self appendLog:@"正在智能检测表格 / 列表 / 卡片…"];
    [BrowserScraperDetector detectCandidatesInWebView:wv completion:^(NSArray<NSDictionary *> *candidates) {
        self.candidates = candidates;
        [self.candidatesTable reloadData];
        if (candidates.count == 0) {
            [self appendLog:@"未检测到可用候选"];
            return;
        }
        [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self.candidatesTable scrollRowToVisible:0];
        NSDictionary *best = candidates.firstObject;
        NSInteger score = [best[@"score"] respondsToSelector:@selector(integerValue)]
            ? [best[@"score"] integerValue] : 0;
        BOOL confident = [best[@"confident"] boolValue];
        NSString *title = [best[@"title"] isKindOfClass:[NSString class]] ? best[@"title"] : @"候选";
        if (confident) {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，智能采用：%@（分 %ld）",
                             (unsigned long)candidates.count, title, (long)score]];
            [self applyAnalysisDictionary:best];
        } else {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，已选中推荐项（分 %ld），置信不足请确认后点「采用选中候选」",
                             (unsigned long)candidates.count, (long)score]];
        }
    }];
}

- (void)useCandidateClicked:(id)sender {
    (void)sender;
    NSInteger row = self.candidatesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    [self applyAnalysisDictionary:self.candidates[row]];
}

- (void)reanalyzeContainerClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    NSString *path = self.draft.containerPath;
    if (path.length == 0) {
        [self appendLog:@"请先选择或填写容器 path"];
        return;
    }
    WKWebView *wv = [self currentWebView];
    [BrowserScraperDetector analyzeContainerInWebView:wv containerPath:path completion:^(NSDictionary *analysis, NSError *error) {
        if (error || !analysis) {
            [self appendLog:error.localizedDescription ?: @"识别失败"];
            return;
        }
        [self applyAnalysisDictionary:analysis];
    }];
}

- (void)pickContainerClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self currentWebView];
    [self appendLog:@"请在页面上点击数据区或其中某一卡片…"];
    [BrowserScraperElementPicker startPickingInWebView:wv mode:BrowserScraperPickModeContainer completion:^(NSDictionary *result, BOOL cancelled) {
        if (cancelled || !result) return;
        id rawPath = result[@"cssPath"];
        NSString *path = [rawPath isKindOfClass:[NSString class]] ? (NSString *)rawPath : @"";
        if (path.length == 0) return;
        self.draft.containerPath = path;
        self.containerField.stringValue = path;
        [BrowserScraperDetector analyzeContainerInWebView:wv containerPath:path completion:^(NSDictionary *analysis, NSError *error) {
            if (error || !analysis) {
                [self applyPickResult:result mode:BrowserScraperPickModeContainer];
                [self appendLog:error.localizedDescription ?: @"已记录容器，但未能识别循环结构"];
                return;
            }
            [self applyAnalysisDictionary:analysis];
        }];
    }];
}

- (void)pickFieldClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    WKWebView *wv = [self currentWebView];
    NSString *container = self.draft.containerPath ?: @"";
    NSString *rowPath = self.draft.rowPath ?: @"";
    BOOL loop = (self.draft.mode != BrowserScraperModeScalar && rowPath.length > 0);
    [self appendLog:loop
        ? @"请点选卡片内字段（将生成相对循环行的 path）…"
        : @"请点选要添加的字段节点…"];
    [BrowserScraperElementPicker startPickingInWebView:wv
                                                  mode:BrowserScraperPickModeField
                                         containerPath:loop ? container : nil
                                               rowPath:loop ? rowPath : nil
                                            completion:^(NSDictionary *result, BOOL cancelled) {
        if (cancelled || !result) return;
        [self applyPickResult:result mode:BrowserScraperPickModeField];
    }];
}

- (void)pickPaginationClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self currentWebView];
    [BrowserScraperElementPicker startPickingInWebView:wv mode:BrowserScraperPickModePagination completion:^(NSDictionary *result, BOOL cancelled) {
        if (cancelled || !result) return;
        [self applyPickResult:result mode:BrowserScraperPickModePagination];
    }];
}

- (void)handlePickMessageBody:(id)body {
    [BrowserScraperElementPicker handleScriptMessageBody:body];
}

- (void)applyPickResult:(NSDictionary *)result mode:(BrowserScraperPickMode)mode {
    id rawPath = result[@"cssPath"];
    NSString *path = [rawPath isKindOfClass:[NSString class]] ? (NSString *)rawPath : @"";
    if (mode == BrowserScraperPickModePagination) {
        self.paginationSelectorField.stringValue = path;
        self.draft.pagination.selector = path;
        [self appendLog:[NSString stringWithFormat:@"翻页选择器: %@", path]];
        return;
    }
    if (mode == BrowserScraperPickModeField) {
        id rawRel = result[@"relativePath"];
        id rawCss = result[@"cssPath"];
        NSString *path = @"";
        if ([rawRel isKindOfClass:[NSString class]]) {
            path = (NSString *)rawRel;
        } else if ([rawCss isKindOfClass:[NSString class]]) {
            path = (NSString *)rawCss;
        }
        // loopAware 且 relativePath 为 "" 表示取循环行自身（常见：卡片根 <a href>）
        BOOL loopAware = [result[@"loopAware"] boolValue];
        if (!loopAware && [rawCss isKindOfClass:[NSString class]]) {
            path = (NSString *)rawCss;
        }

        NSString *kind = @"text";
        if ([result[@"fieldKind"] isKindOfClass:[NSString class]] && [result[@"fieldKind"] length] > 0) {
            kind = result[@"fieldKind"];
        }
        NSString *attr = @"";
        if ([result[@"attribute"] isKindOfClass:[NSString class]]) {
            attr = result[@"attribute"];
        }
        if ([kind isEqualToString:@"href"] && attr.length == 0) attr = @"href";
        if ([kind isEqualToString:@"src"] && attr.length == 0) attr = @"src";

        NSString *nameHint = [result[@"nameHint"] isKindOfClass:[NSString class]] ? result[@"nameHint"] : @"";
        id sample = result[@"textSample"];
        NSString *sampleText = [sample isKindOfClass:[NSString class]] ? (NSString *)sample : @"";
        NSMutableArray *fields = [self.draft.fields mutableCopy] ?: [NSMutableArray array];
        NSString *name = nameHint.length > 0
            ? nameHint
            : (sampleText.length > 0
                ? [sampleText substringToIndex:MIN((NSUInteger)12, sampleText.length)]
                : [NSString stringWithFormat:@"字段%lu", (unsigned long)fields.count + 1]);

        NSMutableDictionary *fd = [@{
            @"id": [[NSUUID UUID] UUIDString],
            @"enabled": @YES,
            @"name": name,
            @"kind": kind,
            @"path": path ?: @"",
        } mutableCopy];
        if (attr.length > 0) fd[@"attribute"] = attr;
        BrowserScraperField *f = [BrowserScraperField fieldWithDictionary:fd];
        [fields addObject:f];
        self.draft.fields = fields;
        [self.fieldsTable reloadData];
        NSString *pathDesc = (path.length == 0 && loopAware) ? @"(循环行自身)" : (path ?: @"");
        [self appendLog:[NSString stringWithFormat:@"已添加字段 %@ · %@ · %@", name, kind, pathDesc]];
        [self previewClicked:nil];
        return;
    }
    self.draft.containerPath = path;
    self.containerField.stringValue = path;
    id rawRow = result[@"rowPath"];
    if ([rawRow isKindOfClass:[NSString class]]) {
        self.draft.rowPath = (NSString *)rawRow;
        self.rowPathField.stringValue = self.draft.rowPath;
    }
    NSArray *suggested = result[@"suggestedFields"];
    if ([suggested isKindOfClass:[NSArray class]] && suggested.count > 0) {
        NSMutableArray *fields = [NSMutableArray array];
        for (id item in suggested) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *sf = (NSDictionary *)item;
            NSMutableDictionary *fd = [NSMutableDictionary dictionary];
            fd[@"id"] = [[NSUUID UUID] UUIDString];
            fd[@"enabled"] = @YES;
            fd[@"name"] = [sf[@"name"] isKindOfClass:[NSString class]] ? sf[@"name"] : @"列";
            fd[@"kind"] = [sf[@"kind"] isKindOfClass:[NSString class]] ? sf[@"kind"] : @"text";
            fd[@"path"] = [sf[@"path"] isKindOfClass:[NSString class]] ? sf[@"path"] : @"";
            if ([sf[@"attribute"] isKindOfClass:[NSString class]] && [sf[@"attribute"] length] > 0) {
                fd[@"attribute"] = sf[@"attribute"];
            }
            [fields addObject:[BrowserScraperField fieldWithDictionary:fd]];
        }
        self.draft.fields = fields;
    }
    id rawTag = result[@"tagName"];
    NSString *tag = [rawTag isKindOfClass:[NSString class]] ? (NSString *)rawTag : @"";
    self.draft.mode = [tag isEqualToString:@"table"] ? BrowserScraperModeTable : self.draft.mode;
    [self syncUIFromDraft];
    [self previewClicked:nil];
}

- (void)removeFieldClicked:(id)sender {
    (void)sender;
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    NSMutableArray *fields = [self.draft.fields mutableCopy];
    [fields removeObjectAtIndex:row];
    self.draft.fields = fields;
    [self.fieldsTable reloadData];
}

- (void)previewClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    WKWebView *wv = [self currentWebView];
    NSMutableArray *fieldDicts = [NSMutableArray array];
    for (BrowserScraperField *f in self.draft.fields) {
        [fieldDicts addObject:[f dictionaryRepresentation]];
    }
    [BrowserScraperDetector extractRowsInWebView:wv
                                            mode:[BrowserScraperRecipe stringFromMode:self.draft.mode]
                                   containerPath:self.draft.containerPath
                                         rowPath:self.draft.rowPath
                                          fields:fieldDicts
                                   absoluteURLs:self.draft.absoluteURLs
                                         maxRows:20
                                      completion:^(NSArray<NSDictionary *> *rows, NSError *error) {
        if (error) {
            [self appendLog:error.localizedDescription ?: @"预览失败"];
            return;
        }
        self.previewRows = rows;
        [self rebuildPreviewColumns];
        [self appendLog:[NSString stringWithFormat:@"预览 %lu 行", (unsigned long)rows.count]];
    }];
}

- (void)rebuildPreviewColumns {
    while (self.previewTable.tableColumns.count) {
        [self.previewTable removeTableColumn:self.previewTable.tableColumns.firstObject];
    }
    NSMutableArray *cols = [NSMutableArray array];
    for (BrowserScraperField *f in self.draft.fields) {
        if (f.enabled) [cols addObject:f.name ?: f.fieldID];
    }
    if (cols.count == 0 && self.previewRows.count > 0) {
        [cols addObjectsFromArray:self.previewRows.firstObject.allKeys];
    }
    for (NSString *name in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:name];
        col.title = name;
        col.width = 100;
        [self.previewTable addTableColumn:col];
    }
    [self.previewTable reloadData];
}

- (void)copyPreviewClicked:(id)sender {
    (void)sender;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.previewRows ?: @[] options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    [self appendLog:@"预览已复制"];
}

- (void)saveRecipeClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    if (self.mysqlPasswordField.stringValue.length > 0) {
        NSError *err = nil;
        [BrowserScraperMySQLWriter setPassword:self.mysqlPasswordField.stringValue
                                    forAccount:self.draft.sink.mysql.passwordKeychainAccount
                                         error:&err];
        if (err) [self appendLog:err.localizedDescription];
    }
    NSError *error = nil;
    if (![[BrowserScraperRecipeStore sharedStore] saveRecipe:self.draft error:&error]) {
        [self appendLog:error.localizedDescription ?: @"保存失败"];
        return;
    }
    NSError *schedErr = nil;
    [[BrowserScraperScheduleManager sharedManager] applyScheduleForRecipe:self.draft error:&schedErr];
    if (schedErr) [self appendLog:schedErr.localizedDescription];
    [self refreshRecipePopup];
    [self appendLog:@"配方已保存"];
}

- (void)runClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    WKWebView *wv = [self currentWebView];
    if (!wv) {
        [self appendLog:@"无当前页面"];
        return;
    }
    if (self.draft.fields.count == 0) {
        [self appendLog:@"请先配置字段"];
        return;
    }
    self.logView.string = @"";
    [self.engine startWithRecipe:self.draft webView:wv];
}

- (void)pauseClicked:(id)sender {
    (void)sender;
    if (self.engine.paused) [self.engine resume];
    else [self.engine pause];
}

- (void)stopClicked:(id)sender {
    (void)sender;
    [self.engine cancel];
}

- (void)testMySQLClicked:(id)sender {
    (void)sender;
    [self applyUIToDraft];
    if (![BrowserScraperMySQLWriter isAvailable]) {
        [self appendLog:@"未找到 mysql 命令行客户端"];
        return;
    }
    NSString *password = self.mysqlPasswordField.stringValue;
    if (password.length == 0) {
        password = [BrowserScraperMySQLWriter passwordForAccount:self.draft.sink.mysql.passwordKeychainAccount] ?: @"";
    }
    NSError *error = nil;
    BOOL ok = [BrowserScraperMySQLWriter testConnection:self.draft.sink.mysql password:password error:&error];
    [self appendLog:ok ? @"MySQL 连接成功" : (error.localizedDescription ?: @"连接失败")];
}

- (void)appendLog:(NSString *)line {
    NSString *existing = self.logView.string ?: @"";
    self.logView.string = [[existing stringByAppendingString:line ?: @""] stringByAppendingString:@"\n"];
    self.runStatusLabel.stringValue = line ?: @"";
}

#pragma mark - Engine delegate

- (void)scraperEngine:(BrowserScraperEngine *)engine didAppendRows:(NSArray<NSDictionary *> *)rows totalRows:(NSInteger)totalRows page:(NSInteger)page {
    (void)engine; (void)rows; (void)page;
    if (engine.previewRows.count > 0) {
        self.previewRows = engine.previewRows;
        [self rebuildPreviewColumns];
    }
    self.runStatusLabel.stringValue = [NSString stringWithFormat:@"已采集 %ld 行", (long)totalRows];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line {
    (void)engine;
    [self appendLog:line];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didFinishWithRunDirectory:(NSString *)runDirectory error:(NSError *)error {
    (void)engine;
    if (error) {
        [self appendLog:error.localizedDescription];
    } else {
        [self appendLog:[NSString stringWithFormat:@"完成 %@", runDirectory.lastPathComponent]];
        NSString *path = self.draft.sink.filePath;
        if (path.length > 0) {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
        }
    }
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.candidatesTable) return (NSInteger)self.candidates.count;
    if (tableView == self.fieldsTable) return (NSInteger)self.draft.fields.count;
    if (tableView == self.previewTable) return (NSInteger)MIN(20, self.previewRows.count);
    return 0;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *ident = tableColumn.identifier;
    if (tableView == self.candidatesTable) {
        NSDictionary *c = self.candidates[row];
        if ([ident isEqualToString:@"type"]) {
            NSString *t = [c[@"type"] isKindOfClass:[NSString class]] ? c[@"type"] : @"";
            if ([t isEqualToString:@"table"]) return @"表格";
            if ([t isEqualToString:@"list"]) return @"列表";
            if ([t isEqualToString:@"cards"]) return @"卡片";
            return t.length ? t : @"—";
        }
        if ([ident isEqualToString:@"title"]) {
            NSString *title = [c[@"title"] isKindOfClass:[NSString class]] ? c[@"title"] : @"";
            NSString *sample = [c[@"sampleText"] isKindOfClass:[NSString class]] ? c[@"sampleText"] : @"";
            if (title.length && sample.length) {
                return [NSString stringWithFormat:@"%@ · %@", title, sample];
            }
            return title.length ? title : sample;
        }
        if ([ident isEqualToString:@"score"]) return c[@"score"] ?: @0;
        if ([ident isEqualToString:@"rows"]) return c[@"estimatedRows"];
        return @"";
    }
    if (tableView == self.fieldsTable) {
        BrowserScraperField *f = self.draft.fields[row];
        if ([ident isEqualToString:@"enabled"]) return @(f.enabled);
        if ([ident isEqualToString:@"name"]) return f.name;
        if ([ident isEqualToString:@"kind"]) return [BrowserScraperField stringFromKind:f.kind];
        if ([ident isEqualToString:@"path"]) return f.path;
        return @"";
    }
    if (tableView == self.previewTable) {
        NSDictionary *r = self.previewRows[row];
        return r[ident] ?: @"";
    }
    return @"";
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(nullable id)object forTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.fieldsTable) return;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    BrowserScraperField *f = self.draft.fields[row];
    NSString *ident = tableColumn.identifier;
    if ([ident isEqualToString:@"enabled"]) f.enabled = [object boolValue];
    else if ([ident isEqualToString:@"name"]) f.name = [object description] ?: @"";
    else if ([ident isEqualToString:@"kind"]) f.kind = [BrowserScraperField kindFromString:[object description]];
    else if ([ident isEqualToString:@"path"]) f.path = [object description] ?: @"";
}

@end
