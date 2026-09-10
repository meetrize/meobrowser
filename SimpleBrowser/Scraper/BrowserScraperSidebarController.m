#import "BrowserScraperSidebarController.h"
#import "BrowserScraperSettings.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserScraperDetector.h"
#import "BrowserScraperValueTransform.h"
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

/// 预览表头：右侧显示删除叉；单击叉删除列，双击列头选中上方字段。
@interface BrowserScraperPreviewHeaderView : NSTableHeaderView
@property (nonatomic, copy, nullable) void (^doubleClickColumnHandler)(NSInteger columnIndex);
@property (nonatomic, copy, nullable) void (^deleteColumnHandler)(NSInteger columnIndex);
@end
@implementation BrowserScraperPreviewHeaderView

- (NSRect)closeRectForColumn:(NSInteger)column {
    if (column < 0) return NSZeroRect;
    NSRect header = [self headerRectOfColumn:column];
    CGFloat size = 12.0;
    CGFloat pad = 4.0;
    return NSMakeRect(NSMaxX(header) - size - pad,
                      NSMidY(header) - size * 0.5,
                      size,
                      size);
}

- (NSInteger)closeColumnAtPoint:(NSPoint)point {
    NSInteger col = [self columnAtPoint:point];
    if (col < 0) return -1;
    if (NSPointInRect(point, [self closeRectForColumn:col])) return col;
    return -1;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSInteger count = (NSInteger)self.tableView.tableColumns.count;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
    for (NSInteger i = 0; i < count; i++) {
        NSRect close = [self closeRectForColumn:i];
        if (!NSIntersectsRect(close, dirtyRect)) continue;
        NSString *mark = @"×";
        NSSize sz = [mark sizeWithAttributes:attrs];
        NSPoint p = NSMakePoint(NSMidX(close) - sz.width * 0.5,
                                NSMidY(close) - sz.height * 0.5);
        [mark drawAtPoint:p withAttributes:attrs];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger closeCol = [self closeColumnAtPoint:loc];
    if (closeCol >= 0 && self.deleteColumnHandler) {
        self.deleteColumnHandler(closeCol);
        return;
    }
    if (event.clickCount >= 2) {
        NSInteger col = [self columnAtPoint:loc];
        if (col >= 0 && self.doubleClickColumnHandler) {
            self.doubleClickColumnHandler(col);
            return;
        }
    }
    [super mouseDown:event];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    NSInteger count = (NSInteger)self.tableView.tableColumns.count;
    for (NSInteger i = 0; i < count; i++) {
        [self addCursorRect:[self closeRectForColumn:i] cursor:[NSCursor pointingHandCursor]];
    }
}

@end

@interface BrowserScraperSidebarController () <BrowserScraperEngineDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong) NSView *rootView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, strong) BrowserScraperRecipe *draft;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, copy) NSArray<NSDictionary *> *candidates;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewRawRows;
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
@property (nonatomic, strong) NSWindow *transformHelpWindow;
@end

