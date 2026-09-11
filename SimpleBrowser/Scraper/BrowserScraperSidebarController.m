#import "BrowserScraperSidebarController.h"
#import "BrowserScraperSettings.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserScraperCandidateOverlay.h"
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
static const CGFloat kContentInset = 16.0;
static const CGFloat kLogSplitHandleHeight = 6.0;
static const CGFloat kLogPaneMinHeight = 48.0;
static const CGFloat kLogPaneMaxHeight = 280.0;
static const CGFloat kFormLabelWidth = 48.0;
static const CGFloat kStandardFieldHeight = 22.0;

typedef NS_ENUM(NSInteger, BrowserScraperButtonTone) {
    BrowserScraperButtonToneSecondary = 0,
    BrowserScraperButtonTonePrimary,
    BrowserScraperButtonToneDestructive,
    BrowserScraperButtonToneQuiet,
};

@interface BrowserScraperSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) BOOL vertical; // YES = 上下拖（日志分隔）
@property (nonatomic, assign) CGFloat dragStartScreen;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation BrowserScraperSidebarResizeView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects {
    NSCursor *cursor = self.vertical ? [NSCursor resizeUpDownCursor] : [NSCursor resizeLeftRightCursor];
    [self addCursorRect:self.bounds cursor:cursor];
}
- (CGFloat)screenCoordFromEvent:(NSEvent *)event {
    NSPoint inWindow = event.locationInWindow;
    if (self.window) {
        NSPoint screen = [self.window convertPointToScreen:inWindow];
        return self.vertical ? screen.y : screen.x;
    }
    return self.vertical ? inWindow.y : inWindow.x;
}
- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    if (!window) return;
    self.dragging = YES;
    self.dragStartScreen = [self screenCoordFromEvent:event];
    if (self.onDragBegan) self.onDragBegan();
    NSCursor *cursor = self.vertical ? [NSCursor resizeUpDownCursor] : [NSCursor resizeLeftRightCursor];
    [cursor push];
    while (self.dragging) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next || next.type == NSEventTypeLeftMouseUp) break;
        if (next.type == NSEventTypeLeftMouseDragged && self.onDragToOffset) {
            CGFloat delta = [self screenCoordFromEvent:next] - self.dragStartScreen;
            // 日志在分隔条下方且底边固定：增高会把分隔条顶上去。
            // 因此 delta 与屏幕 Y（上为正）同号时，分隔条才跟手（下拖→变矮→条下移）。
            self.onDragToOffset(delta);
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

- (instancetype)initWithFrame:(NSRect)frameRect {
    // 零尺寸表头会导致 NSScrollView 未预留列头高度，首行数据会被挡住。
    if (NSHeight(frameRect) < 1.0) {
        frameRect = NSMakeRect(NSMinX(frameRect), NSMinY(frameRect),
                               MAX(NSWidth(frameRect), 1.0), 28.0);
    }
    return [super initWithFrame:frameRect];
}

- (instancetype)init {
    return [self initWithFrame:NSMakeRect(0, 0, 100, 28)];
}

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

/// 仅挂在 fieldsTable 上：实现 viewForTableColumn 不会让候选表等变成 view-based 而整表空白。
@interface BrowserScraperFieldsTableDelegate : NSObject <NSTableViewDelegate>
@property (nonatomic, weak) BrowserScraperSidebarController *owner;
@end

@interface BrowserScraperSidebarController () <BrowserScraperEngineDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong) NSView *rootView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) CGFloat dragStartLogHeight;
@property (nonatomic, strong) NSLayoutConstraint *logHeightConstraint;
@property (nonatomic, strong) BrowserScraperRecipe *draft;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, copy) NSArray<NSDictionary *> *candidates;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewRawRows;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSImageView *titleIconView;
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
@property (nonatomic, strong) NSStackView *mysqlFieldsStack;
@property (nonatomic, strong) NSTableView *fieldsTable;
@property (nonatomic, strong) BrowserScraperFieldsTableDelegate *fieldsTableDelegate;
@property (nonatomic, strong) NSTableView *previewTable;
@property (nonatomic, strong) NSTableView *candidatesTable;
@property (nonatomic, strong) NSTextField *candidatesEmptyLabel;
@property (nonatomic, strong) NSTextField *previewEmptyLabel;
@property (nonatomic, strong) NSButton *showCandidateOverlayCheck;
@property (nonatomic, strong) NSButton *onlySelectedOverlayCheck;
@property (nonatomic, strong) NSButton *clearCandidateOverlayButton;
@property (nonatomic, strong) NSButton *trialRunButton;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *saveStrategyButton;
@property (nonatomic, assign) BOOL candidateOverlayVisible;
@property (nonatomic, assign) BOOL candidateOverlayOnlySelected;
@property (nonatomic, assign) NSInteger adoptedCandidateIndex;
@property (nonatomic, strong) NSSet<NSNumber *> *missingCandidateIndexes;
@property (nonatomic, assign) BOOL suppressCandidateSelectionSync;
@property (nonatomic, strong) SBTextView *logView;
@property (nonatomic, strong) NSTextField *runStatusLabel;
@property (nonatomic, strong) NSWindow *transformHelpWindow;
/// 处理弹窗打开期间：预设下拉写回 JSON 编辑器。
@property (nonatomic, strong, nullable) SBTextView *activeTransformEditor;
@property (nonatomic, copy, nullable) NSDictionary *activeTransformPresets;

- (nullable NSView *)fieldsViewForTable:(NSTableView *)tableView
                            tableColumn:(NSTableColumn *)tableColumn
                                    row:(NSInteger)row;
@end

@implementation BrowserScraperSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [BrowserScraperSettings sharedSettings].sidebarWidth;
        _candidates = @[];
        _candidateOverlayVisible = [BrowserScraperSettings sharedSettings].candidateOverlayVisible;
        _candidateOverlayOnlySelected = [BrowserScraperSettings sharedSettings].candidateOverlayOnlySelected;
        _adoptedCandidateIndex = -1;
        _missingCandidateIndexes = [NSSet set];
        _suppressCandidateSelectionSync = NO;
        _previewRows = @[];
        _previewRawRows = @[];
        _engine = [[BrowserScraperEngine alloc] init];
        _engine.delegate = self;
        _draft = [BrowserScraperRecipe blankRecipeNamed:@"新策略"];
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
    label.maximumNumberOfLines = 1;
    label.lineBreakMode = NSLineBreakByClipping;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

- (NSTextField *)makeSectionTitle:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (nullable NSImage *)symbolNamed:(NSString *)name {
    if (name.length == 0) return nil;
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (!image) return nil;
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
        return [image imageWithSymbolConfiguration:config] ?: image;
    }
    return nil;
}

- (NSButton *)scraperButton:(NSString *)title
                     symbol:(nullable NSString *)symbolName
                       tone:(BrowserScraperButtonTone)tone
                     target:(id)target
                     action:(SEL)action {
    NSButton *btn = [NSButton buttonWithTitle:title ?: @"" target:target action:action];
    btn.bezelStyle = NSBezelStyleRounded;
    btn.font = [NSFont systemFontOfSize:11];
    NSImage *image = [self symbolNamed:symbolName];
    if (image) {
        btn.image = image;
        btn.imagePosition = NSImageLeft;
        btn.imageHugsTitle = YES;
    }
    if (@available(macOS 11.0, *)) {
        if (tone == BrowserScraperButtonTonePrimary) {
            btn.contentTintColor = [NSColor controlAccentColor];
            btn.hasDestructiveAction = NO;
        } else if (tone == BrowserScraperButtonToneDestructive) {
            btn.contentTintColor = [NSColor systemRedColor];
            btn.hasDestructiveAction = YES;
        } else if (tone == BrowserScraperButtonToneQuiet) {
            btn.contentTintColor = [NSColor secondaryLabelColor];
        }
    }
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (NSStackView *)hrowViews:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    for (NSView *v in views) {
        [self prepareFormControl:v];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = spacing;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setHuggingPriority:NSLayoutPriorityDefaultHigh
             forOrientation:NSLayoutConstraintOrientationVertical];
    return row;
}

