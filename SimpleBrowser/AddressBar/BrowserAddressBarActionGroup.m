#import "BrowserAddressBarActionGroup.h"
#import "CompanionLinkUI.h"
#import "CompanionChannel.h"

NSNotificationName const BrowserAddressBarActionVisibilityDidChangeNotification =
    @"BrowserAddressBarActionVisibilityDidChangeNotification";

static const CGFloat kActionButtonSize = 28.0;
static const CGFloat kActionButtonSpacing = 2.0;
static const CGFloat kDefaultGroupWidth = 184.0;
static const CGFloat kMinimumGroupWidth = 36.0;
static const CGFloat kOverflowHysteresis = 8.0;
static const CGFloat kReorderDragThreshold = 4.0;
static NSString * const kActionOrderDefaultsKey = @"BrowserAddressBarActionOrder";
static NSString * const kActionHiddenDefaultsKey = @"BrowserAddressBarActionHidden";

#pragma mark - Edge Resize

@implementation BrowserAddressBarEdgeResizeView

- (BOOL)isOpaque {
    return NO;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window disableCursorRects];
    [[NSCursor resizeLeftRightCursor] set];
    if (self.onDragBegan) {
        self.onDragBegan();
    }

    NSPoint lastPoint = [self convertPoint:event.locationInWindow fromView:nil];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
        CGFloat deltaX = point.x - lastPoint.x;
        lastPoint = point;
        if (self.onDrag && fabs(deltaX) > 0.01) {
            self.onDrag(deltaX);
        }
    }

    if (self.onDragEnded) {
        self.onDragEnded();
    }
    [self.window enableCursorRects];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

@end

#pragma mark - Action Item

@interface BrowserAddressBarActionItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *toolTip;
@property (nonatomic, assign) BOOL userHidden;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation BrowserAddressBarActionItem
@end

#pragma mark - Reorderable Button

@class BrowserAddressBarActionGroup;

@interface BrowserAddressBarActionButton : NSButton
@property (nonatomic, weak) BrowserAddressBarActionGroup *actionGroup;
@end

@interface BrowserAddressBarActionGroup (Reorder)
- (void)handleMouseDownOnActionButton:(BrowserAddressBarActionButton *)button event:(NSEvent *)event;
- (NSMenu *)contextMenuForActionButton:(BrowserAddressBarActionButton *)button;
@end

@implementation BrowserAddressBarActionButton

- (void)mouseDown:(NSEvent *)event {
    [self.actionGroup handleMouseDownOnActionButton:self event:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return [self.actionGroup contextMenuForActionButton:self];
}

@end

#pragma mark - Action Group

@interface BrowserAddressBarActionGroup ()
@property (nonatomic, strong) NSStackView *buttonStack;
@property (nonatomic, strong) NSButton *overflowButton;
@property (nonatomic, strong) NSMenu *overflowMenu;
@property (nonatomic, strong) NSMutableArray<BrowserAddressBarActionItem *> *items;
@property (nonatomic, strong) NSMutableArray<NSButton *> *actionButtons;
@property (nonatomic, strong, readwrite) NSButton *downloadButton;
@property (nonatomic, strong, readwrite, nullable) NSButton *loginAssistButton;
@property (nonatomic, strong, readwrite, nullable) NSButton *captchaAssistButton;
@property (nonatomic, strong, readwrite, nullable) NSButton *feedButton;
@property (nonatomic, strong, readwrite, nullable) NSButton *findInPageButton;
@property (nonatomic, strong, readwrite, nullable) NSButton *companionLinkButton;
@property (nonatomic, strong, nullable) NSView *companionLinkStatusDot;
@property (nonatomic, assign) CGFloat preferredWidth;
@property (nonatomic, assign) CGFloat maximumWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, assign) BOOL isReordering;
@property (nonatomic, assign) BOOL showsOverflowButton;
@property (nonatomic, strong, readwrite) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overflowWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overflowLeadingSpacingConstraint;
@property (nonatomic, assign) NSInteger lastMenuStartIndex;
@property (nonatomic, assign) NSInteger lastVisibleButtonCount;
@property (nonatomic, assign) BOOL suppressVisibilityBroadcast;
@end

