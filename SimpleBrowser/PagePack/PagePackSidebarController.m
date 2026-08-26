#import "PagePackSidebarController.h"
#import "PagePackModels.h"
#import "PagePackStore.h"
#import "PagePackMatcher.h"
#import "PagePackInjector.h"
#import "PagePackSettings.h"
#import "SBTextField.h"
#import "SBTextView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kResizeHandleWidth = 8.0;
static const CGFloat kPackRowHeight = 52.0;

typedef NS_ENUM(NSInteger, PagePackSidebarScope) {
    PagePackSidebarScopePage = 0,
    PagePackSidebarScopeAll = 1,
    PagePackSidebarScopeDiscover = 2,
};

@interface PagePackSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation PagePackSidebarResizeView
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

@interface PagePackSidebarBackgroundView : NSView
@property (nonatomic, copy, nullable) void (^onAppearanceChange)(void);
@end
@implementation PagePackSidebarBackgroundView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onAppearanceChange) {
        self.onAppearanceChange();
    }
}
@end

@interface PagePackRowCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSSwitch *enableSwitch;
@property (nonatomic, copy, nullable) void (^onToggle)(BOOL on);
@end

@implementation PagePackRowCellView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [NSFont systemFontOfSize:11];
        _subtitleLabel.textColor = [NSColor secondaryLabelColor];
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        _enableSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
        _enableSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        _enableSwitch.target = self;
        _enableSwitch.action = @selector(switchChanged:);
        [self addSubview:_enableSwitch];

        [NSLayoutConstraint activateConstraints:@[
            [_enableSwitch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_enableSwitch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_enableSwitch.leadingAnchor constant:-8],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_enableSwitch.leadingAnchor constant:-8],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        ]];
    }
    return self;
}

- (void)switchChanged:(NSSwitch *)sender {
    if (self.onToggle) {
        self.onToggle(sender.state == NSControlStateValueOn);
    }
}
@end

@interface PagePackSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *browseContainer;
@property (nonatomic, strong) NSView *editContainer;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *badgeLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSSegmentedControl *scopeControl;
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSScrollView *listScroll;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSView *emptyContainer;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyDetailLabel;
@property (nonatomic, strong) NSButton *createButton;
@property (nonatomic, strong) NSView *discoverPlaceholder;
@property (nonatomic, strong) PagePackSidebarResizeView *resizeHandle;
@property (nonatomic, strong) NSView *edgeSeparator;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;

@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSTextField *editTitleLabel;
@property (nonatomic, strong) NSSwitch *editEnableSwitch;
@property (nonatomic, strong) SBTextField *nameField;
@property (nonatomic, strong) SBTextField *matchesField;
@property (nonatomic, strong) SBTextField *excludesField;
@property (nonatomic, strong) NSSegmentedControl *fileTabs;
@property (nonatomic, strong) NSButton *addFileButton;
@property (nonatomic, strong) NSButton *deleteFileButton;
@property (nonatomic, strong) NSScrollView *editorScroll;
@property (nonatomic, strong) SBTextView *editorView;
@property (nonatomic, strong) NSTextField *dirtyLabel;
@property (nonatomic, strong) NSButton *discardButton;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *reloadPageButton;
@property (nonatomic, strong) NSButton *deletePackButton;
@property (nonatomic, strong) NSPopUpButton *runAtPopup;

@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) PagePackSidebarScope scope;
@property (nonatomic, copy) NSArray<PagePack *> *listedPacks;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong, nullable) PagePack *editingPack;
@property (nonatomic, copy, nullable) NSString *editingFileName;
@property (nonatomic, assign) BOOL editorDirty;
@property (nonatomic, strong, nullable) id storeObserver;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, assign) BOOL loadingEditor;
@end