- (NSStackView *)hrowLabel:(NSString *)text field:(NSView *)field {
    NSTextField *label = [self makeLabel:text];
    [label.widthAnchor constraintEqualToConstant:kFormLabelWidth].active = YES;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return [self hrowViews:@[label, field] spacing:6];
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
    stack.spacing = 6;
    stack.edgeInsets = NSEdgeInsetsMake(8, kContentInset, 12, kContentInset);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setHuggingPriority:NSLayoutPriorityDefaultLow
               forOrientation:NSLayoutConstraintOrientationVertical];
    for (NSView *v in stack.arrangedSubviews) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-(kContentInset * 2)].active = YES;
    }
    return stack;
}

- (void)setRunStatus:(NSString *)text tone:(BrowserScraperButtonTone)tone {
    self.runStatusLabel.stringValue = text ?: @"";
    if (tone == BrowserScraperButtonTonePrimary) {
        self.runStatusLabel.textColor = [NSColor controlAccentColor];
    } else if (tone == BrowserScraperButtonToneDestructive) {
        self.runStatusLabel.textColor = [NSColor systemRedColor];
    } else if (tone == BrowserScraperButtonToneQuiet) {
        self.runStatusLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.runStatusLabel.textColor = [NSColor secondaryLabelColor];
    }
}

- (void)updateMySQLFieldsVisibility {
    BOOL show = (self.sinkPopup.indexOfSelectedItem == (NSInteger)BrowserScraperSinkTypeMySQL);
    self.mysqlFieldsStack.hidden = !show;
}

- (void)sinkPopupChanged:(id)sender {
    (void)sender;
    [self updateMySQLFieldsVisibility];
}