@implementation BrowserAddressBarActionGroup

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _preferredWidth = kDefaultGroupWidth;
        _maximumWidth = 400.0;
        _minimumAddressWidth = 120.0;
        _lastVisibleButtonCount = -1;
        _lastMenuStartIndex = -1;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        _items = [[self orderedActionItems] mutableCopy];
        [self applyHiddenStateFromDefaults];
        _actionButtons = [[self makeActionButtonsForItems:_items] mutableCopy];
        [self refreshDownloadButtonReference];

        _buttonStack = [NSStackView stackViewWithViews:_actionButtons];
        _buttonStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _buttonStack.spacing = kActionButtonSpacing;
        _buttonStack.translatesAutoresizingMaskIntoConstraints = NO;

        _overflowMenu = [[NSMenu alloc] init];
        _overflowButton = [self makeOverflowButton];
        _overflowButton.hidden = YES;

        [self addSubview:_buttonStack];
        [self addSubview:_overflowButton];

        _overflowWidthConstraint = [self.overflowButton.widthAnchor constraintEqualToConstant:0];
        _overflowLeadingSpacingConstraint = [self.overflowButton.leadingAnchor constraintEqualToAnchor:self.buttonStack.trailingAnchor];

        [NSLayoutConstraint activateConstraints:@[
            [self.buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.buttonStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.buttonStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            _overflowLeadingSpacingConstraint,
            [self.overflowButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.overflowButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _overflowWidthConstraint,
            [self.overflowButton.heightAnchor constraintEqualToConstant:kActionButtonSize],
        ]];

        // 不可 Required：否则用户拉宽动作区后，定宽会抬高窗口最小宽度，无法再拖窄
        _widthConstraint = [self.widthAnchor constraintEqualToConstant:_preferredWidth];
        _widthConstraint.priority = NSLayoutPriorityDefaultHigh;
        _widthConstraint.active = YES;

        [self ensureCompanionLinkStatusDot];
        [self updateCompanionLinkAppearance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(actionVisibilityDidChange:)
                                                     name:BrowserAddressBarActionVisibilityDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSZeroRect];
}

#pragma mark - Catalog & order

- (NSArray<BrowserAddressBarActionItem *> *)defaultActionItems {
    NSArray<NSDictionary<NSString *, NSString *> *> *specs = @[
        @{@"id": @"findInPage", @"symbol": @"magnifyingglass", @"tip": @"查找"},
        @{@"id": @"download", @"symbol": @"arrow.down.circle", @"tip": @"下载"},
        @{@"id": @"loginAssist", @"symbol": @"key.horizontal", @"tip": @"登录助手"},
        @{@"id": @"companionLink", @"symbol": @"link", @"tip": @"互联"},
        @{@"id": @"captchaAssist", @"symbol": @"checkerboard.rectangle", @"tip": @"验证码助手"},
        @{@"id": @"rssFeed", @"symbol": @"dot.radiowaves.up.forward", @"tip": @"RSS"},
        @{@"id": @"share", @"symbol": @"square.and.arrow.up", @"tip": @"分享"},
        @{@"id": @"screenshot", @"symbol": @"camera", @"tip": @"截图"},
        @{@"id": @"comment", @"symbol": @"text.bubble", @"tip": @"评论"},
        @{@"id": @"extension", @"symbol": @"puzzlepiece.extension", @"tip": @"扩展"},
        @{@"id": @"pageSettings", @"symbol": @"gearshape", @"tip": @"页面设置"},
        @{@"id": @"copyLink", @"symbol": @"doc.on.doc", @"tip": @"复制链接"},
    ];
    NSMutableArray<BrowserAddressBarActionItem *> *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *spec in specs) {
        BrowserAddressBarActionItem *item = [[BrowserAddressBarActionItem alloc] init];
        item.itemID = spec[@"id"];
        item.symbolName = spec[@"symbol"];
        item.toolTip = spec[@"tip"];
        [items addObject:item];
    }
    return items;
}