@implementation PagePackSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _visible = NO;
        _currentWidth = [PagePackSettings sharedSettings].sidebarWidth;
        _listedPacks = @[];
        _query = @"";
        _scope = PagePackSidebarScopePage;
        [self buildUI];
        __weak typeof(self) weakSelf = self;
        _storeObserver =
            [[NSNotificationCenter defaultCenter]
                addObserverForName:PagePackStoreDidChangeNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
                if (weakSelf.visible) {
                    [weakSelf reloadForCurrentURL];
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

- (nullable NSImage *)symbolNamed:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return image ? [image imageWithSymbolConfiguration:config] : nil;
    }
    return nil;
}

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;

    PagePackSidebarBackgroundView *background = [[PagePackSidebarBackgroundView alloc] initWithFrame:NSZeroRect];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.wantsLayer = YES;
    __weak typeof(self) weakSelf = self;
    background.onAppearanceChange = ^{
        [weakSelf applyChromeColors];
    };
    [root addSubview:background];

    NSView *browse = [[NSView alloc] initWithFrame:NSZeroRect];
    browse.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *edit = [[NSView alloc] initWithFrame:NSZeroRect];
    edit.translatesAutoresizingMaskIntoConstraints = NO;
    edit.hidden = YES;
    [background addSubview:browse];
    [background addSubview:edit];

    // Browse header
    NSTextField *title = [NSTextField labelWithString:@"页面插件"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    NSTextField *badge = [NSTextField labelWithString:@"本页生效 · 0"];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.font = [NSFont systemFontOfSize:11];
    badge.textColor = [NSColor tertiaryLabelColor];

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

    NSSegmentedControl *scope = [NSSegmentedControl segmentedControlWithLabels:@[@"本页", @"全部", @"发现"]
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:@selector(scopeChanged:)];
    scope.translatesAutoresizingMaskIntoConstraints = NO;
    scope.selectedSegment = 0;

    SBTextField *search = [SBTextField standardField];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.placeholderString = @"搜索名称…";
    search.delegate = self;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.backgroundColor = [NSColor clearColor];
    table.rowHeight = kPackRowHeight;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    if (@available(macOS 11.0, *)) {
        table.style = NSTableViewStylePlain;
    }
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"pack"];
    [table addTableColumn:col];
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.action = @selector(tableClicked:);
    scroll.documentView = table;

    NSView *empty = [[NSView alloc] initWithFrame:NSZeroRect];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *emptyTitle = [NSTextField wrappingLabelWithString:@"当前页没有页面插件"];
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    emptyTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;
    NSTextField *emptyDetail = [NSTextField wrappingLabelWithString:@"新建一个，默认只作用于本站。"];
    emptyDetail.translatesAutoresizingMaskIntoConstraints = NO;
    emptyDetail.font = [NSFont systemFontOfSize:12];
    emptyDetail.textColor = [NSColor tertiaryLabelColor];
    emptyDetail.alignment = NSTextAlignmentCenter;
    emptyDetail.preferredMaxLayoutWidth = 240;
    [empty addSubview:emptyTitle];
    [empty addSubview:emptyDetail];

    NSView *discover = [[NSView alloc] initWithFrame:NSZeroRect];
    discover.translatesAutoresizingMaskIntoConstraints = NO;
    discover.hidden = YES;
    NSTextField *discoverLabel = [NSTextField wrappingLabelWithString:@"远程插件目录即将支持。\n当前可新建本地插件，完全自定义 CSS / JS。"];
    discoverLabel.translatesAutoresizingMaskIntoConstraints = NO;
    discoverLabel.font = [NSFont systemFontOfSize:13];
    discoverLabel.textColor = [NSColor secondaryLabelColor];
    discoverLabel.alignment = NSTextAlignmentCenter;
    discoverLabel.preferredMaxLayoutWidth = 260;
    [discover addSubview:discoverLabel];

    NSButton *create = [NSButton buttonWithTitle:@"＋ 新建插件" target:self action:@selector(createClicked:)];
    create.translatesAutoresizingMaskIntoConstraints = NO;
    create.bezelStyle = NSBezelStyleRounded;

    [browse addSubview:title];
    [browse addSubview:badge];
    [browse addSubview:close];
    [browse addSubview:scope];
    [browse addSubview:search];
    [browse addSubview:scroll];
    [browse addSubview:empty];
    [browse addSubview:discover];
    [browse addSubview:create];

    // Edit UI
    NSButton *back = [NSButton buttonWithTitle:@"←" target:self action:@selector(backClicked:)];
    back.translatesAutoresizingMaskIntoConstraints = NO;
    back.bezelStyle = NSBezelStyleInline;
    back.bordered = NO;
    back.toolTip = @"返回列表";

    NSTextField *editTitle = [NSTextField labelWithString:@""];
    editTitle.translatesAutoresizingMaskIntoConstraints = NO;
    editTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    editTitle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSSwitch *editSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    editSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    editSwitch.target = self;
    editSwitch.action = @selector(editEnableChanged:);

    SBTextField *nameField = [SBTextField standardField];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.placeholderString = @"插件名称（可选）";
    nameField.delegate = self;

    SBTextField *matches = [SBTextField standardField];
    matches.translatesAutoresizingMaskIntoConstraints = NO;
    matches.placeholderString = @"匹配规则（逗号分隔）";
    matches.delegate = self;

    SBTextField *excludes = [SBTextField standardField];
    excludes.translatesAutoresizingMaskIntoConstraints = NO;
    excludes.placeholderString = @"排除规则（可选）";
    excludes.delegate = self;

    NSPopUpButton *runAt = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    runAt.translatesAutoresizingMaskIntoConstraints = NO;
    [runAt addItemsWithTitles:@[@"document-start", @"document-end", @"document-idle"]];
    runAt.target = self;
    runAt.action = @selector(runAtChanged:);

    NSSegmentedControl *tabs = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    tabs.segmentStyle = NSSegmentStyleRounded;
    tabs.trackingMode = NSSegmentSwitchTrackingSelectOne;
    tabs.target = self;
    tabs.action = @selector(fileTabChanged:);

    NSButton *addFile = [NSButton buttonWithTitle:@"＋" target:self action:@selector(addFileClicked:)];
    addFile.translatesAutoresizingMaskIntoConstraints = NO;
    addFile.bezelStyle = NSBezelStyleInline;
    addFile.toolTip = @"新增文件";

    NSButton *deleteFile = [NSButton buttonWithTitle:@"删文件" target:self action:@selector(deleteFileClicked:)];
    deleteFile.translatesAutoresizingMaskIntoConstraints = NO;
    deleteFile.bezelStyle = NSBezelStyleInline;

    NSScrollView *editorScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    editorScroll.translatesAutoresizingMaskIntoConstraints = NO;
    editorScroll.hasVerticalScroller = YES;
    editorScroll.hasHorizontalScroller = YES;
    editorScroll.autohidesScrollers = YES;
    editorScroll.borderType = NSBezelBorder;
    SBTextView *editor = [SBTextView standardTextView];
    editor.delegate = self;
    editor.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    editor.automaticQuoteSubstitutionEnabled = NO;
    editor.automaticDashSubstitutionEnabled = NO;
    editor.richText = NO;
    editor.minSize = NSMakeSize(0, 0);
    editor.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    editor.verticallyResizable = YES;
    editor.horizontallyResizable = YES;
    editor.autoresizingMask = NSViewWidthSizable;
    editor.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    editor.textContainer.widthTracksTextView = NO;
    editorScroll.documentView = editor;

    NSTextField *dirty = [NSTextField labelWithString:@""];
    dirty.translatesAutoresizingMaskIntoConstraints = NO;
    dirty.font = [NSFont systemFontOfSize:11];
    dirty.textColor = [NSColor systemOrangeColor];

    NSButton *discard = [NSButton buttonWithTitle:@"丢弃" target:self action:@selector(discardClicked:)];
    discard.translatesAutoresizingMaskIntoConstraints = NO;
    discard.bezelStyle = NSBezelStyleRounded;

    NSButton *save = [NSButton buttonWithTitle:@"保存" target:self action:@selector(saveClicked:)];
    save.translatesAutoresizingMaskIntoConstraints = NO;
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"s";
    save.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    NSButton *reloadPage = [NSButton buttonWithTitle:@"在页面中刷新" target:self action:@selector(reloadPageClicked:)];
    reloadPage.translatesAutoresizingMaskIntoConstraints = NO;
    reloadPage.bezelStyle = NSBezelStyleInline;

    NSButton *deletePack = [NSButton buttonWithTitle:@"删除插件" target:self action:@selector(deletePackClicked:)];
    deletePack.translatesAutoresizingMaskIntoConstraints = NO;
    deletePack.bezelStyle = NSBezelStyleInline;
    if (@available(macOS 10.14, *)) {
        deletePack.contentTintColor = [NSColor systemRedColor];
    }

    [edit addSubview:back];
    [edit addSubview:editTitle];
    [edit addSubview:editSwitch];
    [edit addSubview:nameField];
    [edit addSubview:matches];
    [edit addSubview:excludes];
    [edit addSubview:runAt];
    [edit addSubview:tabs];
    [edit addSubview:addFile];
    [edit addSubview:deleteFile];
    [edit addSubview:editorScroll];
    [edit addSubview:dirty];
    [edit addSubview:discard];
    [edit addSubview:save];
    [edit addSubview:reloadPage];
    [edit addSubview:deletePack];

    PagePackSidebarResizeView *handle = [[PagePackSidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
    };
    handle.onDragToOffset = ^(CGFloat delta) {
        [weakSelf applyWidth:weakSelf.dragStartWidth - delta];
    };
    handle.onDragEnded = ^{
        [PagePackSettings sharedSettings].sidebarWidth = weakSelf.currentWidth;
        if ([weakSelf.delegate respondsToSelector:@selector(pagePackSidebar:didChangeWidth:)]) {
            [weakSelf.delegate pagePackSidebar:weakSelf didChangeWidth:weakSelf.currentWidth];
        }
    };

    NSView *edge = [[NSView alloc] initWithFrame:NSZeroRect];
    edge.translatesAutoresizingMaskIntoConstraints = NO;
    edge.wantsLayer = YES;
    [root addSubview:handle];
    [root addSubview:edge];

    self.view = root;
    self.backgroundView = background;
    self.browseContainer = browse;
    self.editContainer = edit;
    self.titleLabel = title;
    self.badgeLabel = badge;
    self.closeButton = close;
    self.scopeControl = scope;
    self.searchField = search;
    self.listScroll = scroll;
    self.tableView = table;
    self.emptyContainer = empty;
    self.emptyTitleLabel = emptyTitle;
    self.emptyDetailLabel = emptyDetail;
    self.createButton = create;
    self.discoverPlaceholder = discover;
    self.resizeHandle = handle;
    self.edgeSeparator = edge;

    self.backButton = back;
    self.editTitleLabel = editTitle;
    self.editEnableSwitch = editSwitch;
    self.nameField = nameField;
    self.matchesField = matches;
    self.excludesField = excludes;
    self.fileTabs = tabs;
    self.addFileButton = addFile;
    self.deleteFileButton = deleteFile;
    self.editorScroll = editorScroll;
    self.editorView = editor;
    self.dirtyLabel = dirty;
    self.discardButton = discard;
    self.saveButton = save;
    self.reloadPageButton = reloadPage;
    self.deletePackButton = deletePack;
    self.runAtPopup = runAt;

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:root.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [browse.topAnchor constraintEqualToAnchor:background.topAnchor],
        [browse.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [browse.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [browse.bottomAnchor constraintEqualToAnchor:background.bottomAnchor],
        [edit.topAnchor constraintEqualToAnchor:background.topAnchor],
        [edit.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [edit.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [edit.bottomAnchor constraintEqualToAnchor:background.bottomAnchor],

        [title.leadingAnchor constraintEqualToAnchor:browse.leadingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:browse.topAnchor constant:12],
        [badge.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [badge.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [close.trailingAnchor constraintEqualToAnchor:browse.trailingAnchor constant:-8],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],

        [scope.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:10],
        [scope.leadingAnchor constraintEqualToAnchor:browse.leadingAnchor constant:12],
        [scope.trailingAnchor constraintEqualToAnchor:browse.trailingAnchor constant:-12],
        [search.topAnchor constraintEqualToAnchor:scope.bottomAnchor constant:8],
        [search.leadingAnchor constraintEqualToAnchor:scope.leadingAnchor],
        [search.trailingAnchor constraintEqualToAnchor:scope.trailingAnchor],
        [search.heightAnchor constraintEqualToConstant:22],

        [create.leadingAnchor constraintEqualToAnchor:browse.leadingAnchor constant:12],
        [create.trailingAnchor constraintEqualToAnchor:browse.trailingAnchor constant:-12],
        [create.bottomAnchor constraintEqualToAnchor:browse.bottomAnchor constant:-12],
        [create.heightAnchor constraintEqualToConstant:28],

        [scroll.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:browse.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:browse.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:create.topAnchor constant:-8],

        [empty.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [empty.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],
        [emptyTitle.topAnchor constraintEqualToAnchor:empty.topAnchor],
        [emptyTitle.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor],
        [emptyTitle.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor],
        [emptyDetail.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:6],
        [emptyDetail.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor],
        [emptyDetail.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor],
        [emptyDetail.bottomAnchor constraintEqualToAnchor:empty.bottomAnchor],

        [discover.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [discover.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],
        [discoverLabel.topAnchor constraintEqualToAnchor:discover.topAnchor],
        [discoverLabel.leadingAnchor constraintEqualToAnchor:discover.leadingAnchor],
        [discoverLabel.trailingAnchor constraintEqualToAnchor:discover.trailingAnchor],
        [discoverLabel.bottomAnchor constraintEqualToAnchor:discover.bottomAnchor],

        [back.leadingAnchor constraintEqualToAnchor:edit.leadingAnchor constant:8],
        [back.topAnchor constraintEqualToAnchor:edit.topAnchor constant:10],
        [editTitle.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:4],
        [editTitle.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],
        [editTitle.trailingAnchor constraintLessThanOrEqualToAnchor:editSwitch.leadingAnchor constant:-8],
        [editSwitch.trailingAnchor constraintEqualToAnchor:edit.trailingAnchor constant:-12],
        [editSwitch.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],

        [nameField.topAnchor constraintEqualToAnchor:back.bottomAnchor constant:10],
        [nameField.leadingAnchor constraintEqualToAnchor:edit.leadingAnchor constant:12],
        [nameField.trailingAnchor constraintEqualToAnchor:edit.trailingAnchor constant:-12],
        [nameField.heightAnchor constraintEqualToConstant:22],
        [matches.topAnchor constraintEqualToAnchor:nameField.bottomAnchor constant:6],
        [matches.leadingAnchor constraintEqualToAnchor:nameField.leadingAnchor],
        [matches.trailingAnchor constraintEqualToAnchor:nameField.trailingAnchor],
        [matches.heightAnchor constraintEqualToConstant:22],
        [excludes.topAnchor constraintEqualToAnchor:matches.bottomAnchor constant:6],
        [excludes.leadingAnchor constraintEqualToAnchor:matches.leadingAnchor],
        [excludes.trailingAnchor constraintEqualToAnchor:matches.trailingAnchor],
        [excludes.heightAnchor constraintEqualToConstant:22],
        [runAt.topAnchor constraintEqualToAnchor:excludes.bottomAnchor constant:6],
        [runAt.leadingAnchor constraintEqualToAnchor:matches.leadingAnchor],
        [runAt.widthAnchor constraintEqualToConstant:160],

        [tabs.topAnchor constraintEqualToAnchor:runAt.bottomAnchor constant:8],
        [tabs.leadingAnchor constraintEqualToAnchor:matches.leadingAnchor],
        [tabs.trailingAnchor constraintLessThanOrEqualToAnchor:addFile.leadingAnchor constant:-4],
        [addFile.trailingAnchor constraintEqualToAnchor:deleteFile.leadingAnchor constant:-4],
        [addFile.centerYAnchor constraintEqualToAnchor:tabs.centerYAnchor],
        [deleteFile.trailingAnchor constraintEqualToAnchor:edit.trailingAnchor constant:-12],
        [deleteFile.centerYAnchor constraintEqualToAnchor:tabs.centerYAnchor],

        [editorScroll.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:8],
        [editorScroll.leadingAnchor constraintEqualToAnchor:edit.leadingAnchor constant:12],
        [editorScroll.trailingAnchor constraintEqualToAnchor:edit.trailingAnchor constant:-12],
        [editorScroll.bottomAnchor constraintEqualToAnchor:dirty.topAnchor constant:-8],

        [dirty.leadingAnchor constraintEqualToAnchor:editorScroll.leadingAnchor],
        [dirty.bottomAnchor constraintEqualToAnchor:save.topAnchor constant:-6],
        [discard.trailingAnchor constraintEqualToAnchor:save.leadingAnchor constant:-8],
        [discard.bottomAnchor constraintEqualToAnchor:edit.bottomAnchor constant:-12],
        [save.trailingAnchor constraintEqualToAnchor:edit.trailingAnchor constant:-12],
        [save.bottomAnchor constraintEqualToAnchor:edit.bottomAnchor constant:-12],
        [reloadPage.leadingAnchor constraintEqualToAnchor:editorScroll.leadingAnchor],
        [reloadPage.centerYAnchor constraintEqualToAnchor:save.centerYAnchor],
        [deletePack.leadingAnchor constraintEqualToAnchor:reloadPage.trailingAnchor constant:8],
        [deletePack.centerYAnchor constraintEqualToAnchor:save.centerYAnchor],

        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],
        [edge.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [edge.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edge.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edge.widthAnchor constraintEqualToConstant:1],
    ]];

    [self applyChromeColors];
    [self showBrowseMode];
}

- (void)applyChromeColors {
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
    self.edgeSeparator.layer.backgroundColor = [NSColor separatorColor].CGColor;
}

#pragma mark - Visibility

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    BOOL already = (self.visible == visible);
    if (already && visible && self.widthConstraint.constant > 1) {
        [self reloadForCurrentURL];
        return;
    }
    if (already && !visible && self.widthConstraint.constant < 1) {
        return;
    }
    self.visible = visible;
    if (visible) {
        self.currentWidth = [PagePackSettings sharedSettings].sidebarWidth;
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
            [self reloadForCurrentURL];
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
    CGFloat clamped = MIN(MAX(width, kSidebarMinWidth), kSidebarMaxWidth);
    self.currentWidth = clamped;
    if (self.visible) {
        self.widthConstraint.constant = clamped;
    }
}

#pragma mark - Data

- (NSURL *)currentURL {
    if ([self.delegate respondsToSelector:@selector(pagePackSidebarCurrentURL:)]) {
        return [self.delegate pagePackSidebarCurrentURL:self];
    }
    return nil;
}

- (WKWebView *)currentWebView {
    if ([self.delegate respondsToSelector:@selector(pagePackSidebarCurrentWebView:)]) {
        return [self.delegate pagePackSidebarCurrentWebView:self];
    }
    return nil;
}

- (void)reloadForCurrentURL {
    // 跟磁盘对齐，但不发 DidChange：观察者也会调本方法，发通知会无限重入至栈溢出。
    [[PagePackStore sharedStore] syncFromDisk];
    NSURL *url = [self currentURL];
    NSArray<PagePack *> *enabledMatched = [[PagePackStore sharedStore] enabledPacksMatchingURL:url];
    self.badgeLabel.stringValue = [NSString stringWithFormat:@"本页生效 · %lu", (unsigned long)enabledMatched.count];

    if (self.editingPack) {
        PagePack *fresh = [[PagePackStore sharedStore] packWithID:self.editingPack.packID];
        if (fresh) {
            self.editingPack = fresh;
            [self refreshEditChrome];
        } else {
            [self showBrowseMode];
        }
    }

    if (self.scope == PagePackSidebarScopeDiscover) {
        self.listedPacks = @[];
        self.listScroll.hidden = YES;
        self.emptyContainer.hidden = YES;
        self.discoverPlaceholder.hidden = NO;
        self.searchField.hidden = YES;
        [self.tableView reloadData];
        return;
    }

    self.discoverPlaceholder.hidden = YES;
    self.searchField.hidden = NO;
    self.listScroll.hidden = NO;

    NSArray<PagePack *> *source = (self.scope == PagePackSidebarScopePage)
        ? [[PagePackStore sharedStore] packsMatchingURL:url]
        : [[PagePackStore sharedStore] allPacks];

    NSString *q = self.query.lowercaseString;
    if (q.length > 0) {
        NSMutableArray<PagePack *> *filtered = [NSMutableArray array];
        for (PagePack *pack in source) {
            if ([pack.name.lowercaseString containsString:q] || [pack.matchSummary.lowercaseString containsString:q]) {
                [filtered addObject:pack];
            }
        }
        source = filtered;
    }
    self.listedPacks = source;
    self.emptyContainer.hidden = source.count > 0;
    if (self.scope == PagePackSidebarScopePage) {
        self.emptyTitleLabel.stringValue = @"当前页没有页面插件";
        self.emptyDetailLabel.stringValue = @"新建一个，默认只作用于本站。";
    } else {
        self.emptyTitleLabel.stringValue = @"还没有本地插件";
        self.emptyDetailLabel.stringValue = @"点击下方新建，或稍后再从「发现」安装。";
    }
    [self.tableView reloadData];
}

- (void)revealPackID:(NSString *)packID {
    if (packID.length == 0) {
        return;
    }
    PagePack *pack = [[PagePackStore sharedStore] packWithID:packID];
    if (pack) {
        [self openEditorForPack:pack];
    }
}

#pragma mark - Modes

- (void)showBrowseMode {
    self.editingPack = nil;
    self.editingFileName = nil;
    self.editorDirty = NO;
    self.browseContainer.hidden = NO;
    self.editContainer.hidden = YES;
    [self reloadForCurrentURL];
}

- (void)openEditorForPack:(PagePack *)pack {
    if (self.editorDirty && ![self confirmDiscardIfNeeded]) {
        return;
    }
    self.editingPack = pack;
    self.browseContainer.hidden = YES;
    self.editContainer.hidden = NO;
    [self refreshEditChrome];
    PagePackFile *first = pack.files.firstObject;
    [self selectFileNamed:first.name];
}

- (void)refreshEditChrome {
    PagePack *pack = self.editingPack;
    if (!pack) {
        return;
    }
    NSString *fallback = [self defaultPackDisplayName];
    self.nameField.placeholderString = [NSString stringWithFormat:@"可选，默认：%@", fallback];
    // 若当前名称就是默认「网址 + 插件」，输入框留空以体现「非必填」；自定义名则回填。
    if (pack.name.length > 0 && ![pack.name isEqualToString:fallback]) {
        self.nameField.stringValue = pack.name;
    } else {
        self.nameField.stringValue = @"";
    }
    self.editTitleLabel.stringValue = [self resolvedPackDisplayName];
    self.editEnableSwitch.state = pack.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.matchesField.stringValue = [pack.matches componentsJoinedByString:@", "];
    self.excludesField.stringValue = [pack.excludes componentsJoinedByString:@", "];
    [self.fileTabs setSegmentCount:pack.files.count];
    NSInteger selected = 0;
    for (NSInteger i = 0; i < (NSInteger)pack.files.count; i++) {
        [self.fileTabs setLabel:pack.files[i].name forSegment:i];
        if ([pack.files[i].name isEqualToString:self.editingFileName]) {
            selected = i;
        }
    }
    if (pack.files.count > 0) {
        self.fileTabs.selectedSegment = selected;
    }
    [self updateDirtyLabel];
}

- (NSString *)defaultPackDisplayName {
    NSURL *url = [self currentURL];
    if (url.host.length > 0) {
        return [NSString stringWithFormat:@"%@ 插件", url.host];
    }
    // 无当前页时，尝试从第一条 match 解析 host
    NSString *firstMatch = self.editingPack.matches.firstObject;
    if (firstMatch.length == 0) {
        firstMatch = [[self patternsFromField:self.matchesField.stringValue] firstObject];
    }
    if (firstMatch.length > 0) {
        NSRange schemeSep = [firstMatch rangeOfString:@"://"];
        if (schemeSep.location != NSNotFound) {
            NSString *rest = [firstMatch substringFromIndex:schemeSep.location + schemeSep.length];
            NSRange slash = [rest rangeOfString:@"/"];
            NSString *hostPart = (slash.location == NSNotFound) ? rest : [rest substringToIndex:slash.location];
            // 去掉可能的端口与 *. 前缀
            NSRange colon = [hostPart rangeOfString:@":"];
            if (colon.location != NSNotFound) {
                hostPart = [hostPart substringToIndex:colon.location];
            }
            if ([hostPart hasPrefix:@"*."]) {
                hostPart = [hostPart substringFromIndex:2];
            }
            if (hostPart.length > 0 && ![hostPart isEqualToString:@"*"]) {
                return [NSString stringWithFormat:@"%@ 插件", hostPart];
            }
        }
    }
    return @"新页面插件";
}

- (NSString *)resolvedPackDisplayName {
    NSString *custom = [self.nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (custom.length > 0) {
        return custom;
    }
    return [self defaultPackDisplayName];
}

- (void)selectFileNamed:(NSString *)name {
    if (!self.editingPack || name.length == 0) {
        return;
    }
    if (self.editorDirty && self.editingFileName.length > 0 && ![self.editingFileName isEqualToString:name]) {
        if (![self confirmDiscardIfNeeded]) {
            [self refreshEditChrome];
            return;
        }
    }
    self.loadingEditor = YES;
    self.editingFileName = name;
    NSError *error = nil;
    NSString *content = [[PagePackStore sharedStore] contentOfFile:name inPack:self.editingPack.packID error:&error] ?: @"";
    self.editorView.string = content;
    self.editorDirty = NO;
    self.loadingEditor = NO;
    PagePackFile *file = [self.editingPack fileNamed:name];
    self.runAtPopup.enabled = (file.kind == PagePackFileKindJS);
    if (file) {
        switch (file.runAt) {
            case PagePackRunAtDocumentStart: [self.runAtPopup selectItemAtIndex:0]; break;
            case PagePackRunAtDocumentIdle: [self.runAtPopup selectItemAtIndex:2]; break;
            case PagePackRunAtDocumentEnd:
            default: [self.runAtPopup selectItemAtIndex:1]; break;
        }
    }
    [self refreshEditChrome];
}

- (void)updateDirtyLabel {
    self.dirtyLabel.stringValue = self.editorDirty ? @"未保存的更改" : @"";
    self.discardButton.enabled = self.editorDirty;
    self.saveButton.enabled = self.editorDirty || YES;
}

- (BOOL)confirmDiscardIfNeeded {
    if (!self.editorDirty) {
        return YES;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"丢弃未保存的更改？";
    alert.informativeText = @"当前文件有未保存修改。";
    [alert addButtonWithTitle:@"丢弃"];
    [alert addButtonWithTitle:@"取消"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    if (self.editorDirty && ![self confirmDiscardIfNeeded]) {
        return;
    }
    [self.delegate pagePackSidebarDidRequestClose:self];
}

- (void)scopeChanged:(NSSegmentedControl *)sender {
    self.scope = (PagePackSidebarScope)sender.selectedSegment;
    [self reloadForCurrentURL];
}

- (void)createClicked:(id)sender {
    (void)sender;
    NSError *error = nil;
    PagePack *pack = [[PagePackStore sharedStore] createPackForURL:[self currentURL] name:nil error:&error];
    if (!pack) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"创建失败";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
        return;
    }
    [self openEditorForPack:pack];
}

- (void)backClicked:(id)sender {
    (void)sender;
    if (self.editorDirty && ![self confirmDiscardIfNeeded]) {
        return;
    }
    [self showBrowseMode];
}

- (void)tableClicked:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)self.listedPacks.count) {
        return;
    }
    // Ignore clicks on switch (handled separately); open editor for row body.
    [self openEditorForPack:self.listedPacks[row]];
}

- (void)editEnableChanged:(NSSwitch *)sender {
    if (!self.editingPack) {
        return;
    }
    BOOL on = sender.state == NSControlStateValueOn;
    if (on && self.editingPack.hasDangerousMatch) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"此插件匹配所有网站";
        alert.informativeText = @"启用后将对几乎所有页面注入脚本/样式。确定继续？";
        [alert addButtonWithTitle:@"启用"];
        [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            sender.state = NSControlStateValueOff;
            return;
        }
    }
    NSError *error = nil;
    [[PagePackStore sharedStore] setPack:self.editingPack.packID enabled:on error:&error];
    WKWebView *webView = [self currentWebView];
    NSURL *url = [self currentURL];
    if (webView) {
        if (on) {
            PagePack *pack = [[PagePackStore sharedStore] packWithID:self.editingPack.packID];
            if (pack) {
                [[PagePackInjector sharedInjector] hotApplyPack:pack toWebView:webView URL:url];
            }
        } else {
            [[PagePackInjector sharedInjector] removeCSSForPackID:self.editingPack.packID fromWebView:webView];
        }
    }
}

- (void)runAtChanged:(NSPopUpButton *)sender {
    if (!self.editingPack || self.editingFileName.length == 0) {
        return;
    }
    PagePack *pack = [self.editingPack copy];
    PagePackFile *file = [pack fileNamed:self.editingFileName];
    if (!file || file.kind != PagePackFileKindJS) {
        return;
    }
    NSInteger idx = sender.indexOfSelectedItem;
    if (idx == 0) {
        file.runAt = PagePackRunAtDocumentStart;
    } else if (idx == 2) {
        file.runAt = PagePackRunAtDocumentIdle;
    } else {
        file.runAt = PagePackRunAtDocumentEnd;
    }
    NSMutableArray *files = [NSMutableArray array];
    for (PagePackFile *f in pack.files) {
        [files addObject:[f.name isEqualToString:file.name] ? file : f];
    }
    pack.files = files;
    [[PagePackStore sharedStore] upsertPack:pack error:nil];
    self.editingPack = [[PagePackStore sharedStore] packWithID:pack.packID];
}

- (void)fileTabChanged:(NSSegmentedControl *)sender {
    NSInteger idx = sender.selectedSegment;
    if (!self.editingPack || idx < 0 || idx >= (NSInteger)self.editingPack.files.count) {
        return;
    }
    [self selectFileNamed:self.editingPack.files[idx].name];
}

- (void)addFileClicked:(id)sender {
    (void)sender;
    if (!self.editingPack) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"新增文件";
    alert.informativeText = @"输入文件名，如 tweak.js 或 theme.css";
    SBTextField *input = [SBTextField standardField];
    input.frame = NSMakeRect(0, 0, 240, 24);
    input.stringValue = @"tweak.js";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    PagePackFileKind kind = PagePackFileKindJS;
    if (![PagePackFile kindForFileName:name outKind:&kind]) {
        NSAlert *err = [[NSAlert alloc] init];
        err.messageText = @"文件名无效";
        err.informativeText = @"请使用 .css 或 .js 后缀。";
        [err runModal];
        return;
    }
    PagePackFile *file = [PagePackFile fileWithName:name kind:kind];
    if (kind == PagePackFileKindCSS) {
        file.runAt = PagePackRunAtDocumentStart;
    }
    NSError *error = nil;
    if (![[PagePackStore sharedStore] addFile:file toPack:self.editingPack.packID initialContent:@"" error:&error]) {
        NSAlert *err = [[NSAlert alloc] init];
        err.messageText = @"添加失败";
        err.informativeText = error.localizedDescription ?: @"";
        [err runModal];
        return;
    }
    self.editingPack = [[PagePackStore sharedStore] packWithID:self.editingPack.packID];
    [self selectFileNamed:name];
}

- (void)deleteFileClicked:(id)sender {
    (void)sender;
    if (!self.editingPack || self.editingFileName.length == 0) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除此文件？";
    alert.informativeText = self.editingFileName;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    NSError *error = nil;
    if (![[PagePackStore sharedStore] removeFileNamed:self.editingFileName inPack:self.editingPack.packID error:&error]) {
        return;
    }
    self.editorDirty = NO;
    self.editingPack = [[PagePackStore sharedStore] packWithID:self.editingPack.packID];
    PagePackFile *next = self.editingPack.files.firstObject;
    if (next) {
        [self selectFileNamed:next.name];
    } else {
        self.editingFileName = nil;
        self.editorView.string = @"";
        [self refreshEditChrome];
    }
}

- (void)discardClicked:(id)sender {
    (void)sender;
    if (!self.editingPack || self.editingFileName.length == 0) {
        return;
    }
    if (![self confirmDiscardIfNeeded]) {
        return;
    }
    [self selectFileNamed:self.editingFileName];
}

- (void)saveClicked:(id)sender {
    (void)sender;
    [self saveCurrentEditor];
}

- (void)saveCurrentEditor {
    if (!self.editingPack) {
        return;
    }
    NSArray<NSString *> *matches = [self patternsFromField:self.matchesField.stringValue];
    NSArray<NSString *> *excludes = [self patternsFromField:self.excludesField.stringValue];
    if (matches.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"请填写至少一条匹配规则";
        [alert runModal];
        return;
    }
    PagePack *pack = [self.editingPack copy];
    pack.matches = matches;
    pack.excludes = excludes;
    pack.name = [self resolvedPackDisplayName];
    if (pack.hasDangerousMatch) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"匹配规则过于宽泛";
        alert.informativeText = @"包含对所有网站生效的规则。确定保存？";
        [alert addButtonWithTitle:@"保存"];
        [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }
    NSError *error = nil;
    if (![[PagePackStore sharedStore] upsertPack:pack error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"保存元数据失败";
        alert.informativeText = error.localizedDescription ?: @"";
        [alert runModal];
        return;
    }
    if (self.editingFileName.length > 0) {
        if (![[PagePackStore sharedStore] writeContent:self.editorView.string
                                             fileName:self.editingFileName
                                               inPack:pack.packID
                                                error:&error]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"保存文件失败";
            alert.informativeText = error.localizedDescription ?: @"";
            [alert runModal];
            return;
        }
    }
    self.editorDirty = NO;
    self.editingPack = [[PagePackStore sharedStore] packWithID:pack.packID];
    [self updateDirtyLabel];
    [self refreshEditChrome];

    WKWebView *webView = [self currentWebView];
    NSURL *url = [self currentURL];
    if (webView && self.editingPack) {
        [[PagePackInjector sharedInjector] hotApplyPack:self.editingPack toWebView:webView URL:url];
    }
}

- (NSArray<NSString *> *)patternsFromField:(NSString *)text {
    NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]];
    NSMutableArray *patterns = [NSMutableArray array];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [patterns addObject:trimmed];
        }
    }
    return patterns;
}

