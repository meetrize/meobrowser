#import "PhoneNotificationSidebarController.h"
#import "PhoneNotificationInboxSettings.h"
#import "PhoneNotificationInboxStore.h"
#import "PhoneNotificationItem.h"
#import "CompanionChannel.h"
#import "SBTextField.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kResizeHandleWidth = 8.0;
static const NSTimeInterval kAutoMarkReadDelay = 0.5;
static const NSTimeInterval kSearchDebounce = 0.25;

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

@interface PhoneNotificationSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSSegmentedControl *bucketControl;
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
@property (nonatomic, strong, nullable) dispatch_block_t searchDebounceBlock;
@property (nonatomic, strong, nullable) dispatch_block_t autoMarkReadBlock;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@property (nonatomic, copy, nullable) NSString *pendingRevealItemID;
@property (nonatomic, strong, nullable) NSView *highlightFlashView;
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
    }
    return self;
}

- (void)dealloc {
    [self uninstallKeyMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;

    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    effect.translatesAutoresizingMaskIntoConstraints = NO;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    if (@available(macOS 10.14, *)) {
        effect.material = NSVisualEffectMaterialSidebar;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        effect.material = NSVisualEffectMaterialAppearanceBased;
#pragma clang diagnostic pop
    }
    effect.state = NSVisualEffectStateFollowsWindowActiveState;
    [root addSubview:effect];

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

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.backgroundColor = [NSColor clearColor];
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsEmptySelection = YES;
    table.rowHeight = 56;
    table.intercellSpacing = NSMakeSize(0, 2);
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

    NSView *separator = [[NSView alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor separatorColor].CGColor;

    [effect addSubview:title];
    [effect addSubview:close];
    [effect addSubview:search];
    [effect addSubview:bucket];
    [effect addSubview:scroll];
    [effect addSubview:empty];
    [effect addSubview:markAll];
    [effect addSubview:purge];
    [root addSubview:handle];
    [root addSubview:separator];

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [effect.topAnchor constraintEqualToAnchor:root.topAnchor],
        [effect.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [effect.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [effect.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],

        [separator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [separator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [separator.widthAnchor constraintEqualToConstant:1],

        [title.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:effect.topAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor constant:-10],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],

        [search.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:12],
        [search.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor constant:-12],
        [search.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [search.heightAnchor constraintEqualToConstant:26],

        [bucket.leadingAnchor constraintEqualToAnchor:search.leadingAnchor],
        [bucket.trailingAnchor constraintEqualToAnchor:search.trailingAnchor],
        [bucket.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],

        [scroll.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:bucket.bottomAnchor constant:8],
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

        [markAll.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:12],
        [markAll.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor constant:-10],
        [purge.leadingAnchor constraintEqualToAnchor:markAll.trailingAnchor constant:12],
        [purge.centerYAnchor constraintEqualToAnchor:markAll.centerYAnchor],
    ]];

    self.view = root;
    self.effectView = effect;
    self.titleLabel = title;
    self.closeButton = close;
    self.searchField = search;
    self.bucketControl = bucket;
    self.scrollView = scroll;
    self.tableView = table;
    self.emptyContainer = empty;
    self.emptyTitleLabel = emptyTitle;
    self.emptyDetailLabel = emptyDetail;
    self.emptyActionButton = emptyAction;
    self.markAllReadButton = markAll;
    self.purgeReadButton = purge;
    self.resizeHandle = handle;

    [self reloadList];
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
    NSArray<PhoneNotificationItem *> *items = [[PhoneNotificationInboxStore sharedStore] itemsMatchingFilter:filter];
    self.rows = [self buildRowsFromItems:items];
    [self.tableView reloadData];
    [self refreshEmptyState];
    [self scheduleAutoMarkRead];
}

- (NSArray<PhoneNotificationSidebarRow *> *)buildRowsFromItems:(NSArray<PhoneNotificationItem *> *)items {
    NSMutableArray<PhoneNotificationSidebarRow *> *rows = [NSMutableArray array];
    NSMutableArray<PhoneNotificationItem *> *pinned = [NSMutableArray array];
    NSMutableArray<PhoneNotificationItem *> *rest = [NSMutableArray array];
    for (PhoneNotificationItem *item in items) {
        if (item.pinned && [self selectedBucket] != PhoneNotificationInboxBucketPinned) {
            [pinned addObject:item];
        } else {
            [rest addObject:item];
        }
    }

    if (pinned.count > 0) {
        PhoneNotificationSidebarRow *sec = [[PhoneNotificationSidebarRow alloc] init];
        sec.kind = PhoneNotificationSidebarRowKindSection;
        sec.sectionTitle = @"已钉选";
        [rows addObject:sec];
        for (PhoneNotificationItem *item in pinned) {
            PhoneNotificationSidebarRow *row = [[PhoneNotificationSidebarRow alloc] init];
            row.kind = PhoneNotificationSidebarRowKindItem;
            row.item = item;
            [rows addObject:row];
        }
    }

    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<PhoneNotificationItem *> *> *byPkg = [NSMutableDictionary dictionary];
    for (PhoneNotificationItem *item in rest) {
        NSString *key = item.packageName.length > 0 ? item.packageName : @"unknown";
        if (!byPkg[key]) {
            byPkg[key] = [NSMutableArray array];
            [order addObject:key];
        }
        [byPkg[key] addObject:item];
    }
    for (NSString *pkg in order) {
        NSArray<PhoneNotificationItem *> *group = byPkg[pkg];
        PhoneNotificationItem *first = group.firstObject;
        NSString *label = first.appLabel.length > 0 ? first.appLabel : pkg;
        PhoneNotificationSidebarRow *sec = [[PhoneNotificationSidebarRow alloc] init];
        sec.kind = PhoneNotificationSidebarRowKindSection;
        sec.sectionTitle = label;
        [rows addObject:sec];
        for (PhoneNotificationItem *item in group) {
            PhoneNotificationSidebarRow *row = [[PhoneNotificationSidebarRow alloc] init];
            row.kind = PhoneNotificationSidebarRowKindItem;
            row.item = item;
            [rows addObject:row];
        }
    }
    return rows;
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
        self.emptyDetailLabel.stringValue = @"试试其他分桶或清空搜索。";
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
    (void)tableView;
    PhoneNotificationSidebarRow *r = self.rows[(NSUInteger)row];
    if (r.kind == PhoneNotificationSidebarRowKindSection) return 24;
    if (r.item.kind == PhoneNotificationItemKindOTP) return 64;
    return 52;
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
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"item" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"item";

        NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.wantsLayer = YES;
        dot.layer.cornerRadius = 3.5;
        dot.identifier = @"unreadDot";

        NSTextField *title = [NSTextField labelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.identifier = @"title";
        title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSTextField *body = [NSTextField labelWithString:@""];
        body.translatesAutoresizingMaskIntoConstraints = NO;
        body.identifier = @"body";
        body.font = [NSFont systemFontOfSize:11];
        body.textColor = [NSColor secondaryLabelColor];
        body.lineBreakMode = NSLineBreakByTruncatingTail;

        NSTextField *time = [NSTextField labelWithString:@""];
        time.translatesAutoresizingMaskIntoConstraints = NO;
        time.identifier = @"time";
        time.font = [NSFont systemFontOfSize:10];
        time.textColor = [NSColor tertiaryLabelColor];
        time.alignment = NSTextAlignmentRight;

        NSButton *copyOTP = [NSButton buttonWithTitle:@"复制码" target:self action:@selector(copyOTPFromCell:)];
        copyOTP.translatesAutoresizingMaskIntoConstraints = NO;
        copyOTP.identifier = @"copyOTP";
        copyOTP.bezelStyle = NSBezelStyleInline;
        copyOTP.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        copyOTP.hidden = YES;

        [cell addSubview:dot];
        [cell addSubview:title];
        [cell addSubview:body];
        [cell addSubview:time];
        [cell addSubview:copyOTP];
        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [dot.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
            [dot.widthAnchor constraintEqualToConstant:7],
            [dot.heightAnchor constraintEqualToConstant:7],
            [title.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
            [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
            [title.trailingAnchor constraintEqualToAnchor:time.leadingAnchor constant:-6],
            [time.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [time.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
            [time.widthAnchor constraintGreaterThanOrEqualToConstant:40],
            [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
            [body.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [copyOTP.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [copyOTP.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:2],
            [copyOTP.heightAnchor constraintEqualToConstant:20],
        ]];
    }

    NSView *dot = [self subview:cell id:@"unreadDot"];
    NSTextField *title = (NSTextField *)[self subview:cell id:@"title"];
    NSTextField *body = (NSTextField *)[self subview:cell id:@"body"];
    NSTextField *time = (NSTextField *)[self subview:cell id:@"time"];
    NSButton *copyOTP = (NSButton *)[self subview:cell id:@"copyOTP"];

    BOOL unread = !item.read;
    dot.hidden = !unread;
    if (@available(macOS 10.14, *)) {
        dot.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
    } else {
        dot.layer.backgroundColor = [NSColor blueColor].CGColor;
    }

    NSString *head = item.title.length > 0 ? item.title : (item.appLabel.length > 0 ? item.appLabel : @"通知");
    if (item.pinned) {
        head = [@"📌 " stringByAppendingString:head];
    }
    title.stringValue = head;
    title.font = [NSFont systemFontOfSize:12 weight:unread ? NSFontWeightSemibold : NSFontWeightMedium];

    if (item.kind == PhoneNotificationItemKindOTP && item.otpCode.length > 0) {
        body.stringValue = item.otpCode;
        body.font = [NSFont monospacedDigitSystemFontOfSize:16 weight:NSFontWeightSemibold];
        body.textColor = [NSColor labelColor];
        copyOTP.hidden = NO;
        copyOTP.tag = row;
    } else {
        body.stringValue = item.body.length > 0 ? item.body : @"";
        body.font = [NSFont systemFontOfSize:11];
        body.textColor = [NSColor secondaryLabelColor];
        copyOTP.hidden = YES;
    }

    time.stringValue = [self formatTime:item.postTimeMs];
    cell.objectValue = item.itemID;
    return cell;
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

- (void)emptyActionClicked:(id)sender {
    (void)sender;
    if ([self.delegate respondsToSelector:@selector(notificationSidebarDidRequestCompanionSettings:)]) {
        [self.delegate notificationSidebarDidRequestCompanionSettings:self];
    }
}

- (void)inboxOrChannelDidChange:(NSNotification *)notification {
    (void)notification;
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