@implementation BrowserScraperSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [BrowserScraperSettings sharedSettings].sidebarWidth;
        _candidates = @[];
        _previewRows = @[];
        _previewRawRows = @[];
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
    self.logView.selectable = YES;
    self.logView.delegate = self;
    self.logView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.logView.linkTextAttributes = @{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSCursorAttributeName: [NSCursor pointingHandCursor],
    };
    logScroll.documentView = self.logView;
    [logScroll.heightAnchor constraintEqualToConstant:72].active = YES;

    NSButton *trialBtn = [NSButton buttonWithTitle:@"试运行" target:self action:@selector(trialRunClicked:)];
    NSButton *runBtn = [NSButton buttonWithTitle:@"立即运行" target:self action:@selector(runClicked:)];
    NSButton *pauseBtn = [NSButton buttonWithTitle:@"暂停" target:self action:@selector(pauseClicked:)];
    NSButton *stopBtn = [NSButton buttonWithTitle:@"停止" target:self action:@selector(stopClicked:)];
    NSButton *saveBtn = [NSButton buttonWithTitle:@"保存配方" target:self action:@selector(saveRecipeClicked:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[trialBtn, runBtn, pauseBtn, stopBtn, saveBtn]];
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
    NSTableColumn *cApply = [[NSTableColumn alloc] initWithIdentifier:@"apply"];
    cApply.title = @" ";
    cApply.width = 28;
    cApply.minWidth = 24;
    cApply.maxWidth = 36;
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
    [self.candidatesTable addTableColumn:cApply];
    [self.candidatesTable addTableColumn:c0];
    [self.candidatesTable addTableColumn:c1];
    [self.candidatesTable addTableColumn:cScore];
    [self.candidatesTable addTableColumn:c2];
    self.candidatesTable.target = self;
    self.candidatesTable.doubleAction = @selector(candidatesTableDoubleClicked:);
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
    for (NSArray *pair in @[ @[@"index", @"#"], @[@"enabled", @"开"], @[@"name", @"列名"], @[@"kind", @"类型"], @[@"path", @"path"], @[@"transforms", @"处理"] ]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:pair[0]];
        col.title = pair[1];
        if ([pair[0] isEqualToString:@"index"]) {
            col.width = 28;
            col.minWidth = 24;
            col.maxWidth = 36;
        } else if ([pair[0] isEqualToString:@"enabled"]) col.width = 28;
        else if ([pair[0] isEqualToString:@"transforms"]) col.width = 72;
        else col.width = 90;
        [self.fieldsTable addTableColumn:col];
    }
    NSScrollView *fieldsScroll = [self boxedTableScroll:self.fieldsTable height:140];

    NSButton *addField = [NSButton buttonWithTitle:@"点选添加字段" target:self action:@selector(pickFieldClicked:)];
    NSButton *removeField = [NSButton buttonWithTitle:@"删除选中" target:self action:@selector(removeFieldClicked:)];
    NSButton *moveUp = [NSButton buttonWithTitle:@"上移" target:self action:@selector(moveFieldUpClicked:)];
    NSButton *moveDown = [NSButton buttonWithTitle:@"下移" target:self action:@selector(moveFieldDownClicked:)];
    NSButton *editTransform = [NSButton buttonWithTitle:@"编辑处理" target:self action:@selector(editTransformClicked:)];
    NSButton *preview = [NSButton buttonWithTitle:@"刷新预览" target:self action:@selector(previewClicked:)];
    NSButton *copyPreview = [NSButton buttonWithTitle:@"复制预览" target:self action:@selector(copyPreviewClicked:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[addField, removeField, moveUp, moveDown, editTransform, preview, copyPreview]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.spacing = 6;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [actions setHuggingPriority:NSLayoutPriorityDefaultHigh
                 forOrientation:NSLayoutConstraintOrientationVertical];

    NSTextField *previewLabel = [self makeLabel:@"预览"];

    self.previewTable = [self makeTable];
    {
        BrowserScraperPreviewHeaderView *header = [[BrowserScraperPreviewHeaderView alloc] init];
        __weak typeof(self) weakSelf = self;
        header.doubleClickColumnHandler = ^(NSInteger columnIndex) {
            [weakSelf selectFieldForPreviewColumn:columnIndex];
        };
        header.deleteColumnHandler = ^(NSInteger columnIndex) {
            [weakSelf deleteFieldForPreviewColumn:columnIndex];
        };
        self.previewTable.headerView = header;
    }
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
    [self detectAndApplyPaginationNearPath:container];
    [self previewClicked:nil];
}

- (void)detectAndApplyPaginationNearPath:(NSString *)containerPath {
    WKWebView *wv = [self currentWebView];
    [BrowserScraperDetector detectPaginationInWebView:wv
                                     nearContainerPath:containerPath
                                            completion:^(NSDictionary *pagination) {
        [self applyPaginationDetection:pagination];
    }];
}

- (void)applyPaginationDetection:(NSDictionary *)pagination {
    if (![pagination isKindOfClass:[NSDictionary class]]) return;
    NSString *typeStr = [pagination[@"type"] isKindOfClass:[NSString class]] ? pagination[@"type"] : @"none";
    BrowserScraperPaginationType type = [BrowserScraperPagination typeFromString:typeStr];
    NSString *selector = [pagination[@"selector"] isKindOfClass:[NSString class]] ? pagination[@"selector"] : @"";
    NSString *reason = [pagination[@"reason"] isKindOfClass:[NSString class]] ? pagination[@"reason"] : @"";
    NSInteger score = [pagination[@"score"] respondsToSelector:@selector(integerValue)]
        ? [pagination[@"score"] integerValue] : 0;

    self.draft.pagination.type = type;
    self.draft.pagination.selector = selector ?: @"";
    if (pagination[@"pageDelayMs"]) {
        self.draft.pagination.pageDelayMs = MAX(0, [pagination[@"pageDelayMs"] integerValue]);
    }
    if (pagination[@"scrollStepPx"]) {
        self.draft.pagination.scrollStepPx = MAX(1, [pagination[@"scrollStepPx"] integerValue]);
    }
    if (pagination[@"scrollSettleMs"]) {
        self.draft.pagination.scrollSettleMs = MAX(0, [pagination[@"scrollSettleMs"] integerValue]);
    }
    if (pagination[@"maxPages"]) {
        self.draft.pagination.maxPages = MAX(1, [pagination[@"maxPages"] integerValue]);
    }

    // 刷新翻页页 UI（不整表 sync，避免冲掉用户正在编辑的其它字段）
    if (self.paginationPopup) {
        [self.paginationPopup selectItemAtIndex:(NSInteger)type];
    }
    if (self.paginationSelectorField) {
        self.paginationSelectorField.stringValue = self.draft.pagination.selector ?: @"";
    }
    if (self.maxPagesField) {
        self.maxPagesField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.pagination.maxPages];
    }
    if (self.delayField) {
        self.delayField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.draft.pagination.pageDelayMs];
    }

    NSString *typeLabel = @"无";
    switch (type) {
        case BrowserScraperPaginationTypeNextButton: typeLabel = @"下一页按钮"; break;
        case BrowserScraperPaginationTypePageNumbers: typeLabel = @"页码"; break;
        case BrowserScraperPaginationTypeLoadMore: typeLabel = @"Load More"; break;
        case BrowserScraperPaginationTypeInfiniteScroll: typeLabel = @"无限滚动"; break;
        default: typeLabel = @"无"; break;
    }
    if (type == BrowserScraperPaginationTypeNone) {
        [self appendLog:[NSString stringWithFormat:@"翻页检测：未发现可用翻页（%@）", reason.length ? reason : @"none"]];
    } else if (selector.length > 0) {
        [self appendLog:[NSString stringWithFormat:@"翻页检测：%@ · %@（分 %ld）· %@",
                         typeLabel, reason, (long)score, selector]];
    } else {
        [self appendLog:[NSString stringWithFormat:@"翻页检测：%@ · %@（分 %ld）",
                         typeLabel, reason, (long)score]];
    }
}