- (NSArray<BrowserAddressBarActionItem *> *)orderedActionItems {
    NSArray<BrowserAddressBarActionItem *> *defaults = [self defaultActionItems];
    NSMutableDictionary<NSString *, BrowserAddressBarActionItem *> *byID = [NSMutableDictionary dictionary];
    for (BrowserAddressBarActionItem *item in defaults) {
        byID[item.itemID] = item;
    }

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kActionOrderDefaultsKey];
    if (![saved isKindOfClass:[NSArray class]] || saved.count == 0) {
        return defaults;
    }

    NSMutableArray<BrowserAddressBarActionItem *> *ordered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in saved) {
        if (![entry isKindOfClass:[NSString class]]) {
            continue;
        }
        BrowserAddressBarActionItem *item = byID[entry];
        if (item && ![seen containsObject:item.itemID]) {
            [ordered addObject:item];
            [seen addObject:item.itemID];
        }
    }
    for (BrowserAddressBarActionItem *item in defaults) {
        if ([seen containsObject:item.itemID]) {
            continue;
        }
        // 升级迁移：新「互联」键插到登录助手之后，避免落到末尾溢出区
        if ([item.itemID isEqualToString:@"companionLink"]) {
            NSUInteger loginIdx = NSNotFound;
            for (NSUInteger i = 0; i < ordered.count; i++) {
                if ([ordered[i].itemID isEqualToString:@"loginAssist"]) {
                    loginIdx = i;
                    break;
                }
            }
            if (loginIdx != NSNotFound) {
                [ordered insertObject:item atIndex:loginIdx + 1];
            } else {
                [ordered addObject:item];
            }
        } else {
            [ordered addObject:item];
        }
        [seen addObject:item.itemID];
    }
    return ordered;
}

- (void)applyHiddenStateFromDefaults {
    NSArray *hidden = [[NSUserDefaults standardUserDefaults] arrayForKey:kActionHiddenDefaultsKey];
    NSSet<NSString *> *hiddenIDs = [hidden isKindOfClass:[NSArray class]]
        ? [NSSet setWithArray:hidden]
        : [NSSet set];
    for (BrowserAddressBarActionItem *item in self.items) {
        item.userHidden = [hiddenIDs containsObject:item.itemID];
    }
}

- (void)persistActionOrder {
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:self.items.count];
    for (BrowserAddressBarActionItem *item in self.items) {
        if (item.itemID.length > 0) {
            [ids addObject:item.itemID];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kActionOrderDefaultsKey];
}

- (void)persistHiddenState {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (BrowserAddressBarActionItem *item in self.items) {
        if (item.userHidden && item.itemID.length > 0) {
            [ids addObject:item.itemID];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kActionHiddenDefaultsKey];
}

- (void)broadcastVisibilityChange {
    if (self.suppressVisibilityBroadcast) {
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserAddressBarActionVisibilityDidChangeNotification
                                                        object:self];
}

- (void)actionVisibilityDidChange:(NSNotification *)notification {
    if (notification.object == self) {
        return;
    }
    NSInteger oldToolbarCount = [self toolbarItemCount];
    self.suppressVisibilityBroadcast = YES;
    [self applyHiddenStateFromDefaults];
    NSInteger newToolbarCount = [self toolbarItemCount];
    self.lastVisibleButtonCount = -1;
    self.lastMenuStartIndex = -1;
    [self compactPreferredWidthToContentAllowingExpand:(newToolbarCount > oldToolbarCount)];
    self.suppressVisibilityBroadcast = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BrowserAddressBarActionOrderDidChangeNotification"
                                                        object:self];
}

- (void)refreshDownloadButtonReference {
    self.downloadButton = nil;
    self.loginAssistButton = nil;
    self.captchaAssistButton = nil;
    self.feedButton = nil;
    self.findInPageButton = nil;
    self.companionLinkButton = nil;
    for (NSUInteger i = 0; i < self.items.count; i++) {
        NSString *itemID = self.items[i].itemID;
        if ([itemID isEqualToString:@"download"]) {
            self.downloadButton = self.actionButtons[i];
        } else if ([itemID isEqualToString:@"loginAssist"]) {
            self.loginAssistButton = self.actionButtons[i];
        } else if ([itemID isEqualToString:@"captchaAssist"]) {
            self.captchaAssistButton = self.actionButtons[i];
        } else if ([itemID isEqualToString:@"rssFeed"]) {
            self.feedButton = self.actionButtons[i];
        } else if ([itemID isEqualToString:@"findInPage"]) {
            self.findInPageButton = self.actionButtons[i];
        } else if ([itemID isEqualToString:@"companionLink"]) {
            self.companionLinkButton = self.actionButtons[i];
        }
    }
    [self ensureCompanionLinkStatusDot];
    [self updateCompanionLinkAppearance];
}