- (void)applyLogPaneHeight:(CGFloat)height {
    CGFloat next = height;
    if (next < kLogPaneMinHeight) next = kLogPaneMinHeight;
    CGFloat maxH = kLogPaneMaxHeight;
    NSWindow *window = self.view.window;
    if (window) {
        CGFloat budget = NSHeight(window.contentView.bounds) * 0.4;
        if (budget > kLogPaneMinHeight) maxH = MIN(kLogPaneMaxHeight, budget);
    }
    if (next > maxH) next = maxH;
    self.logHeightConstraint.constant = next;
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

    NSButton *close = [self scraperButton:@""
                                   symbol:@"xmark"
                                     tone:BrowserScraperButtonToneQuiet
                                   target:self
                                   action:@selector(closeClicked:)];
    close.toolTip = @"关闭";
    close.bezelStyle = NSBezelStyleToolbar;

    self.titleIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.titleIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleIconView.image = [self symbolNamed:@"ladybug"];
    self.titleIconView.imageScaling = NSImageScaleProportionallyDown;
    [self.titleIconView.widthAnchor constraintEqualToConstant:16].active = YES;
    [self.titleIconView.heightAnchor constraintEqualToConstant:16].active = YES;

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
    NSStackView *header = [NSStackView stackViewWithViews:@[
        self.titleIconView, self.titleLabel, self.statusLabel, headerSpacer, close
    ]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 8;
    header.translatesAutoresizingMaskIntoConstraints = NO;

    self.segment = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.segment.segmentCount = 3;
    [self.segment setLabel:@"探测" forSegment:0];
    [self.segment setLabel:@"预览" forSegment:1];
    [self.segment setLabel:@"配置" forSegment:2];
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
        [self wrapScroll:[self buildConfigFormStack]],
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

    BrowserScraperSidebarResizeView *logSplit = [[BrowserScraperSidebarResizeView alloc] initWithFrame:NSZeroRect];
    logSplit.vertical = YES;
    logSplit.translatesAutoresizingMaskIntoConstraints = NO;
    logSplit.wantsLayer = YES;
    logSplit.layer.backgroundColor = NSColor.separatorColor.CGColor;
    logSplit.onDragBegan = ^{
        weakSelf.dragStartLogHeight = weakSelf.logHeightConstraint.constant;
    };
    logSplit.onDragToOffset = ^(CGFloat delta) {
        [weakSelf applyLogPaneHeight:weakSelf.dragStartLogHeight + delta];
    };
    logSplit.onDragEnded = ^{
        [BrowserScraperSettings sharedSettings].logPaneHeight = weakSelf.logHeightConstraint.constant;
    };

    self.runStatusLabel = [NSTextField labelWithString:@"就绪"];
    self.runStatusLabel.font = [NSFont systemFontOfSize:11];
    self.runStatusLabel.textColor = [NSColor secondaryLabelColor];
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
    CGFloat logH = [BrowserScraperSettings sharedSettings].logPaneHeight;
    self.logHeightConstraint = [logScroll.heightAnchor constraintEqualToConstant:logH];
    self.logHeightConstraint.active = YES;

    self.trialRunButton = [self scraperButton:@"试运行" symbol:@"play.circle"
                                         tone:BrowserScraperButtonToneSecondary
                                       target:self action:@selector(trialRunClicked:)];
    self.runButton = [self scraperButton:@"立即运行" symbol:@"play.fill"
                                    tone:BrowserScraperButtonTonePrimary
                                  target:self action:@selector(runClicked:)];
    self.pauseButton = [self scraperButton:@"暂停" symbol:@"pause.fill"
                                      tone:BrowserScraperButtonToneSecondary
                                    target:self action:@selector(pauseClicked:)];
    self.stopButton = [self scraperButton:@"停止" symbol:@"stop.fill"
                                     tone:BrowserScraperButtonToneDestructive
                                   target:self action:@selector(stopClicked:)];
    self.saveStrategyButton = [self scraperButton:@"保存策略" symbol:@"square.and.arrow.down"
                                             tone:BrowserScraperButtonToneSecondary
                                           target:self action:@selector(saveRecipeClicked:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[
        self.trialRunButton, self.runButton, self.pauseButton, self.stopButton, self.saveStrategyButton
    ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 6;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *body = [[NSView alloc] initWithFrame:NSZeroRect];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:header];
    [body addSubview:self.segment];
    [body addSubview:self.pagesHost];
    [body addSubview:logSplit];
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

        [header.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [header.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-kContentInset],
        [header.topAnchor constraintEqualToAnchor:body.topAnchor constant:10],

        [self.segment.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [self.segment.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-kContentInset],
        [self.segment.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],

        [self.pagesHost.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
        [self.pagesHost.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
        [self.pagesHost.topAnchor constraintEqualToAnchor:self.segment.bottomAnchor constant:6],
        [self.pagesHost.bottomAnchor constraintEqualToAnchor:logSplit.topAnchor],

        [logSplit.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [logSplit.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-kContentInset],
        [logSplit.heightAnchor constraintEqualToConstant:kLogSplitHandleHeight],
        [logSplit.bottomAnchor constraintEqualToAnchor:self.runStatusLabel.topAnchor constant:-4],

        [self.runStatusLabel.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [self.runStatusLabel.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-kContentInset],
        [self.runStatusLabel.bottomAnchor constraintEqualToAnchor:logScroll.topAnchor constant:-4],

        [logScroll.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [logScroll.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-kContentInset],
        [logScroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-8],

        [actions.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:kContentInset],
        [actions.trailingAnchor constraintLessThanOrEqualToAnchor:body.trailingAnchor constant:-kContentInset],
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
    // documentView 须走 frame 布局；TAMIC=NO 易导致表头与内容区重叠、首行被挡。
    table.translatesAutoresizingMaskIntoConstraints = YES;
    table.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
    table.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    table.usesAlternatingRowBackgroundColors = YES;
    table.delegate = self;
    table.dataSource = self;
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

/// 「探测」：紧凑多栏表单 + 候选表弹性高度。
- (NSView *)buildPageFormPage {
    NSView *page = [[NSView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;

    self.recipePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.recipePopup.target = self;
    self.recipePopup.action = @selector(recipePopupChanged:);
    self.nameField = [SBTextField standardField];
    [self.nameField.heightAnchor constraintEqualToConstant:kStandardFieldHeight].active = YES;
    [self.nameField setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationVertical];
    [self.nameField setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                             forOrientation:NSLayoutConstraintOrientationVertical];
    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modePopup addItemsWithTitles:@[ @"表格 / 列表", @"单一数据" ]];
    self.containerField = [SBTextField standardField];
    self.rowPathField = [SBTextField standardField];

    NSButton *newRecipe = [self scraperButton:@"新建" symbol:@"plus"
                                         tone:BrowserScraperButtonToneSecondary
                                       target:self action:@selector(newRecipeClicked:)];
    NSButton *detect = [self scraperButton:@"智能检测" symbol:@"wand.and.stars"
                                      tone:BrowserScraperButtonTonePrimary
                                    target:self action:@selector(detectClicked:)];
    NSButton *pickContainer = [self scraperButton:@"选择数据区" symbol:@"hand.tap"
                                             tone:BrowserScraperButtonToneSecondary
                                           target:self action:@selector(pickContainerClicked:)];
    NSButton *reanalyze = [self scraperButton:@"识别循环" symbol:@"arrow.triangle.2.circlepath"
                                         tone:BrowserScraperButtonToneSecondary
                                       target:self action:@selector(reanalyzeContainerClicked:)];

    NSTextField *strategyL = [self makeLabel:@"策略"];
    [strategyL.widthAnchor constraintEqualToConstant:kFormLabelWidth].active = YES;
    NSStackView *strategyRow = [self hrowViews:@[strategyL, self.recipePopup, newRecipe] spacing:6];
    [self.recipePopup setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *nameL = [self makeLabel:@"名称"];
    [nameL.widthAnchor constraintEqualToConstant:kFormLabelWidth].active = YES;
    NSTextField *modeL = [self makeLabel:@"模式"];
    [modeL setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationVertical];
    [modeL setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                    forOrientation:NSLayoutConstraintOrientationVertical];
    // 与 popup 显式居中，避免 label 基线导致视觉偏上/偏下
    NSStackView *nameRow = [self hrowViews:@[nameL, self.nameField, modeL, self.modePopup] spacing:6];
    nameRow.alignment = NSLayoutAttributeCenterY;
    [modeL.centerYAnchor constraintEqualToAnchor:self.modePopup.centerYAnchor].active = YES;
    [nameL.centerYAnchor constraintEqualToAnchor:self.nameField.centerYAnchor].active = YES;

    NSStackView *actionRow = [self hrowViews:@[detect, pickContainer, reanalyze] spacing:6];
    NSStackView *containerRow = [self hrowLabel:@"容器" field:self.containerField];
    NSStackView *rowPathRow = [self hrowLabel:@"行path" field:self.rowPathField];

    NSStackView *topStack = [NSStackView stackViewWithViews:@[
        strategyRow, nameRow, actionRow, containerRow, rowPathRow,
        [self makeSectionTitle:@"检测候选"]
    ]];
    topStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    topStack.alignment = NSLayoutAttributeLeading;
    topStack.spacing = 5;
    topStack.edgeInsets = NSEdgeInsetsMake(8, kContentInset, 0, kContentInset);
    topStack.translatesAutoresizingMaskIntoConstraints = NO;
    [topStack setHuggingPriority:NSLayoutPriorityDefaultHigh
                  forOrientation:NSLayoutConstraintOrientationVertical];
    for (NSView *v in topStack.arrangedSubviews) {
        [v.widthAnchor constraintEqualToAnchor:topStack.widthAnchor constant:-(kContentInset * 2)].active = YES;
    }

    self.showCandidateOverlayCheck = [NSButton checkboxWithTitle:@"显示标注"
                                                          target:self
                                                          action:@selector(showCandidateOverlayToggled:)];
    self.showCandidateOverlayCheck.state = self.candidateOverlayVisible
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.showCandidateOverlayCheck.font = [NSFont systemFontOfSize:11];
    self.onlySelectedOverlayCheck = [NSButton checkboxWithTitle:@"仅显示选中"
                                                          target:self
                                                          action:@selector(onlySelectedOverlayToggled:)];
    self.onlySelectedOverlayCheck.state = self.candidateOverlayOnlySelected
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.onlySelectedOverlayCheck.font = [NSFont systemFontOfSize:11];
    self.clearCandidateOverlayButton = [self scraperButton:@"清除" symbol:@"eye.slash"
                                                      tone:BrowserScraperButtonToneQuiet
                                                    target:self
                                                    action:@selector(clearCandidateOverlayClicked:)];
    NSStackView *overlayRow = [self hrowViews:@[
        self.showCandidateOverlayCheck,
        self.onlySelectedOverlayCheck,
        self.clearCandidateOverlayButton
    ] spacing:10];

    self.candidatesTable = [self makeTable];
    while (self.candidatesTable.tableColumns.count) {
        [self.candidatesTable removeTableColumn:self.candidatesTable.tableColumns.firstObject];
    }
    NSTableColumn *cIndex = [[NSTableColumn alloc] initWithIdentifier:@"index"];
    cIndex.title = @"#";
    cIndex.width = 28;
    cIndex.minWidth = 24;
    cIndex.maxWidth = 36;
    NSTableColumn *c0 = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    c0.title = @"类型";
    c0.width = 48;
    NSTableColumn *c1 = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    c1.title = @"候选";
    c1.width = 120;
    NSTableColumn *cScore = [[NSTableColumn alloc] initWithIdentifier:@"score"];
    cScore.title = @"分";
    cScore.width = 36;
    NSTableColumn *c2 = [[NSTableColumn alloc] initWithIdentifier:@"rows"];
    c2.title = @"行";
    c2.width = 36;
    NSTableColumn *cPreview = [[NSTableColumn alloc] initWithIdentifier:@"preview"];
    cPreview.title = @"预览";
    cPreview.width = 44;
    cPreview.minWidth = 40;
    cPreview.maxWidth = 56;
    {
        NSButtonCell *btnCell = [[NSButtonCell alloc] init];
        btnCell.bezelStyle = NSBezelStyleInline;
        btnCell.title = @"";
        btnCell.imagePosition = NSImageOnly;
        btnCell.image = [self symbolNamed:@"eye"];
        if (!btnCell.image) {
            btnCell.title = @"◎";
            btnCell.imagePosition = NSNoImage;
        }
        cPreview.dataCell = btnCell;
    }
    [self.candidatesTable addTableColumn:cIndex];
    [self.candidatesTable addTableColumn:c0];
    [self.candidatesTable addTableColumn:c1];
    [self.candidatesTable addTableColumn:cScore];
    [self.candidatesTable addTableColumn:c2];
    [self.candidatesTable addTableColumn:cPreview];
    self.candidatesTable.target = self;
    self.candidatesTable.action = @selector(candidatesTableClicked:);
    self.candidatesTable.doubleAction = @selector(candidatesTableDoubleClicked:);
    NSScrollView *candScroll = [self boxedTableScroll:self.candidatesTable height:0];
    [candScroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [candScroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    self.candidatesEmptyLabel = [self makeLabel:@"点击「智能检测」开始识别当前页数据区"];
    self.candidatesEmptyLabel.alignment = NSTextAlignmentCenter;
    self.candidatesEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [page addSubview:topStack];
    [page addSubview:overlayRow];
    [page addSubview:candScroll];
    [page addSubview:self.candidatesEmptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [topStack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [topStack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [topStack.topAnchor constraintEqualToAnchor:page.topAnchor],

        [overlayRow.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [overlayRow.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [overlayRow.topAnchor constraintEqualToAnchor:topStack.bottomAnchor constant:4],

        [candScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [candScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [candScroll.topAnchor constraintEqualToAnchor:overlayRow.bottomAnchor constant:4],
        [candScroll.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:-4],
        [candScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],

        [self.candidatesEmptyLabel.centerXAnchor constraintEqualToAnchor:candScroll.centerXAnchor],
        [self.candidatesEmptyLabel.centerYAnchor constraintEqualToAnchor:candScroll.centerYAnchor],
        [self.candidatesEmptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:candScroll.leadingAnchor constant:8],
        [self.candidatesEmptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:candScroll.trailingAnchor constant:-8],
    ]];
    return page;
}

/// 预览页：字段表 + 样本预览，纵向撑满至日志上方。
- (NSView *)buildFieldsPage {
    NSView *page = [[NSView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;

    self.fieldsTable = [self makeTable];
    self.fieldsTableDelegate = [[BrowserScraperFieldsTableDelegate alloc] init];
    self.fieldsTableDelegate.owner = self;
    self.fieldsTable.delegate = self.fieldsTableDelegate;
    while (self.fieldsTable.tableColumns.count) {
        [self.fieldsTable removeTableColumn:self.fieldsTable.tableColumns.firstObject];
    }
    for (NSArray *pair in @[ @[@"index", @"#"], @[@"enabled", @"开"], @[@"name", @"列名"], @[@"kind", @"类型"], @[@"path", @"path"], @[@"transforms", @"处理"], @[@"ops", @"操作"] ]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:pair[0]];
        col.title = pair[1];
        if ([pair[0] isEqualToString:@"index"]) {
            col.width = 28;
            col.minWidth = 24;
            col.maxWidth = 36;
        } else if ([pair[0] isEqualToString:@"enabled"]) col.width = 28;
        else if ([pair[0] isEqualToString:@"transforms"]) col.width = 72;
        else if ([pair[0] isEqualToString:@"ops"]) {
            col.width = 100;
            col.minWidth = 96;
            col.maxWidth = 120;
        } else col.width = 90;
        [self.fieldsTable addTableColumn:col];
    }
    NSScrollView *fieldsScroll = [self boxedTableScroll:self.fieldsTable height:140];

    NSButton *addField = [self scraperButton:@"点选添加" symbol:@"plus.square.on.square"
                                        tone:BrowserScraperButtonToneSecondary
                                      target:self action:@selector(pickFieldClicked:)];
    NSButton *removeField = [self scraperButton:@"删除" symbol:@"trash"
                                           tone:BrowserScraperButtonToneDestructive
                                         target:self action:@selector(removeFieldClicked:)];
    NSButton *preview = [self scraperButton:@"刷新预览" symbol:@"arrow.clockwise"
                                       tone:BrowserScraperButtonToneSecondary
                                     target:self action:@selector(previewClicked:)];
    NSStackView *actionsPrimary = [self hrowViews:@[addField, removeField, preview] spacing:6];

    NSTextField *previewLabel = [self makeSectionTitle:@"预览"];

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

    self.previewEmptyLabel = [self makeLabel:@"配置字段后点「刷新预览」查看样本行"];
    self.previewEmptyLabel.alignment = NSTextAlignmentCenter;
    self.previewEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [page addSubview:fieldsScroll];
    [page addSubview:actionsPrimary];
    [page addSubview:previewLabel];
    [page addSubview:previewScroll];
    [page addSubview:self.previewEmptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [fieldsScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [fieldsScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [fieldsScroll.topAnchor constraintEqualToAnchor:page.topAnchor constant:8],

        [actionsPrimary.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [actionsPrimary.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [actionsPrimary.topAnchor constraintEqualToAnchor:fieldsScroll.bottomAnchor constant:6],

        [previewLabel.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [previewLabel.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [previewLabel.topAnchor constraintEqualToAnchor:actionsPrimary.bottomAnchor constant:6],

        [previewScroll.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:kContentInset],
        [previewScroll.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-kContentInset],
        [previewScroll.topAnchor constraintEqualToAnchor:previewLabel.bottomAnchor constant:4],
        [previewScroll.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:-4],
        [previewScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],

        [self.previewEmptyLabel.centerXAnchor constraintEqualToAnchor:previewScroll.centerXAnchor],
        [self.previewEmptyLabel.centerYAnchor constraintEqualToAnchor:previewScroll.centerYAnchor],
        [self.previewEmptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:previewScroll.leadingAnchor constant:8],
        [self.previewEmptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:previewScroll.trailingAnchor constant:-8],
    ]];
    return page;
}

- (NSStackView *)buildConfigFormStack {
    self.paginationPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.paginationPopup addItemsWithTitles:@[ @"无", @"下一页按钮", @"页码", @"Load More", @"无限滚动" ]];
    self.paginationSelectorField = [SBTextField standardField];
    self.maxPagesField = [SBTextField standardField];
    self.maxRowsField = [SBTextField standardField];
    self.delayField = [SBTextField standardField];
    NSButton *pickPag = [self scraperButton:@"点选翻页" symbol:@"hand.point.up.left"
                                       tone:BrowserScraperButtonToneSecondary
                                     target:self action:@selector(pickPaginationClicked:)];
    NSTextField *pagTypeL = [self makeLabel:@"类型"];
    [pagTypeL.widthAnchor constraintEqualToConstant:kFormLabelWidth].active = YES;
    NSStackView *pagTypeRow = [self hrowViews:@[pagTypeL, self.paginationPopup, pickPag] spacing:6];
    NSStackView *pagSelRow = [self hrowLabel:@"选择器" field:self.paginationSelectorField];

    // 页数 / 行数 / 延迟：标准高度输入框 + 上标签下控件三列，避免挤扁裁字
    static const CGFloat kPagNumFieldWidth = 88.0;
    NSStackView *(^pagNumColumn)(NSString *, SBTextField *) = ^NSStackView *(NSString *title, SBTextField *field) {
        NSTextField *lab = [self makeLabel:title];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [field.widthAnchor constraintEqualToConstant:kPagNumFieldWidth].active = YES;
        [field.heightAnchor constraintEqualToConstant:kStandardFieldHeight].active = YES;
        [field setContentHuggingPriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationVertical];
        [field setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationVertical];
        [field setContentHuggingPriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [field setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *col = [NSStackView stackViewWithViews:@[lab, field]];
        col.orientation = NSUserInterfaceLayoutOrientationVertical;
        col.alignment = NSLayoutAttributeLeading;
        col.spacing = 3;
        col.translatesAutoresizingMaskIntoConstraints = NO;
        [col setHuggingPriority:NSLayoutPriorityRequired
                 forOrientation:NSLayoutConstraintOrientationVertical];
        return col;
    };
    NSStackView *pagNumsRow = [self hrowViews:@[
        pagNumColumn(@"页数", self.maxPagesField),
        pagNumColumn(@"行数", self.maxRowsField),
        pagNumColumn(@"延迟(ms)", self.delayField),
    ] spacing:12];
    // 行本身不要为了竖直 hugging 把子控件压矮
    [pagNumsRow setHuggingPriority:NSLayoutPriorityDefaultLow
                    forOrientation:NSLayoutConstraintOrientationVertical];
    [pagNumsRow setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                         forOrientation:NSLayoutConstraintOrientationVertical];

    self.sessionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.sessionPopup addItemsWithTitles:@[ @"共用浏览器 Cookie", @"独立会话" ]];
    self.scheduleCheck = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.scheduleCheck.buttonType = NSButtonTypeSwitch;
    self.scheduleCheck.title = @"启用定时爬取";
    self.intervalField = [SBTextField standardField];
    NSStackView *sessionRow = [self hrowLabel:@"会话" field:self.sessionPopup];
    NSStackView *schedRow = [self hrowViews:@[
        self.scheduleCheck, [self makeLabel:@"间隔(分)"], self.intervalField
    ] spacing:6];
    NSTextField *taskHint = [self makeLabel:@"定时由 MeoScrapeRunner / LaunchAgent 执行，不占用主窗口。"];
    taskHint.maximumNumberOfLines = 2;

    self.sinkPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.sinkPopup addItemsWithTitles:@[ @"Excel (xlsx)", @"CSV", @"JSON", @"MySQL" ]];
    self.sinkPopup.target = self;
    self.sinkPopup.action = @selector(sinkPopupChanged:);
    self.filePathField = [SBTextField standardField];
    self.filePathField.placeholderString = @"空则写入下载文件夹";
    self.mysqlHostField = [SBTextField standardField];
    self.mysqlPortField = [SBTextField standardField];
    self.mysqlDBField = [SBTextField standardField];
    self.mysqlUserField = [SBTextField standardField];
    self.mysqlPasswordField = [SBSecureTextField standardField];
    self.mysqlTableField = [SBTextField standardField];
    NSButton *testMySQL = [self scraperButton:@"测试连接" symbol:@"cylinder.split.1x2"
                                         tone:BrowserScraperButtonToneSecondary
                                       target:self action:@selector(testMySQLClicked:)];
    NSStackView *sinkRow = [self hrowLabel:@"目标" field:self.sinkPopup];
    NSStackView *pathRow = [self hrowLabel:@"路径" field:self.filePathField];
    NSStackView *mysqlHostRow = [self hrowViews:@[
        [self makeLabel:@"Host"], self.mysqlHostField,
        [self makeLabel:@"Port"], self.mysqlPortField
    ] spacing:6];
    NSStackView *mysqlDBRow = [self hrowViews:@[
        [self makeLabel:@"DB"], self.mysqlDBField,
        [self makeLabel:@"表"], self.mysqlTableField
    ] spacing:6];
    NSStackView *mysqlUserRow = [self hrowViews:@[
        [self makeLabel:@"User"], self.mysqlUserField,
        [self makeLabel:@"密码"], self.mysqlPasswordField
    ] spacing:6];
    self.mysqlFieldsStack = [NSStackView stackViewWithViews:@[mysqlHostRow, mysqlDBRow, mysqlUserRow, testMySQL]];
    self.mysqlFieldsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.mysqlFieldsStack.alignment = NSLayoutAttributeLeading;
    self.mysqlFieldsStack.spacing = 5;
    self.mysqlFieldsStack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in self.mysqlFieldsStack.arrangedSubviews) {
        [v.widthAnchor constraintEqualToAnchor:self.mysqlFieldsStack.widthAnchor].active = YES;
    }

    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSZeroRect];
    sep1.boxType = NSBoxSeparator;
    sep1.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSZeroRect];
    sep2.boxType = NSBoxSeparator;
    sep2.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [self vstack:@[
        [self makeSectionTitle:@"翻页"],
        pagTypeRow, pagSelRow, pagNumsRow,
        sep1,
        [self makeSectionTitle:@"任务"],
        sessionRow, schedRow, taskHint,
        sep2,
        [self makeSectionTitle:@"导出"],
        sinkRow, pathRow, self.mysqlFieldsStack,
    ]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateMySQLFieldsVisibility];
    });
    return stack;
}

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
            [BrowserScraperCandidateOverlay clearInWebView:[self currentWebView]];
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
    // 预览页：从隐藏切到可见时重排预览表，避免首行被表头挡住
    if (idx == 1) {
        [self repairPreviewTableLayoutAfterBecomingVisible];
    }
}

/// 预览页刚显示时，强制 NSScrollView 为表头让出空间并把首行滚入可视区。
- (void)repairPreviewTableLayoutAfterBecomingVisible {
    NSScrollView *scroll = self.previewTable.enclosingScrollView;
    if (!scroll || !self.previewTable) return;

    void (^fix)(void) = ^{
        [scroll layoutSubtreeIfNeeded];
        [self.previewTable tile];
        NSTableHeaderView *header = self.previewTable.headerView;
        if (header && NSHeight(header.frame) < 1.0) {
            NSRect hf = header.frame;
            hf.size.height = 28.0;
            header.frame = hf;
            [self.previewTable tile];
        }
        if (self.previewTable.numberOfRows > 0) {
            [self.previewTable scrollRowToVisible:0];
        } else {
            NSClipView *clip = scroll.contentView;
            if (clip) {
                NSRect doc = [scroll.documentView frame];
                NSSize visible = clip.bounds.size;
                CGFloat y = MAX(0, NSHeight(doc) - visible.height);
                [clip scrollToPoint:NSMakePoint(clip.bounds.origin.x, y)];
                [scroll reflectScrolledClipView:clip];
            }
        }
        [self syncPreviewHeaderScrollWithContent];
    };
    fix();
    dispatch_async(dispatch_get_main_queue(), fix);
}

#pragma mark - Sync

- (void)reloadForCurrentURL {
    [BrowserScraperCandidateOverlay clearInWebView:[self currentWebView]];
    [self refreshRecipePopup];
    NSURL *url = nil;
    if ([self.delegate respondsToSelector:@selector(scraperSidebarCurrentURL:)]) {
        url = [self.delegate scraperSidebarCurrentURL:self];
    }
    NSArray *matched = url ? [[BrowserScraperRecipeStore sharedStore] recipesMatchingURL:url] : @[];
    if (matched.count > 0) {
        self.draft = [matched.firstObject copy];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"本页策略 %lu", (unsigned long)matched.count];
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
    [self updateMySQLFieldsVisibility];
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
    self.draft = [BrowserScraperRecipe blankRecipeNamed:@"新策略"];
    NSURL *url = [self.delegate scraperSidebarCurrentURL:self];
    if (url.host.length > 0) {
        self.draft.match.hosts = @[ url.host.lowercaseString ];
        self.draft.startURL = url.absoluteString;
    }

    // 候选 / 预览回到初始空状态（含页内标注）
    [BrowserScraperCandidateOverlay clearInWebView:[self currentWebView]];
    self.candidates = @[];
    self.adoptedCandidateIndex = -1;
    self.missingCandidateIndexes = [NSSet set];
    self.previewRows = @[];
    self.previewRawRows = @[];
    [self.candidatesTable deselectAll:nil];
    [self.candidatesTable reloadData];
    self.candidatesEmptyLabel.hidden = NO;

    [self syncUIFromDraft];
    [self appendLog:@"已新建策略草稿"];
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
    [self appendLog:[NSString stringWithFormat:@"智能识别：%@ · 循环 %@ · 约 %ld 行 · %lu 字段（叶子拆分）",
                     title, rowPath.length ? rowPath : @"(无)", (long)rows, (unsigned long)fields.count]];
    [self markAdoptedCandidateMatchingContainerPath:container];
    [self syncUIFromDraft];
    [self detectAndApplyPaginationNearPath:container];
    [self previewClicked:nil];
}

- (void)markAdoptedCandidateMatchingContainerPath:(NSString *)containerPath {
    NSInteger found = -1;
    if (containerPath.length > 0) {
        for (NSInteger i = 0; i < (NSInteger)self.candidates.count; i++) {
            NSDictionary *c = self.candidates[i];
            NSString *path = [c[@"containerPath"] isKindOfClass:[NSString class]] ? c[@"containerPath"] : @"";
            if ([path isEqualToString:containerPath]) {
                found = i;
                break;
            }
        }
    }
    self.adoptedCandidateIndex = found;
    [self.candidatesTable reloadData];
    WKWebView *wv = [self currentWebView];
    if (wv && self.candidates.count > 0) {
        [BrowserScraperCandidateOverlay setAdoptedIndex:found inWebView:wv];
    }
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
    [BrowserScraperCandidateOverlay clearInWebView:wv];
    self.adoptedCandidateIndex = -1;
    self.missingCandidateIndexes = [NSSet set];
    [self appendLog:@"正在智能检测表格 / 列表 / 卡片与翻页方式…"];
    [BrowserScraperDetector detectCandidatesInWebView:wv completion:^(NSArray<NSDictionary *> *candidates) {
        self.candidates = candidates;
        [self.candidatesTable reloadData];
        self.candidatesEmptyLabel.hidden = (candidates.count > 0);
        if (candidates.count == 0) {
            [self appendLog:@"未检测到可用候选，仍尝试识别整页翻页…"];
            [self detectAndApplyPaginationNearPath:@""];
            return;
        }
        self.suppressCandidateSelectionSync = YES;
        [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self.candidatesTable scrollRowToVisible:0];
        self.suppressCandidateSelectionSync = NO;
        [self refreshCandidateOverlaySelectingIndex:0];
        NSDictionary *best = candidates.firstObject;
        NSInteger score = [best[@"score"] respondsToSelector:@selector(integerValue)]
            ? [best[@"score"] integerValue] : 0;
        BOOL confident = [best[@"confident"] boolValue];
        NSString *title = [best[@"title"] isKindOfClass:[NSString class]] ? best[@"title"] : @"候选";
        NSString *near = [best[@"containerPath"] isKindOfClass:[NSString class]] ? best[@"containerPath"] : @"";
        if (confident) {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，已在页面标注，智能采用：%@（分 %ld）",
                             (unsigned long)candidates.count, title, (long)score]];
            [self applyAnalysisDictionary:best];
        } else {
            [self appendLog:[NSString stringWithFormat:@"检测到 %lu 个候选，已在页面标注并选中推荐项（分 %ld）。单击行采用；点预览或双击行查看字段预览",
                             (unsigned long)candidates.count, (long)score]];
            [self detectAndApplyPaginationNearPath:near];
        }
    }];
}

- (void)adoptCandidateAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    [self applyAnalysisDictionary:self.candidates[row]];
}

- (void)openCandidatePreviewAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    self.suppressCandidateSelectionSync = YES;
    [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    self.suppressCandidateSelectionSync = NO;
    [self adoptCandidateAtRow:row];
    if (self.candidateOverlayVisible) {
        [BrowserScraperCandidateOverlay setSelectedIndex:row inWebView:[self currentWebView]];
    }
    if (self.segment.segmentCount > 1) {
        self.segment.selectedSegment = 1;
        [self segmentChanged:self.segment];
    }
    [self previewClicked:nil];
}

- (void)useCandidateClicked:(id)sender {
    (void)sender;
    [self adoptCandidateAtRow:self.candidatesTable.selectedRow];
}

- (void)candidatesTableClicked:(id)sender {
    (void)sender;
    NSInteger row = self.candidatesTable.clickedRow;
    NSInteger col = self.candidatesTable.clickedColumn;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    if (col >= 0 && col < (NSInteger)self.candidatesTable.tableColumns.count) {
        NSTableColumn *column = self.candidatesTable.tableColumns[col];
        if ([column.identifier isEqualToString:@"preview"]) {
            [self openCandidatePreviewAtRow:row];
            return;
        }
    }
    // 单击非预览列：采用该候选（已选中行再点一次也会走这里）
    [self adoptCandidateAtRow:row];
    if (self.candidateOverlayVisible) {
        [self refreshCandidateOverlaySelectingIndex:row];
    }
}

- (void)candidatesTableDoubleClicked:(id)sender {
    (void)sender;
    NSInteger row = self.candidatesTable.clickedRow;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    [self openCandidatePreviewAtRow:row];
}

- (void)refreshCandidateOverlaySelectingIndex:(NSInteger)index {
    WKWebView *wv = [self currentWebView];
    if (!wv) return;
    if (self.candidates.count == 0) {
        [BrowserScraperCandidateOverlay clearInWebView:wv];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BrowserScraperCandidateOverlay showCandidates:self.candidates
                                        inWebView:wv
                                    selectedIndex:index
                                     adoptedIndex:self.adoptedCandidateIndex
                                     onlySelected:self.candidateOverlayOnlySelected
                                       completion:^(NSArray<NSNumber *> *missingIndexes) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSSet<NSNumber *> *next = [NSSet setWithArray:missingIndexes ?: @[]];
        BOOL changed = ![next isEqualToSet:self.missingCandidateIndexes];
        self.missingCandidateIndexes = next;
        if (changed) {
            [self.candidatesTable reloadData];
            if (next.count > 0) {
                [self appendLog:[NSString stringWithFormat:@"有 %lu 个候选 path 在当前页无法定位，已在侧栏灰显",
                                 (unsigned long)next.count]];
            }
        }
    }];
    if (!self.candidateOverlayVisible) {
        [BrowserScraperCandidateOverlay setVisible:NO inWebView:wv];
    }
}

- (void)showCandidateOverlayToggled:(id)sender {
    (void)sender;
    self.candidateOverlayVisible = (self.showCandidateOverlayCheck.state == NSControlStateValueOn);
    [BrowserScraperSettings sharedSettings].candidateOverlayVisible = self.candidateOverlayVisible;
    WKWebView *wv = [self currentWebView];
    if (self.candidateOverlayVisible) {
        if (self.candidates.count > 0) {
            NSInteger row = self.candidatesTable.selectedRow;
            if (row < 0) row = 0;
            [self refreshCandidateOverlaySelectingIndex:row];
        }
    } else {
        [BrowserScraperCandidateOverlay setVisible:NO inWebView:wv];
    }
}

- (void)onlySelectedOverlayToggled:(id)sender {
    (void)sender;
    self.candidateOverlayOnlySelected = (self.onlySelectedOverlayCheck.state == NSControlStateValueOn);
    [BrowserScraperSettings sharedSettings].candidateOverlayOnlySelected = self.candidateOverlayOnlySelected;
    WKWebView *wv = [self currentWebView];
    if (!wv || self.candidates.count == 0) return;
    if (self.candidateOverlayVisible) {
        [BrowserScraperCandidateOverlay setOnlySelected:self.candidateOverlayOnlySelected inWebView:wv];
    }
}

- (void)clearCandidateOverlayClicked:(id)sender {
    (void)sender;
    [BrowserScraperCandidateOverlay clearInWebView:[self currentWebView]];
    self.candidateOverlayVisible = NO;
    self.showCandidateOverlayCheck.state = NSControlStateValueOff;
    [BrowserScraperSettings sharedSettings].candidateOverlayVisible = NO;
    [self appendLog:@"已清除页面数据区标注"];
}

- (void)handleCandidateOverlayMessage:(id)body {
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSString *action = [body[@"action"] isKindOfClass:[NSString class]] ? body[@"action"] : @"";
    if ([action isEqualToString:@"clearCandidateOverlay"]) {
        [self clearCandidateOverlayClicked:nil];
        return;
    }
    if (![action isEqualToString:@"selectCandidate"]) return;
    NSInteger index = [BrowserScraperCandidateOverlay indexFromSelectCandidateMessage:body];
    if (index < 0 || index >= (NSInteger)self.candidates.count) return;
    self.suppressCandidateSelectionSync = YES;
    [self.candidatesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self.candidatesTable scrollRowToVisible:index];
    self.suppressCandidateSelectionSync = NO;
    // 页内点选候选：等同侧栏单击采用
    [self adoptCandidateAtRow:index];
    if (self.candidateOverlayVisible) {
        [BrowserScraperCandidateOverlay setSelectedIndex:index inWebView:[self currentWebView]];
    }
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
    [BrowserScraperCandidateOverlay setVisible:NO inWebView:wv];
    [self appendLog:@"请在页面上点击数据区或其中某一卡片…"];
    [BrowserScraperElementPicker startPickingInWebView:wv mode:BrowserScraperPickModeContainer completion:^(NSDictionary *result, BOOL cancelled) {
        if (self.candidateOverlayVisible && self.candidates.count > 0) {
            NSInteger row = self.candidatesTable.selectedRow;
            if (row < 0) row = 0;
            [self refreshCandidateOverlaySelectingIndex:row];
        }
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
    [BrowserScraperCandidateOverlay setVisible:NO inWebView:wv];
    [BrowserScraperElementPicker startPickingInWebView:wv
                                                  mode:BrowserScraperPickModeField
                                         containerPath:loop ? container : nil
                                               rowPath:loop ? rowPath : nil
                                            completion:^(NSDictionary *result, BOOL cancelled) {
        if (self.candidateOverlayVisible && self.candidates.count > 0) {
            NSInteger row = self.candidatesTable.selectedRow;
            if (row < 0) row = 0;
            [self refreshCandidateOverlaySelectingIndex:row];
        }
        if (cancelled || !result) return;
        [self applyPickResult:result mode:BrowserScraperPickModeField];
    }];
}

- (void)pickPaginationClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self currentWebView];
    [BrowserScraperCandidateOverlay setVisible:NO inWebView:wv];
    [BrowserScraperElementPicker startPickingInWebView:wv mode:BrowserScraperPickModePagination completion:^(NSDictionary *result, BOOL cancelled) {
        if (self.candidateOverlayVisible && self.candidates.count > 0) {
            NSInteger row = self.candidatesTable.selectedRow;
            if (row < 0) row = 0;
            [self refreshCandidateOverlaySelectingIndex:row];
        }
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
    [self moveFieldAtIndex:self.fieldsTable.selectedRow byOffset:-1];
}

- (void)moveFieldDownClicked:(id)sender {
    (void)sender;
    [self moveFieldAtIndex:self.fieldsTable.selectedRow byOffset:1];
}

- (void)moveFieldAtIndex:(NSInteger)row byOffset:(NSInteger)offset {
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
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

- (NSButton *)fieldOpsIconButton:(NSString *)symbolName
                      identifier:(NSString *)identifier
                         tooltip:(NSString *)tooltip {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bordered = NO;
    btn.bezelStyle = NSBezelStyleInline;
    btn.title = @"";
    btn.imagePosition = NSImageOnly;
    btn.image = [self symbolNamed:symbolName];
    if (!btn.image) {
        // 旧系统无 SF Symbol 时用短字符兜底
        if ([identifier isEqualToString:@"up"]) btn.title = @"↑";
        else if ([identifier isEqualToString:@"down"]) btn.title = @"↓";
        else if ([identifier isEqualToString:@"transform"]) btn.title = @"处";
        else btn.title = @"复";
        btn.imagePosition = NSNoImage;
        btn.font = [NSFont systemFontOfSize:11];
    }
    btn.identifier = identifier;
    btn.toolTip = tooltip;
    btn.target = self;
    btn.action = @selector(fieldOpsClicked:);
    [btn.widthAnchor constraintEqualToConstant:22].active = YES;
    [btn.heightAnchor constraintEqualToConstant:20].active = YES;
    return btn;
}

- (NSStackView *)makeFieldOpsCellView {
    NSButton *up = [self fieldOpsIconButton:@"arrow.up" identifier:@"up" tooltip:@"上移"];
    NSButton *down = [self fieldOpsIconButton:@"arrow.down" identifier:@"down" tooltip:@"下移"];
    NSButton *tx = [self fieldOpsIconButton:@"slider.horizontal.3" identifier:@"transform" tooltip:@"处理"];
    NSButton *dup = [self fieldOpsIconButton:@"doc.on.doc" identifier:@"duplicate" tooltip:@"复制为新字段"];
    NSStackView *stack = [NSStackView stackViewWithViews:@[up, down, tx, dup]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 1;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.edgeInsets = NSEdgeInsetsMake(0, 2, 0, 2);
    stack.identifier = @"fieldOps";
    return stack;
}

- (void)configureFieldOpsCellView:(NSView *)view forRow:(NSInteger)row {
    NSStackView *stack = [view isKindOfClass:[NSStackView class]] ? (NSStackView *)view : nil;
    if (!stack) return;
    NSInteger last = (NSInteger)self.draft.fields.count - 1;
    for (NSView *sub in stack.arrangedSubviews) {
        if (![sub isKindOfClass:[NSButton class]]) continue;
        NSButton *btn = (NSButton *)sub;
        btn.tag = row;
        if ([btn.identifier isEqualToString:@"up"]) {
            btn.enabled = row > 0;
        } else if ([btn.identifier isEqualToString:@"down"]) {
            btn.enabled = row >= 0 && row < last;
        } else {
            btn.enabled = row >= 0 && row <= last;
        }
    }
}

- (void)fieldOpsClicked:(id)sender {
    if (![sender isKindOfClass:[NSButton class]]) return;
    NSButton *btn = (NSButton *)sender;
    NSInteger row = btn.tag;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    NSString *op = btn.identifier;
    if ([op isEqualToString:@"up"]) {
        [self moveFieldAtIndex:row byOffset:-1];
    } else if ([op isEqualToString:@"down"]) {
        [self moveFieldAtIndex:row byOffset:1];
    } else if ([op isEqualToString:@"transform"]) {
        [self editTransformForFieldAtIndex:row];
    } else if ([op isEqualToString:@"duplicate"]) {
        [self duplicateFieldAtIndex:row];
    }
}

- (NSString *)uniqueFieldNameBasedOn:(NSString *)baseName {
    NSString *root = baseName.length > 0 ? baseName : @"字段";
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (BrowserScraperField *f in self.draft.fields) {
        if (f.name.length > 0) [used addObject:f.name];
    }
    NSInteger n = 2;
    NSString *candidate;
    do {
        candidate = [NSString stringWithFormat:@"%@_%ld", root, (long)n++];
    } while ([used containsObject:candidate]);
    return candidate;
}

- (void)duplicateFieldAtIndex:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    BrowserScraperField *src = self.draft.fields[row];
    BrowserScraperField *dup = [src copy];
    dup.fieldID = [[NSUUID UUID] UUIDString];
    dup.name = [self uniqueFieldNameBasedOn:src.name];
    NSMutableArray *fields = [self.draft.fields mutableCopy];
    [fields insertObject:dup atIndex:row + 1];
    self.draft.fields = fields;
    [self.fieldsTable reloadData];
    NSInteger newRow = row + 1;
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self.fieldsTable scrollRowToVisible:newRow];
    [self appendLog:[NSString stringWithFormat:@"已复制字段「%@」→「%@」", src.name ?: @"", dup.name ?: @""]];
    [self refreshPreviewAfterFieldOrderChange];
}

- (void)editTransformClicked:(id)sender {
    (void)sender;
    [self editTransformForFieldAtIndex:self.fieldsTable.selectedRow];
}

- (void)editTransformForFieldAtIndex:(NSInteger)row {
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
    alert.informativeText = @"选择预设会立刻填入下方步骤；也可直接编辑 JSON。\n常用：digits / number / regex / relTime / remove / trim";
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
    preset.target = self;
    preset.action = @selector(transformPresetChanged:);
    NSButton *helpBtn = [NSButton buttonWithTitle:@"函数说明…" target:self action:@selector(showTransformHelpClicked:)];
    helpBtn.bezelStyle = NSBezelStyleRounded;
    helpBtn.frame = NSMakeRect(308, 204, 112, 28);

    NSTextField *sampleLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"样例原文：%@", sample.length ? sample : @"(刷新预览后可带入)"]];
    sampleLabel.frame = NSMakeRect(0, 178, 420, 20);
    sampleLabel.font = [NSFont systemFontOfSize:11];
    sampleLabel.textColor = NSColor.secondaryLabelColor;
    sampleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSTextField *hint = [NSTextField labelWithString:@"点击「函数说明…」可同时查看（不挡住本对话框）"];
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

    self.activeTransformEditor = tv;
    self.activeTransformPresets = presets;

    NSModalResponse resp = [alert runModal];
    self.activeTransformEditor = nil;
    self.activeTransformPresets = nil;

    if (resp == NSAlertThirdButtonReturn) return;
    if (resp == NSAlertSecondButtonReturn) {
        field.transforms = @[];
        [self.fieldsTable reloadData];
        [self appendLog:[NSString stringWithFormat:@"已清除字段「%@」的处理步骤", field.name]];
        [self previewClicked:nil];
        return;
    }

    // 预设已在选择时写入编辑器；应用时始终以编辑器 JSON 为准
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
    field.transforms = arr;
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

- (void)transformPresetChanged:(id)sender {
    if (![sender isKindOfClass:[NSPopUpButton class]]) return;
    NSPopUpButton *preset = (NSPopUpButton *)sender;
    NSInteger idx = preset.indexOfSelectedItem;
    if (idx <= 0 || !self.activeTransformEditor) return;
    NSString *title = preset.titleOfSelectedItem;
    NSArray *steps = self.activeTransformPresets[title];
    if (![steps isKindOfClass:[NSArray class]]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:steps
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]";
    self.activeTransformEditor.string = json;
    [self.activeTransformEditor scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)showTransformHelpClicked:(id)sender {
    (void)sender;
    if (self.transformHelpWindow && self.transformHelpWindow.isVisible) {
        [self.transformHelpWindow makeKeyAndOrderFront:nil];
        return;
    }

    NSRect rect = NSMakeRect(0, 0, 560, 520);
    // NSPanel + worksWhenModal：可在处理对话框（runModal）之上独立开关，不互相卡住
    NSPanel *win = [[NSPanel alloc] initWithContentRect:rect
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskResizable |
                                                         NSWindowStyleMaskUtilityWindow)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    win.title = @"字段处理 · 函数说明";
    win.minSize = NSMakeSize(420, 320);
    win.releasedWhenClosed = NO;
    win.floatingPanel = YES;
    win.worksWhenModal = YES;
    win.level = NSFloatingWindowLevel;
    win.hidesOnDeactivate = NO;

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
    close.keyEquivalent = @"\033"; // Esc 关闭说明，避免抢处理框的 Return

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
    self.previewEmptyLabel.hidden = (self.previewRows.count > 0);

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
    dispatch_async(dispatch_get_main_queue(), ^{
        restoreScroll();
        if (self.segment.selectedSegment == 1) {
            [self repairPreviewTableLayoutAfterBecomingVisible];
        }
    });

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
    [self appendLog:@"策略已保存"];
}

- (void)setRunningControlsEnabled:(BOOL)enabled {
    self.trialRunButton.enabled = enabled;
    self.runButton.enabled = enabled;
    self.saveStrategyButton.enabled = enabled;
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
    // 切到「预览」页以便看到预览追加
    if (self.segment.segmentCount > 1) {
        self.segment.selectedSegment = 1;
        [self segmentChanged:self.segment];
    }
    [self setRunningControlsEnabled:NO];
    [self setRunStatus:@"试运行中…" tone:BrowserScraperButtonTonePrimary];
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
    [self setRunningControlsEnabled:NO];
    [self setRunStatus:@"运行中…" tone:BrowserScraperButtonTonePrimary];
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
    // 不覆盖运行中的着色状态文案时仍同步一行摘要
    if (!self.engine.running) {
        self.runStatusLabel.stringValue = text;
        self.runStatusLabel.textColor = [NSColor secondaryLabelColor];
    }

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
        self.runStatusLabel.textColor = [NSColor controlAccentColor];
        return;
    }
    // 立即运行：不写入预览表，只更新状态
    [self setRunStatus:[NSString stringWithFormat:@"已采集 %ld 行", (long)totalRows]
                  tone:BrowserScraperButtonTonePrimary];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line {
    (void)engine;
    [self appendLog:line];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didFinishWithRunDirectory:(NSString *)runDirectory error:(NSError *)error {
    BOOL trial = engine.trialMode;
    (void)engine;
    [self setRunningControlsEnabled:YES];
    if (error) {
        [self setRunStatus:error.localizedDescription ?: @"失败" tone:BrowserScraperButtonToneDestructive];
        [self appendLog:error.localizedDescription];
        return;
    }
    if (trial) {
        [self setRunStatus:[NSString stringWithFormat:@"试运行完成 · %lu 行", (unsigned long)self.previewRows.count]
                      tone:BrowserScraperButtonToneQuiet];
        [self appendLog:[NSString stringWithFormat:@"试运行完成，预览共 %lu 行", (unsigned long)self.previewRows.count]];
        return;
    }
    [self setRunStatus:@"完成" tone:BrowserScraperButtonToneQuiet];
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
        BOOL missing = [self.missingCandidateIndexes containsObject:@(row)];
        if ([ident isEqualToString:@"index"]) return @(row + 1);
        if ([ident isEqualToString:@"preview"]) return @"";
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
            NSString *text;
            if (title.length && sample.length) {
                text = [NSString stringWithFormat:@"%@ · %@", title, sample];
            } else {
                text = title.length ? title : sample;
            }
            if (missing && text.length > 0) {
                return [NSString stringWithFormat:@"%@（已失效）", text];
            }
            if (missing) return @"（已失效）";
            return text;
        }
        if ([ident isEqualToString:@"score"]) return c[@"score"] ?: @0;
        if ([ident isEqualToString:@"rows"]) return c[@"estimatedRows"];
        return @"";
    }
    if (tableView == self.fieldsTable) {
        if ([ident isEqualToString:@"ops"]) return @"";
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

- (NSTableCellView *)makeFieldsTextCellView:(NSString *)identifier editable:(BOOL)editable {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = identifier;
    NSTextField *text;
    if (editable) {
        SBTextField *field = [SBTextField standardField];
        field.bordered = NO;
        field.bezeled = NO;
        field.drawsBackground = NO;
        field.focusRingType = NSFocusRingTypeDefault;
        field.font = [NSFont systemFontOfSize:11];
        field.target = self;
        field.action = @selector(fieldCellTextEdited:);
        text = field;
    } else {
        text = [NSTextField labelWithString:@""];
        text.font = [NSFont systemFontOfSize:11];
        text.textColor = NSColor.labelColor;
    }
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.lineBreakMode = NSLineBreakByTruncatingTail;
    text.maximumNumberOfLines = 1;
    [cell addSubview:text];
    cell.textField = text;
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (NSTableCellView *)makeFieldsEnabledCellView {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = @"fieldEnabled";
    NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(fieldEnabledToggled:)];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.identifier = @"fieldEnabledCheck";
    [cell addSubview:check];
    [NSLayoutConstraint activateConstraints:@[
        [check.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
        [check.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (nullable NSButton *)fieldsEnabledCheckboxInCell:(NSTableCellView *)cell {
    for (NSView *sub in cell.subviews) {
        if ([sub isKindOfClass:[NSButton class]] && [sub.identifier isEqualToString:@"fieldEnabledCheck"]) {
            return (NSButton *)sub;
        }
    }
    return nil;
}

- (void)fieldEnabledToggled:(id)sender {
    if (![sender isKindOfClass:[NSButton class]]) return;
    NSButton *check = (NSButton *)sender;
    NSInteger row = check.tag;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return;
    BrowserScraperField *f = self.draft.fields[row];
    f.enabled = (check.state == NSControlStateValueOn);
    [self.fieldsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self refreshPreviewAfterFieldOrderChange];
}

- (void)fieldCellTextEdited:(id)sender {
    if (![sender isKindOfClass:[NSTextField class]]) return;
    NSTextField *tf = (NSTextField *)sender;
    NSInteger row = tf.tag;
    NSString *ident = tf.identifier;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count || ident.length == 0) return;
    BrowserScraperField *f = self.draft.fields[row];
    NSString *value = tf.stringValue ?: @"";
    if ([ident isEqualToString:@"name"]) {
        f.name = value;
        [self refreshPreviewAfterFieldOrderChange];
    } else if ([ident isEqualToString:@"kind"]) {
        f.kind = [BrowserScraperField kindFromString:value];
    } else if ([ident isEqualToString:@"path"]) {
        f.path = value;
    }
}

- (nullable NSView *)fieldsViewForTable:(NSTableView *)tableView
                            tableColumn:(NSTableColumn *)tableColumn
                                    row:(NSInteger)row {
    if (tableView != self.fieldsTable) return nil;
    if (row < 0 || row >= (NSInteger)self.draft.fields.count) return nil;
    NSString *ident = tableColumn.identifier;
    BrowserScraperField *f = self.draft.fields[row];

    if ([ident isEqualToString:@"ops"]) {
        NSView *view = [tableView makeViewWithIdentifier:@"fieldOps" owner:self];
        if (!view) {
            view = [self makeFieldOpsCellView];
        }
        [self configureFieldOpsCellView:view forRow:row];
        return view;
    }

    if ([ident isEqualToString:@"enabled"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"fieldEnabled" owner:self];
        if (!cell) cell = [self makeFieldsEnabledCellView];
        NSButton *check = [self fieldsEnabledCheckboxInCell:cell];
        if (check) {
            check.tag = row;
            check.state = f.enabled ? NSControlStateValueOn : NSControlStateValueOff;
        }
        return cell;
    }

    BOOL editable = [ident isEqualToString:@"name"] || [ident isEqualToString:@"kind"] || [ident isEqualToString:@"path"];
    NSString *reuseID = [NSString stringWithFormat:@"field.%@.%@", ident, editable ? @"edit" : @"label"];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:reuseID owner:self];
    if (!cell) {
        cell = [self makeFieldsTextCellView:reuseID editable:editable];
    }

    NSString *value = @"";
    if ([ident isEqualToString:@"index"]) {
        value = [NSString stringWithFormat:@"%ld", (long)(row + 1)];
    } else if ([ident isEqualToString:@"name"]) {
        value = f.name ?: @"";
    } else if ([ident isEqualToString:@"kind"]) {
        value = [BrowserScraperField stringFromKind:f.kind] ?: @"";
    } else if ([ident isEqualToString:@"path"]) {
        value = f.path ?: @"";
    } else if ([ident isEqualToString:@"transforms"]) {
        NSString *sum = [BrowserScraperValueTransform summaryForTransforms:f.transforms];
        value = sum.length ? sum : @"—";
    }
    cell.textField.stringValue = value;
    cell.textField.tag = row;
    cell.textField.identifier = ident;
    return cell;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.candidatesTable) return;
    if ([tableColumn.identifier isEqualToString:@"preview"]) {
        if ([cell isKindOfClass:[NSButtonCell class]]) {
            NSButtonCell *btn = (NSButtonCell *)cell;
            NSImage *eye = [self symbolNamed:@"eye"];
            if (eye) {
                btn.image = eye;
                btn.title = @"";
                btn.imagePosition = NSImageOnly;
            } else {
                btn.title = @"◎";
                btn.image = nil;
                btn.imagePosition = NSNoImage;
            }
        }
        return;
    }
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    BOOL missing = [self.missingCandidateIndexes containsObject:@(row)];
    ((NSTextFieldCell *)cell).textColor = missing ? NSColor.tertiaryLabelColor : NSColor.labelColor;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView != self.candidatesTable) return;
    if (self.suppressCandidateSelectionSync) return;
    NSInteger row = self.candidatesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.candidates.count) return;
    if (self.candidateOverlayVisible) {
        [self refreshCandidateOverlaySelectingIndex:row];
    }
}

@end

@implementation BrowserScraperFieldsTableDelegate

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    return [self.owner fieldsViewForTable:tableView tableColumn:tableColumn row:row];
}

@end