- (void)detectClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self currentWebView];
    [self appendLog:@"正在智能检测表格 / 列表 / 卡片与翻页方式…"];
    [BrowserScraperDetector detectCandidatesInWebView:wv completion:^(NSArray<NSDictionary *> *candidates) {
        self.candidates = candidates;
        [self.candidatesTable reloadData];
        if (candidates.count == 0) {
            [self appendLog:@"未检测到可用候选，仍尝试识别整页翻页…"];
            [self detectAndApplyPaginationNearPath:@""];
            return;
        }
        [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self.candidatesTable scrollRowToVisible:0];
        NSDictionary *best = candidates.firstObject;
        NSInteger score = [best[@"score"] respondsToSelector:@selector(integerValue)]
            ? [best[@"score"] integerValue] : 0;
        BOOL confident = [best[@"confident"] boolValue];
        NSString *title = [best[@"title"] isKindOfClass:[NSString class]] ? best[@"title"] : @"候选";
        NSString *near = [best[@"containerPath"] isKindOfClass:[NSString class]] ? best[@"containerPath"] : @"";
        if (confident) {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，智能采用：%@（分 %ld）",
                             (unsigned long)candidates.count, title, (long)score]];
            [self applyAnalysisDictionary:best];
        } else {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，已选中推荐项（分 %ld），置信不足请确认后点「采用选中候选」",
                             (unsigned long)candidates.count, (long)score]];
            [self detectAndApplyPaginationNearPath:near];
        }
    }];
}

- (void)useCandidateClicked:(id)sender {
    (void)sender;
    NSInteger row = self.candidatesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    [self applyAnalysisDictionary:self.candidates[row]];
}

- (void)candidatesTableDoubleClicked:(id)sender {
    (void)sender;
    NSInteger row = self.candidatesTable.clickedRow;
    NSInteger col = self.candidatesTable.clickedColumn;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    if (col < 0 || col >= (NSInteger)self.candidatesTable.tableColumns.count) return;
    NSTableColumn *column = self.candidatesTable.tableColumns[col];
    if (![column.identifier isEqualToString:@"apply"]) return;
    [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self useCandidateClicked:nil];
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
    [self removeFieldAtIndex:self.fieldsTable.selectedRow];
}