- (void)ensureCompanionLinkStatusDot {
    NSButton *button = self.companionLinkButton;
    if (!button) {
        [self.companionLinkStatusDot removeFromSuperview];
        return;
    }
    if (!self.companionLinkStatusDot) {
        NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
        dot.wantsLayer = YES;
        dot.layer.cornerRadius = 4.0;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        self.companionLinkStatusDot = dot;
    }
    if (self.companionLinkStatusDot.superview != button) {
        [self.companionLinkStatusDot removeFromSuperview];
        [button addSubview:self.companionLinkStatusDot];
        [NSLayoutConstraint activateConstraints:@[
            [self.companionLinkStatusDot.widthAnchor constraintEqualToConstant:8],
            [self.companionLinkStatusDot.heightAnchor constraintEqualToConstant:8],
            [self.companionLinkStatusDot.topAnchor constraintEqualToAnchor:button.topAnchor constant:2],
            [self.companionLinkStatusDot.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-2],
        ]];
    }
}

- (void)updateCompanionLinkAppearance {
    [self ensureCompanionLinkStatusDot];
    NSButton *button = self.companionLinkButton;
    if (!button || !self.companionLinkStatusDot) {
        return;
    }
    CompanionLinkUIState state = [CompanionLinkUI stateFromChannel:[CompanionChannel sharedChannel]];
    NSColor *dotColor = [CompanionLinkUI dotColorForState:state];
    self.companionLinkStatusDot.layer.backgroundColor = dotColor.CGColor;
    if (@available(macOS 10.14, *)) {
        self.companionLinkStatusDot.layer.borderWidth = 1.0;
        self.companionLinkStatusDot.layer.borderColor = [NSColor controlBackgroundColor].CGColor;
    }
    button.alphaValue = (state == CompanionLinkUIStateDisconnected) ? 0.7 : 1.0;
    NSString *title = [CompanionLinkUI titleForState:state];
    button.toolTip = [NSString stringWithFormat:@"互联 · %@", title];
    button.accessibilityLabel = [NSString stringWithFormat:@"互联 · %@", title];
}

#pragma mark - Buttons

- (NSImage *)symbolImageNamed:(NSString *)symbolName {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:15
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (BrowserAddressBarActionButton *)makeToolbarButtonWithSymbol:(NSString *)symbolName toolTip:(NSString *)toolTip {
    NSImage *image = [self symbolImageNamed:symbolName];
    BrowserAddressBarActionButton *button = [[BrowserAddressBarActionButton alloc] initWithFrame:NSZeroRect];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = toolTip;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.actionGroup = self;
    if (image) {
        button.image = image;
    } else {
        button.title = @"?";
    }
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kActionButtonSize],
    ]];
    button.target = self;
    button.action = @selector(demoButtonClicked:);
    return button;
}

- (NSArray<NSButton *> *)makeActionButtonsForItems:(NSArray<BrowserAddressBarActionItem *> *)items {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (BrowserAddressBarActionItem *item in items) {
        BrowserAddressBarActionButton *button = [self makeToolbarButtonWithSymbol:item.symbolName toolTip:item.toolTip];
        if (item.target && item.action) {
            button.target = item.target;
            button.action = item.action;
        }
        [buttons addObject:button];
    }
    return buttons;
}

- (NSButton *)makeOverflowButton {
    NSButton *button = [NSButton buttonWithImage:[self symbolImageNamed:@"chevron.right"]
                                          target:self
                                          action:@selector(showOverflowMenu:)];
    if (!button.image) {
        button = [NSButton buttonWithTitle:@"…" target:self action:@selector(showOverflowMenu:)];
    }
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"更多工具";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kActionButtonSize],
    ]];
    return button;
}

- (void)demoButtonClicked:(id)sender {
    (void)sender;
}

- (void)showOverflowMenu:(NSButton *)sender {
    NSPoint location = NSMakePoint(0, NSHeight(sender.bounds));
    [self.overflowMenu popUpMenuPositioningItem:nil atLocation:location inView:sender];
}

#pragma mark - Pin / Hide

- (NSInteger)indexOfActionButton:(NSButton *)button {
    return [self.actionButtons indexOfObject:button];
}

- (NSMenu *)contextMenuForActionButton:(BrowserAddressBarActionButton *)button {
    NSInteger index = [self indexOfActionButton:button];
    if (index == NSNotFound || index >= (NSInteger)self.items.count) {
        return nil;
    }
    BrowserAddressBarActionItem *item = self.items[index];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:item.toolTip ?: @"工具"];

    NSMenuItem *pinItem = [[NSMenuItem alloc] initWithTitle:@"固定"
                                                     action:@selector(pinActionItem:)
                                              keyEquivalent:@""];
    pinItem.target = self;
    pinItem.representedObject = item.itemID;
    pinItem.state = item.userHidden ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:pinItem];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:@"隐藏"
                                                      action:@selector(hideActionItem:)
                                               keyEquivalent:@""];
    hideItem.target = self;
    hideItem.representedObject = item.itemID;
    hideItem.state = item.userHidden ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:hideItem];

    if (self.augmentContextMenu) {
        self.augmentContextMenu(item.itemID, menu);
    }
    return menu;
}