- (void)reloadPageClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(pagePackSidebarDidRequestReloadPage:)]) {
        [self.delegate pagePackSidebarDidRequestReloadPage:self];
    }
}

- (void)deletePackClicked:(id)sender {
    (void)sender;
    if (!self.editingPack) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除此页面插件？";
    alert.informativeText = self.editingPack.name;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    NSString *packID = self.editingPack.packID;
    WKWebView *webView = [self currentWebView];
    [[PagePackStore sharedStore] deletePackWithID:packID error:nil];
    if (webView) {
        [[PagePackInjector sharedInjector] removeCSSForPackID:packID fromWebView:webView];
    }
    self.editorDirty = NO;
    [self showBrowseMode];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.listedPacks.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    PagePackRowCellView *cell = [tableView makeViewWithIdentifier:@"PagePackRow" owner:self];
    if (!cell) {
        cell = [[PagePackRowCellView alloc] initWithFrame:NSMakeRect(0, 0, 320, kPackRowHeight)];
        cell.identifier = @"PagePackRow";
    }
    if (row < 0 || row >= (NSInteger)self.listedPacks.count) {
        return cell;
    }
    PagePack *pack = self.listedPacks[row];
    cell.titleLabel.stringValue = pack.name ?: @"";
    NSMutableArray *names = [NSMutableArray array];
    for (PagePackFile *file in pack.files) {
        [names addObject:file.name];
    }
    cell.subtitleLabel.stringValue = names.count > 0
        ? [names componentsJoinedByString:@" · "]
        : pack.matchSummary;
    cell.enableSwitch.state = pack.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    __weak typeof(self) weakSelf = self;
    NSString *packID = pack.packID;
    cell.onToggle = ^(BOOL on) {
        [weakSelf setPackID:packID enabled:on];
    };
    return cell;
}