- (void)removeFieldAtIndex:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    BrowserScraperField *removed = self.draft.fields[row];
    NSString *colKey = removed.name.length ? removed.name : (removed.fieldID ?: @"");

    NSMutableArray *fields = [self.draft.fields mutableCopy];
    [fields removeObjectAtIndex:row];
    self.draft.fields = fields;
    [self.fieldsTable reloadData];
    if (row < (NSInteger)self.draft.fields.count) {
        [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    } else if (self.draft.fields.count > 0) {
        [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:self.draft.fields.count - 1] byExtendingSelection:NO];
    } else {
        [self.fieldsTable deselectAll:nil];
    }

    // 只摘掉对应预览列，避免整表重建导致表头/内容错位与滚动跳动
    [self removePreviewColumnNamed:colKey];
    if (self.previewRawRows.count > 0) {
        BrowserScraperTransformContext *txCtx = [BrowserScraperTransformContext defaultContext];
        WKWebView *wv = [self currentWebView];
        if (wv.URL.absoluteString.length > 0) txCtx.baseURL = wv.URL.absoluteString;
        self.previewRows = [BrowserScraperValueTransform normalizeRows:self.previewRawRows
                                                                fields:self.draft.fields
                                                               context:txCtx];
        [self.previewTable reloadData];
        [self.previewTable tile];
        [self syncPreviewHeaderScrollWithContent];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self syncPreviewHeaderScrollWithContent];
        });
    }
}

- (void)syncPreviewHeaderScrollWithContent {
    NSScrollView *scroll = self.previewTable.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip) return;
    CGFloat x = clip.bounds.origin.x;
    NSView *headerSuper = self.previewTable.headerView.superview;
    if (![headerSuper isKindOfClass:[NSClipView class]]) return;
    NSClipView *headerClip = (NSClipView *)headerSuper;
    NSPoint hp = headerClip.bounds.origin;
    if (fabs(hp.x - x) < 0.5) return;
    hp.x = x;
    hp.y = 0;
    [headerClip setBoundsOrigin:hp];
    [headerClip setNeedsDisplay:YES];
    [self.previewTable.headerView setNeedsDisplay:YES];
}

- (void)removePreviewColumnNamed:(NSString *)name {
    if (name.length == 0) return;
    NSTableColumn *match = nil;
    for (NSTableColumn *col in self.previewTable.tableColumns) {
        if ([col.identifier isEqualToString:name]) {
            match = col;
            break;
        }
    }
    if (!match) return;

    NSScrollView *scroll = self.previewTable.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    CGFloat savedX = clip ? clip.bounds.origin.x : 0;
    CGFloat savedY = clip ? clip.bounds.origin.y : 0;

    [self.previewTable removeTableColumn:match];
    [self.previewTable tile];
    [scroll layoutSubtreeIfNeeded];

    if (clip) {
        NSRect doc = [scroll.documentView frame];
        NSSize visible = clip.bounds.size;
        CGFloat maxX = MAX(0, NSWidth(doc) - visible.width);
        CGFloat maxY = MAX(0, NSHeight(doc) - visible.height);
        CGFloat x = MIN(MAX(0, savedX), maxX);
        CGFloat y = MIN(MAX(0, savedY), maxY);
        [clip scrollToPoint:NSMakePoint(x, y)];
        [scroll reflectScrolledClipView:clip];
        [self syncPreviewHeaderScrollWithContent];
    }

    NSTableHeaderView *header = self.previewTable.headerView;
    if (header.window) {
        [header.window invalidateCursorRectsForView:header];
    }
    [header setNeedsDisplay:YES];
    // 下一帧再对齐一次，避免 tile/reload 异步布局后又偏一点
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncPreviewHeaderScrollWithContent];
    });
}

- (void)moveFieldUpClicked:(id)sender {
    (void)sender;
    [self moveSelectedFieldByOffset:-1];
}

- (void)moveFieldDownClicked:(id)sender {
    (void)sender;
    [self moveSelectedFieldByOffset:1];
}