- (BrowserAddressBarActionItem *)itemWithID:(NSString *)itemID {
    if (itemID.length == 0) {
        return nil;
    }
    for (BrowserAddressBarActionItem *item in self.items) {
        if ([item.itemID isEqualToString:itemID]) {
            return item;
        }
    }
    return nil;
}

- (void)pinActionItem:(NSMenuItem *)sender {
    NSString *itemID = sender.representedObject;
    BrowserAddressBarActionItem *item = [self itemWithID:itemID];
    if (!item || !item.userHidden) {
        return;
    }
    item.userHidden = NO;
    [self persistHiddenState];
    self.lastVisibleButtonCount = -1;
    self.lastMenuStartIndex = -1;
    [self compactPreferredWidthToContentAllowingExpand:YES];
    [self broadcastVisibilityChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BrowserAddressBarActionOrderDidChangeNotification"
                                                        object:self];
}

- (void)hideActionItem:(NSMenuItem *)sender {
    NSString *itemID = sender.representedObject;
    BrowserAddressBarActionItem *item = [self itemWithID:itemID];
    if (!item || item.userHidden) {
        return;
    }
    item.userHidden = YES;
    [self persistHiddenState];
    self.lastVisibleButtonCount = -1;
    self.lastMenuStartIndex = -1;
    [self compactPreferredWidthToContentAllowingExpand:NO];
    [self broadcastVisibilityChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BrowserAddressBarActionOrderDidChangeNotification"
                                                        object:self];
}

- (NSInteger)toolbarItemCount {
    NSInteger count = 0;
    for (BrowserAddressBarActionItem *item in self.items) {
        if (!item.userHidden) {
            count += 1;
        }
    }
    return count;
}

- (NSInteger)userHiddenItemCount {
    NSInteger count = 0;
    for (BrowserAddressBarActionItem *item in self.items) {
        if (item.userHidden) {
            count += 1;
        }
    }
    return count;
}

/// 将工具组宽度对齐到当前应显示的按钮（+ 溢出箭头），去掉尾部空白。
/// allowExpand：固定回工具栏时允许变宽以容纳新按钮。
- (void)compactPreferredWidthToContentAllowingExpand:(BOOL)allowExpand {
    NSInteger toolbar = [self toolbarItemCount];
    BOOL hasUserHidden = [self userHiddenItemCount] > 0;

    CGFloat footprint = self.preferredWidth;
    if (allowExpand) {
        footprint = [self clampedPreferredWidth:footprint + kActionButtonSize + kActionButtonSpacing];
    }

    BOOL needsWidthOverflow = [self widthForButtonCount:toolbar includeOverflow:NO] > footprint + 0.5;
    BOOL showOverflow = hasUserHidden || needsWidthOverflow;
    NSInteger visible = toolbar;
    if (showOverflow) {
        CGFloat available = footprint - (kActionButtonSpacing + kActionButtonSize);
        visible = [self visibleToolbarButtonCountForAvailableWidth:MAX(0, available) total:toolbar];
        if (hasUserHidden) {
            visible = MAX(0, MIN(visible, toolbar));
        } else {
            visible = MAX(0, MIN(visible, MAX(0, toolbar - 1)));
        }
    }
    if (toolbar == 0 && hasUserHidden) {
        visible = 0;
        showOverflow = YES;
    }

    CGFloat exact = [self widthForButtonCount:visible includeOverflow:showOverflow];
    exact = [self clampedPreferredWidth:exact];
    self.preferredWidth = exact;
    self.widthConstraint.constant = exact;
    [self updateOverflowLayoutForWidth:exact];
}

#pragma mark - Reorder / click