- (void)setPackID:(NSString *)packID enabled:(BOOL)enabled {
    PagePack *pack = [[PagePackStore sharedStore] packWithID:packID];
    if (enabled && pack.hasDangerousMatch) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"此插件匹配所有网站";
        alert.informativeText = @"启用后将对几乎所有页面注入脚本/样式。确定继续？";
        [alert addButtonWithTitle:@"启用"];
        [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            [self reloadForCurrentURL];
            return;
        }
    }
    [[PagePackStore sharedStore] setPack:packID enabled:enabled error:nil];
    WKWebView *webView = [self currentWebView];
    NSURL *url = [self currentURL];
    if (webView) {
        if (enabled) {
            PagePack *fresh = [[PagePackStore sharedStore] packWithID:packID];
            if (fresh) {
                [[PagePackInjector sharedInjector] hotApplyPack:fresh toWebView:webView URL:url];
            }
        } else {
            [[PagePackInjector sharedInjector] removeCSSForPackID:packID fromWebView:webView];
        }
    }
}

#pragma mark - Text

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.searchField) {
        self.query = self.searchField.stringValue ?: @"";
        [self reloadForCurrentURL];
        return;
    }
    if (obj.object == self.nameField) {
        self.editorDirty = YES;
        self.editTitleLabel.stringValue = [self resolvedPackDisplayName];
        [self updateDirtyLabel];
        return;
    }
    if (obj.object == self.matchesField || obj.object == self.excludesField) {
        self.editorDirty = YES;
        if (obj.object == self.matchesField) {
            NSString *fallback = [self defaultPackDisplayName];
            self.nameField.placeholderString = [NSString stringWithFormat:@"可选，默认：%@", fallback];
            if ([self.nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
                self.editTitleLabel.stringValue = fallback;
            }
        }
        [self updateDirtyLabel];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.loadingEditor) {
        return;
    }
    self.editorDirty = YES;
    [self updateDirtyLabel];
}

#pragma mark - Keys

- (void)installKeyMonitor {
    if (self.localKeyMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53) { // Esc
            if (weakSelf.editContainer && !weakSelf.editContainer.hidden) {
                [weakSelf backClicked:nil];
                return nil;
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

@end