- (void)moveSelectedFieldByOffset:(NSInteger)offset {
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) {
        [self appendLog:@"请先选中要调整顺序的字段"];
        return;
    }
    NSInteger target = row + offset;
    if (target < 0 || target >= (NSInteger)self.draft.fields.count) return;
    NSMutableArray *fields = [self.draft.fields mutableCopy];
    [fields exchangeObjectAtIndex:row withObjectAtIndex:target];
    self.draft.fields = fields;
    [self.fieldsTable reloadData];
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:target] byExtendingSelection:NO];
    [self.fieldsTable scrollRowToVisible:target];
    [self refreshPreviewAfterFieldOrderChange];
}

- (void)refreshPreviewAfterFieldOrderChange {
    if (self.previewRawRows.count > 0) {
        BrowserScraperTransformContext *txCtx = [BrowserScraperTransformContext defaultContext];
        WKWebView *wv = [self currentWebView];
        if (wv.URL.absoluteString.length > 0) txCtx.baseURL = wv.URL.absoluteString;
        self.previewRows = [BrowserScraperValueTransform normalizeRows:self.previewRawRows
                                                                fields:self.draft.fields
                                                               context:txCtx];
    }
    [self rebuildPreviewColumns];
}

- (void)editTransformClicked:(id)sender {
    (void)sender;
    NSInteger row = self.fieldsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) {
        [self appendLog:@"请先选中要编辑处理步骤的字段"];
        return;
    }
    BrowserScraperField *field = self.draft.fields[row];
    NSString *sample = @"";
    NSDictionary *rawRow = self.previewRawRows.firstObject;
    if ([rawRow isKindOfClass:[NSDictionary class]]) {
        id v = rawRow[field.name];
        if ([v isKindOfClass:[NSString class]]) sample = (NSString *)v;
        else if ([v isKindOfClass:[NSNumber class]]) sample = [(NSNumber *)v stringValue];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"字段处理 · %@", field.name ?: @"未命名"];
    alert.informativeText = @"选择预设，或直接编辑下方 JSON 步骤数组。\n常用：digits / number / regex / relTime / remove / trim";
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"清除处理"];
    [alert addButtonWithTitle:@"取消"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 236)];
    NSPopUpButton *preset = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 206, 300, 24) pullsDown:NO];
    [preset addItemWithTitle:@"（可选）套用预设到下方"];
    NSDictionary *presets = [BrowserScraperValueTransform presetTemplates];
    NSArray *keys = [[presets allKeys] sortedArrayUsingSelector:@selector(localizedCompare:)];
    for (NSString *k in keys) {
        [preset addItemWithTitle:k];
    }
    NSButton *helpBtn = [NSButton buttonWithTitle:@"函数说明…" target:self action:@selector(showTransformHelpClicked:)];
    helpBtn.bezelStyle = NSBezelStyleRounded;
    helpBtn.frame = NSMakeRect(308, 204, 112, 28);

    NSTextField *sampleLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"样例原文：%@", sample.length ? sample : @"(刷新预览后可带入)"]];
    sampleLabel.frame = NSMakeRect(0, 178, 420, 20);
    sampleLabel.font = [NSFont systemFontOfSize:11];
    sampleLabel.textColor = NSColor.secondaryLabelColor;
    sampleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSTextField *hint = [NSTextField labelWithString:@"点击「函数说明…」查看全部 op 的参数与示例"];
    hint.frame = NSMakeRect(0, 158, 420, 16);
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = NSColor.tertiaryLabelColor;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 150)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    SBTextView *tv = [SBTextView standardTextView];
    tv.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    if (field.transforms.count > 0) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:field.transforms
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
        tv.string = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
    } else {
        tv.string = @"[]";
    }
    scroll.documentView = tv;
    [accessory addSubview:preset];
    [accessory addSubview:helpBtn];
    [accessory addSubview:sampleLabel];
    [accessory addSubview:hint];
    [accessory addSubview:scroll];
    alert.accessoryView = accessory;

    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertThirdButtonReturn) return;
    if (resp == NSAlertSecondButtonReturn) {
        field.transforms = @[];
        [self.fieldsTable reloadData];
        [self appendLog:[NSString stringWithFormat:@"已清除字段「%@」的处理步骤", field.name]];
        [self previewClicked:nil];
        return;
    }

    NSArray *clean = nil;
    NSInteger presetIdx = preset.indexOfSelectedItem;
    if (presetIdx > 0) {
        NSString *title = preset.titleOfSelectedItem;
        NSArray *steps = presets[title];
        if ([steps isKindOfClass:[NSArray class]]) clean = steps;
    }
    if (!clean) {
        NSString *json = tv.string ?: @"[]";
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![obj isKindOfClass:[NSArray class]]) {
            [self appendLog:@"处理步骤 JSON 无效，需为数组"];
            return;
        }
        NSMutableArray *arr = [NSMutableArray array];
        for (id step in (NSArray *)obj) {
            if ([step isKindOfClass:[NSDictionary class]] && [step[@"op"] isKindOfClass:[NSString class]]) {
                [arr addObject:step];
            }
        }
        clean = arr;
    }
    field.transforms = clean ?: @[];
    [self.fieldsTable reloadData];
    NSString *out = [BrowserScraperValueTransform applyTransforms:field.transforms
                                                         rawValue:sample
                                                              row:@{}
                                                          context:nil];
    [self appendLog:[NSString stringWithFormat:@"字段「%@」处理试跑：%@ → %@（%@）",
                     field.name,
                     sample.length ? sample : @"(空)",
                     out,
                     [BrowserScraperValueTransform summaryForTransforms:field.transforms] ?: @"无"]];
    [self previewClicked:nil];
}