- (void)handleMouseDownOnActionButton:(BrowserAddressBarActionButton *)button event:(NSEvent *)event {
    if (button.hidden || self.isResizingWidth) {
        return;
    }

    NSInteger fromIndex = [self.actionButtons indexOfObject:button];
    if (fromIndex == NSNotFound) {
        return;
    }

    button.highlighted = YES;
    NSPoint startInWindow = event.locationInWindow;
    BOOL didReorder = NO;
    NSInteger currentIndex = fromIndex;

    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }

        NSPoint now = next.locationInWindow;
        CGFloat dx = now.x - startInWindow.x;
        CGFloat dy = now.y - startInWindow.y;
        if (!didReorder && (dx * dx + dy * dy) >= (kReorderDragThreshold * kReorderDragThreshold)) {
            didReorder = YES;
            self.isReordering = YES;
            if (@available(macOS 10.14, *)) {
                button.contentTintColor = [NSColor controlAccentColor];
            }
            button.alphaValue = 0.55;
        }
        if (!didReorder) {
            continue;
        }

        NSPoint inStack = [self.buttonStack convertPoint:now fromView:nil];
        NSInteger targetIndex = [self insertionIndexForPointInStack:inStack
                                                    excludingButton:button
                                                      currentIndex:currentIndex];
        if (targetIndex > currentIndex) {
            [self swapActionAtIndex:currentIndex withIndex:currentIndex + 1];
            currentIndex += 1;
        } else if (targetIndex < currentIndex) {
            [self swapActionAtIndex:currentIndex withIndex:currentIndex - 1];
            currentIndex -= 1;
        }
    }

    button.highlighted = NO;
    button.alphaValue = 1.0;
    if (!didReorder) {
        // 短按：触发原按钮动作（用 sendAction，与菜单/快捷键路径一致）
        if (button.action) {
            [NSApp sendAction:button.action to:button.target from:button];
        }
    } else {
        if (@available(macOS 10.14, *)) {
            // 下载按钮忙碌高亮由窗口控制器维护；此处恢复为默认次要色
            button.contentTintColor = [NSColor secondaryLabelColor];
        }
        [self persistActionOrder];
        self.isReordering = NO;
        self.lastVisibleButtonCount = -1;
        self.lastMenuStartIndex = -1;
        [self updateOverflowLayout];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BrowserAddressBarActionOrderDidChangeNotification"
                                                            object:self];
    }
}

- (NSInteger)insertionIndexForPointInStack:(NSPoint)point
                           excludingButton:(NSButton *)dragged
                             currentIndex:(NSInteger)currentIndex {
    (void)dragged;
    NSInteger bestIndex = currentIndex;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < self.actionButtons.count; i++) {
        NSButton *candidate = self.actionButtons[i];
        if (candidate.hidden || self.items[i].userHidden) {
            continue;
        }
        CGFloat midX = NSMidX(candidate.frame);
        CGFloat distance = fabs(point.x - midX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = (NSInteger)i;
        }
    }
    return bestIndex;
}

- (void)swapActionAtIndex:(NSInteger)indexA withIndex:(NSInteger)indexB {
    if (indexA == indexB ||
        indexA < 0 || indexB < 0 ||
        indexA >= (NSInteger)self.actionButtons.count ||
        indexB >= (NSInteger)self.actionButtons.count) {
        return;
    }
    if (self.actionButtons[indexA].hidden || self.actionButtons[indexB].hidden ||
        self.items[indexA].userHidden || self.items[indexB].userHidden) {
        return;
    }

    [self.actionButtons exchangeObjectAtIndex:indexA withObjectAtIndex:indexB];
    [self.items exchangeObjectAtIndex:indexA withObjectAtIndex:indexB];

    for (NSButton *button in [self.actionButtons copy]) {
        [self.buttonStack removeArrangedSubview:button];
        [button removeFromSuperview];
    }
    for (NSButton *button in self.actionButtons) {
        [self.buttonStack addArrangedSubview:button];
    }

    [self refreshDownloadButtonReference];
    self.lastVisibleButtonCount = -1;
}

#pragma mark - Width resize

- (CGFloat)clampedPreferredWidth:(CGFloat)width {
    CGFloat minWidth = kMinimumGroupWidth;
    CGFloat maxWidth = MAX(minWidth, self.maximumWidth);
    return MIN(MAX(width, minWidth), maxWidth);
}

- (void)applyWidthDelta:(CGFloat)deltaX {
    CGFloat next = [self clampedPreferredWidth:round(self.preferredWidth + deltaX)];
    if (fabs(next - self.preferredWidth) < 0.5) {
        [self updateOverflowLayoutForWidth:self.preferredWidth];
        return;
    }
    self.preferredWidth = next;
    self.widthConstraint.constant = next;
    [self updateOverflowLayoutForWidth:next];
}

- (void)beginWidthResize {
    self.isResizingWidth = YES;
}

- (void)endWidthResize {
    self.isResizingWidth = NO;
    [self updateOverflowLayout];
}

#pragma mark - Overflow