- (void)showTransformHelpClicked:(id)sender {
    (void)sender;
    if (self.transformHelpWindow && self.transformHelpWindow.isVisible) {
        [self.transformHelpWindow makeKeyAndOrderFront:nil];
        return;
    }

    NSRect rect = NSMakeRect(0, 0, 560, 520);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:rect
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskResizable |
                                                           NSWindowStyleMaskMiniaturizable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"字段处理 · 函数说明";
    win.minSize = NSMakeSize(420, 320);
    win.releasedWhenClosed = NO;

    NSView *content = win.contentView;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSNoBorder;
    scroll.autohidesScrollers = YES;

    SBTextView *tv = [SBTextView standardTextView];
    tv.editable = NO;
    tv.drawsBackground = YES;
    tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    tv.string = [BrowserScraperValueTransform helpDocumentText];
    scroll.documentView = tv;

    NSButton *close = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeTransformHelpClicked:)];
    close.bezelStyle = NSBezelStyleRounded;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.keyEquivalent = @"\r";

    [content addSubview:scroll];
    [content addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [scroll.bottomAnchor constraintEqualToAnchor:close.topAnchor constant:-10],
        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [close.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
    ]];

    self.transformHelpWindow = win;
    [win center];
    [win makeKeyAndOrderFront:nil];
    // 把光标滚到开头
    [tv scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)closeTransformHelpClicked:(id)sender {
    (void)sender;
    [self.transformHelpWindow close];
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
        BrowserScraperTransformContext *txCtx = [BrowserScraperTransformContext defaultContext];
        if (wv.URL.absoluteString.length > 0) txCtx.baseURL = wv.URL.absoluteString;
        self.previewRawRows = rows;
        self.previewRows = [BrowserScraperValueTransform normalizeRows:rows
                                                                fields:self.draft.fields
                                                               context:txCtx];
        [self rebuildPreviewColumns];
        [self appendLog:[NSString stringWithFormat:@"预览 %lu 行", (unsigned long)rows.count]];
    }];
}

- (void)rebuildPreviewColumns {
    NSScrollView *scroll = self.previewTable.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    CGFloat savedX = clip ? clip.bounds.origin.x : 0;
    CGFloat savedY = clip ? clip.bounds.origin.y : 0;

    while (self.previewTable.tableColumns.count) {
        [self.previewTable removeTableColumn:self.previewTable.tableColumns.firstObject];
    }
    NSArray<NSString *> *cols = [BrowserScraperField orderedColumnNamesFromFields:self.draft.fields];
    if (cols.count == 0 && self.previewRows.count > 0) {
        // 无启用字段时：按首行 key 排序兜底，避免 allKeys 乱序
        NSDictionary *first = self.previewRows.firstObject;
        if ([first isKindOfClass:[NSDictionary class]]) {
            cols = [[first.allKeys filteredArrayUsingPredicate:
                     [NSPredicate predicateWithBlock:^BOOL(id key, NSDictionary *bindings) {
                (void)bindings;
                return [key isKindOfClass:[NSString class]];
            }]] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        }
    }
    for (NSString *name in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:name];
        col.title = name;
        col.width = 100;
        [self.previewTable addTableColumn:col];
    }
    [self.previewTable reloadData];
    [self.previewTable tile];
    [scroll layoutSubtreeIfNeeded];

    void (^restoreScroll)(void) = ^{
        if (!clip || !scroll) return;
        NSRect doc = [scroll.documentView frame];
        NSSize visible = clip.bounds.size;
        CGFloat maxX = MAX(0, NSWidth(doc) - visible.width);
        CGFloat maxY = MAX(0, NSHeight(doc) - visible.height);
        CGFloat x = MIN(MAX(0, savedX), maxX);
        CGFloat y = MIN(MAX(0, savedY), maxY);
        [clip scrollToPoint:NSMakePoint(x, y)];
        [scroll reflectScrolledClipView:clip];
        [self syncPreviewHeaderScrollWithContent];
    };
    restoreScroll();
    dispatch_async(dispatch_get_main_queue(), restoreScroll);

    if (self.previewTable.headerView.window) {
        [self.previewTable.headerView.window invalidateCursorRectsForView:self.previewTable.headerView];
    }
}

- (void)selectFieldForPreviewColumn:(NSInteger)columnIndex {
    NSInteger fieldRow = [self fieldIndexForPreviewColumn:columnIndex];
    if (fieldRow < 0) {
        if (columnIndex >= 0 && columnIndex < (NSInteger)self.previewTable.tableColumns.count) {
            NSString *name = self.previewTable.tableColumns[columnIndex].identifier ?: @"";
            [self appendLog:[NSString stringWithFormat:@"预览列「%@」未匹配到字段列表", name]];
        }
        return;
    }
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:fieldRow] byExtendingSelection:NO];
    [self.fieldsTable scrollRowToVisible:fieldRow];
    [[self.fieldsTable window] makeFirstResponder:self.fieldsTable];
}

- (void)deleteFieldForPreviewColumn:(NSInteger)columnIndex {
    NSInteger fieldRow = [self fieldIndexForPreviewColumn:columnIndex];
    if (fieldRow < 0) {
        if (columnIndex >= 0 && columnIndex < (NSInteger)self.previewTable.tableColumns.count) {
            NSString *name = self.previewTable.tableColumns[columnIndex].identifier ?: @"";
            [self appendLog:[NSString stringWithFormat:@"预览列「%@」未匹配到字段列表，无法删除", name]];
        }
        return;
    }
    [self removeFieldAtIndex:fieldRow];
}

- (NSInteger)fieldIndexForPreviewColumn:(NSInteger)columnIndex {
    if (columnIndex < 0 || columnIndex >= (NSInteger)self.previewTable.tableColumns.count) return -1;
    NSString *name = self.previewTable.tableColumns[columnIndex].identifier ?: @"";
    if (name.length == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)self.draft.fields.count; i++) {
        BrowserScraperField *f = self.draft.fields[i];
        NSString *key = f.name.length ? f.name : (f.fieldID ?: @"");
        if ([key isEqualToString:name]) return i;
    }
    return -1;
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

- (void)trialRunClicked:(id)sender {
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
    if (self.engine.running) {
        [self appendLog:@"已有任务在运行，请先停止"];
        return;
    }
    // 切到「字段」页以便看到预览追加
    if (self.segment.segmentCount > 1) {
        self.segment.selectedSegment = 1;
        [self segmentChanged:self.segment];
    }
    [self appendLog:@"试运行：按当前翻页设置，最多 10 页，结果追加到预览"];
    [self.engine startTrialWithRecipe:self.draft webView:wv];
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
    NSString *text = line ?: @"";
    self.runStatusLabel.stringValue = text;

    NSFont *font = self.logView.font ?: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    NSColor *fg = [NSColor labelColor];
    NSDictionary *plainAttrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fg,
    };

    NSMutableAttributedString *chunk = [[NSMutableAttributedString alloc] init];
    static NSString *const kExportPrefix = @"已导出 ";
    if ([text hasPrefix:kExportPrefix]) {
        NSString *path = [text substringFromIndex:kExportPrefix.length];
        [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:kExportPrefix attributes:plainAttrs]];
        if (path.length > 0) {
            NSURL *fileURL = [NSURL fileURLWithPath:path isDirectory:NO];
            NSDictionary *linkAttrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [NSColor linkColor],
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                NSLinkAttributeName: fileURL,
                NSToolTipAttributeName: @"用默认应用打开",
            };
            [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:path attributes:linkAttrs]];
        }
    } else {
        [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:plainAttrs]];
    }
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:plainAttrs]];

    NSTextStorage *storage = self.logView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:chunk];
    [storage endEditing];
    NSRange end = NSMakeRange(storage.length, 0);
    [self.logView scrollRangeToVisible:end];
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    (void)textView;
    (void)charIndex;
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]]) {
        url = (NSURL *)link;
    } else if ([link isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)link];
        if (!url.scheme.length) {
            url = [NSURL fileURLWithPath:(NSString *)link];
        }
    }
    if (!url) return NO;
    BOOL ok = [[NSWorkspace sharedWorkspace] openURL:url];
    if (!ok) {
        [self appendLog:[NSString stringWithFormat:@"无法打开 %@", url.isFileURL ? url.path : url.absoluteString]];
    }
    return YES;
}