- (CGFloat)widthForButtonCount:(NSInteger)count includeOverflow:(BOOL)includeOverflow {
    if (count <= 0) {
        return includeOverflow ? kActionButtonSize : 0;
    }
    CGFloat width = (CGFloat)count * kActionButtonSize + (CGFloat)(count - 1) * kActionButtonSpacing;
    if (includeOverflow) {
        width += kActionButtonSpacing + kActionButtonSize;
    }
    return width;
}

- (NSInteger)visibleToolbarButtonCountForAvailableWidth:(CGFloat)available total:(NSInteger)total {
    NSInteger visibleCount = 0;
    for (NSInteger i = 1; i <= total; i++) {
        if ([self widthForButtonCount:i includeOverflow:NO] <= available + 0.5) {
            visibleCount = i;
        } else {
            break;
        }
    }
    return visibleCount;
}

- (NSArray<NSNumber *> *)toolbarIndexes {
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.items.count; i++) {
        if (!self.items[i].userHidden) {
            [indexes addObject:@(i)];
        }
    }
    return indexes;
}

- (void)updateOverflowLayout {
    if (self.isReordering) {
        return;
    }
    CGFloat groupWidth = floor(self.preferredWidth > 0 ? self.preferredWidth : MAX(0, NSWidth(self.bounds)));
    [self updateOverflowLayoutForWidth:groupWidth];
}

- (void)updateOverflowLayoutForWidth:(CGFloat)groupWidth {
    NSInteger total = (NSInteger)self.actionButtons.count;
    if (total == 0) {
        self.showsOverflowButton = NO;
        [self applyOverflowPresentation];
        return;
    }

    groupWidth = floor(MAX(0, groupWidth));
    NSArray<NSNumber *> *toolbarIndexes = [self toolbarIndexes];
    NSInteger toolbarTotal = (NSInteger)toolbarIndexes.count;
    NSInteger hiddenCount = [self userHiddenItemCount];

    CGFloat allToolbarWidth = [self widthForButtonCount:toolbarTotal includeOverflow:NO];
    BOOL widthOverflow = NO;
    if (self.showsOverflowButton) {
        widthOverflow = (groupWidth + kOverflowHysteresis) < allToolbarWidth;
    } else {
        widthOverflow = groupWidth < allToolbarWidth;
    }
    BOOL shouldShowOverflow = widthOverflow || hiddenCount > 0;

    if (self.showsOverflowButton != shouldShowOverflow) {
        self.showsOverflowButton = shouldShowOverflow;
        [self applyOverflowPresentation];
    }

    NSInteger visibleToolbarCount = toolbarTotal;
    if (shouldShowOverflow && widthOverflow) {
        CGFloat available = groupWidth - (kActionButtonSpacing + kActionButtonSize);
        visibleToolbarCount = [self visibleToolbarButtonCountForAvailableWidth:available total:toolbarTotal];
        visibleToolbarCount = MAX(0, MIN(visibleToolbarCount, MAX(0, toolbarTotal - (hiddenCount > 0 ? 0 : 1))));
        if (hiddenCount == 0) {
            visibleToolbarCount = MAX(0, MIN(visibleToolbarCount, toolbarTotal - 1));
        }
    } else if (shouldShowOverflow && !widthOverflow) {
        // 仅有用户隐藏项：工具栏项全部可见
        visibleToolbarCount = toolbarTotal;
    }

    // 标记每个按钮是否显示
    NSMutableSet<NSNumber *> *visibleIndexSet = [NSMutableSet set];
    for (NSInteger i = 0; i < visibleToolbarCount && i < (NSInteger)toolbarIndexes.count; i++) {
        [visibleIndexSet addObject:toolbarIndexes[i]];
    }

    NSInteger signature = visibleToolbarCount + toolbarTotal * 1000 + hiddenCount * 100000;
    if (signature != self.lastVisibleButtonCount) {
        self.lastVisibleButtonCount = signature;
        for (NSInteger i = 0; i < total; i++) {
            BOOL shouldHide = self.items[i].userHidden || ![visibleIndexSet containsObject:@(i)];
            NSButton *button = self.actionButtons[i];
            if (button.hidden != shouldHide) {
                button.hidden = shouldHide;
            }
        }
    }

    [self rebuildOverflowMenuWithVisibleToolbarCount:visibleToolbarCount
                                      toolbarIndexes:toolbarIndexes];
}