#pragma mark - Engine delegate

- (void)scraperEngine:(BrowserScraperEngine *)engine didAppendRows:(NSArray<NSDictionary *> *)rows totalRows:(NSInteger)totalRows page:(NSInteger)page {
    (void)page;
    if (engine.trialMode) {
        if (rows.count > 0) {
            NSMutableArray *preview = [(self.previewRows ?: @[]) mutableCopy];
            NSMutableArray *raw = [(self.previewRawRows ?: @[]) mutableCopy];
            [preview addObjectsFromArray:rows];
            [raw addObjectsFromArray:rows];
            self.previewRows = preview;
            self.previewRawRows = raw;
            [self rebuildPreviewColumns];
            // 滚到预览底部，方便看到追加结果
            NSInteger last = (NSInteger)MIN(200, self.previewRows.count) - 1;
            if (last >= 0) {
                [self.previewTable scrollRowToVisible:last];
            }
        }
        self.runStatusLabel.stringValue = [NSString stringWithFormat:@"试运行 已追加，预览 %lu 行（本轮合计 %ld）",
                                           (unsigned long)self.previewRows.count, (long)totalRows];
        return;
    }
    // 立即运行：不写入预览表，只更新状态
    self.runStatusLabel.stringValue = [NSString stringWithFormat:@"已采集 %ld 行", (long)totalRows];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line {
    (void)engine;
    [self appendLog:line];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didFinishWithRunDirectory:(NSString *)runDirectory error:(NSError *)error {
    BOOL trial = engine.trialMode;
    (void)engine;
    if (error) {
        [self appendLog:error.localizedDescription];
        return;
    }
    if (trial) {
        [self appendLog:[NSString stringWithFormat:@"试运行完成，预览共 %lu 行", (unsigned long)self.previewRows.count]];
        return;
    }
    [self appendLog:[NSString stringWithFormat:@"完成 %@", runDirectory.lastPathComponent]];
    NSString *path = self.draft.sink.filePath;
    if (path.length > 0) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
    }
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.candidatesTable) return (NSInteger)self.candidates.count;
    if (tableView == self.fieldsTable) return (NSInteger)self.draft.fields.count;
    if (tableView == self.previewTable) return (NSInteger)MIN(200, self.previewRows.count);
    return 0;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *ident = tableColumn.identifier;
    if (tableView == self.candidatesTable) {
        NSDictionary *c = self.candidates[row];
        if ([ident isEqualToString:@"apply"]) return @"";
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
        if ([ident isEqualToString:@"index"]) return @(row + 1);
        if ([ident isEqualToString:@"enabled"]) return @(f.enabled);
        if ([ident isEqualToString:@"name"]) return f.name;
        if ([ident isEqualToString:@"kind"]) return [BrowserScraperField stringFromKind:f.kind];
        if ([ident isEqualToString:@"path"]) return f.path;
        if ([ident isEqualToString:@"transforms"]) {
            NSString *sum = [BrowserScraperValueTransform summaryForTransforms:f.transforms];
            return sum.length ? sum : @"—";
        }
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
    if ([ident isEqualToString:@"enabled"]) {
        f.enabled = [object boolValue];
        [self refreshPreviewAfterFieldOrderChange];
    } else if ([ident isEqualToString:@"name"]) {
        f.name = [object description] ?: @"";
        [self refreshPreviewAfterFieldOrderChange];
    } else if ([ident isEqualToString:@"kind"]) f.kind = [BrowserScraperField kindFromString:[object description]];
    else if ([ident isEqualToString:@"path"]) f.path = [object description] ?: @"";
}

@end