- (void)applyOverflowPresentation {
    if (self.showsOverflowButton) {
        self.overflowWidthConstraint.constant = kActionButtonSize;
        self.overflowLeadingSpacingConstraint.constant = kActionButtonSpacing;
        self.overflowButton.hidden = NO;
    } else {
        self.overflowWidthConstraint.constant = 0;
        self.overflowLeadingSpacingConstraint.constant = 0;
        self.overflowButton.hidden = YES;
    }
}

- (void)rebuildOverflowMenuWithVisibleToolbarCount:(NSInteger)visibleToolbarCount
                                    toolbarIndexes:(NSArray<NSNumber *> *)toolbarIndexes {
    NSInteger menuKey = visibleToolbarCount + (NSInteger)toolbarIndexes.count * 100 + [self userHiddenItemCount] * 10000;
    if (self.overflowMenu.numberOfItems > 0 &&
        self.lastMenuStartIndex == menuKey &&
        !self.isResizingWidth) {
        return;
    }
    self.lastMenuStartIndex = menuKey;

    [self.overflowMenu removeAllItems];

    // 1) 因宽度溢出而未显示的工具栏项
    for (NSInteger i = visibleToolbarCount; i < (NSInteger)toolbarIndexes.count; i++) {
        NSInteger index = toolbarIndexes[i].integerValue;
        [self addOverflowMenuItemForIndex:index];
    }

    // 2) 用户主动隐藏的项
    BOOL addedHiddenHeader = NO;
    for (NSUInteger i = 0; i < self.items.count; i++) {
        if (!self.items[i].userHidden) {
            continue;
        }
        if (!addedHiddenHeader && self.overflowMenu.numberOfItems > 0) {
            [self.overflowMenu addItem:[NSMenuItem separatorItem]];
            addedHiddenHeader = YES;
        }
        [self addOverflowMenuItemForIndex:(NSInteger)i];
    }

    // 3) 将隐藏项「固定」回工具栏
    NSMutableArray<BrowserAddressBarActionItem *> *hiddenItems = [NSMutableArray array];
    for (BrowserAddressBarActionItem *item in self.items) {
        if (item.userHidden) {
            [hiddenItems addObject:item];
        }
    }
    if (hiddenItems.count > 0) {
        [self.overflowMenu addItem:[NSMenuItem separatorItem]];
        for (BrowserAddressBarActionItem *item in hiddenItems) {
            NSString *title = [NSString stringWithFormat:@"固定「%@」", item.toolTip ?: item.itemID];
            NSMenuItem *pinItem = [[NSMenuItem alloc] initWithTitle:title
                                                             action:@selector(pinActionItem:)
                                                      keyEquivalent:@""];
            pinItem.target = self;
            pinItem.representedObject = item.itemID;
            [self.overflowMenu addItem:pinItem];
        }
    }
}

- (void)addOverflowMenuItemForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) {
        return;
    }
    BrowserAddressBarActionItem *item = self.items[index];
    SEL action = @selector(demoButtonClicked:);
    id target = self;
    if (index < (NSInteger)self.actionButtons.count) {
        NSButton *button = self.actionButtons[index];
        if (button.target && button.action) {
            target = button.target;
            action = button.action;
        }
    }
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:item.toolTip
                                                      action:action
                                               keyEquivalent:@""];
    menuItem.target = target;
    menuItem.image = [self symbolImageNamed:item.symbolName];
    [self.overflowMenu addItem:menuItem];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    [self updateMaximumWidthFromWindow];
    if (!self.isResizingWidth && !self.isReordering) {
        [self updateOverflowLayout];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:self.window];
        [self updateMaximumWidthFromWindow];
        [self updateOverflowLayout];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSWindowDidResizeNotification
                                                      object:self.window];
    }
    [super viewWillMoveToWindow:newWindow];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    if (!self.isResizingWidth && !self.isReordering) {
        [self updateMaximumWidthFromWindow];
        [self updateOverflowLayout];
    }
}

- (void)updateMaximumWidthFromWindow {
    NSView *container = self.layoutContainer ?: self.superview;
    if (!container) {
        return;
    }
    CGFloat containerWidth = floor(NSWidth(container.bounds));
    if (containerWidth < 1.0) {
        return;
    }
    self.maximumWidth = MAX(kMinimumGroupWidth, containerWidth - self.minimumAddressWidth);
    CGFloat clamped = [self clampedPreferredWidth:self.preferredWidth];
    if (fabs(clamped - self.preferredWidth) > 0.5) {
        self.preferredWidth = clamped;
        self.widthConstraint.constant = clamped;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
