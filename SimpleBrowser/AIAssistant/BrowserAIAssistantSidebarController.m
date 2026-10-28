#import "BrowserAIAssistantSidebarController.h"
#import "BrowserAIAssistantPreferences.h"
#import "BrowserAIAssistantPrompts.h"
#import "BrowserAIAssistantClient.h"
#import "BrowserAIAssistantChatPanel.h"
#import "AIAssistantSession.h"
#import "AIAssistantSessionStore.h"
#import "AIAssistantHistoryPanel.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeService.h"
#import "SBTextView.h"

static const CGFloat kSidebarDefaultWidth = 400.0;
static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidth = 560.0;
static const CGFloat kRailWidth = 44.0;

typedef NS_ENUM(NSInteger, AIAssistantPane) {
    AIAssistantPaneChat = 0,
    AIAssistantPaneNewSession,
};

@interface BrowserAIAssistantResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation BrowserAIAssistantResizeView
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

@interface BrowserAIAssistantSidebarController () <NSTextViewDelegate, NSTextFieldDelegate, NSPopoverDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, strong) BrowserAIAssistantResizeView *resizeHandle;

@property (nonatomic, assign) AIAssistantPane pane;
@property (nonatomic, strong) NSView *leftRail;
@property (nonatomic, strong) NSView *mainColumn;
@property (nonatomic, strong) NSView *chatPane;
@property (nonatomic, strong) NSView *createSessionPane;

@property (nonatomic, strong) NSButton *plusButton;
@property (nonatomic, strong) NSButton *historyButton;
@property (nonatomic, strong) NSButton *skillsButton;
@property (nonatomic, strong) NSButton *pluginsButton;
@property (nonatomic, strong) NSButton *tasksButton;
@property (nonatomic, strong) NSButton *displayButton;
@property (nonatomic, strong) NSButton *bridgeRailButton;
@property (nonatomic, strong) NSButton *settingsButton;

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeBtn;
@property (nonatomic, strong) NSView *statusDot;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *focusTabButton;
@property (nonatomic, strong) NSButton *reopenButton;
@property (nonatomic, strong) NSButton *moreButton;
@property (nonatomic, strong) BrowserAIAssistantChatPanel *chatPanel;
@property (nonatomic, strong) SBTextView *inputView;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *cancelButton;

@property (nonatomic, strong) NSStackView *providerStack;
@property (nonatomic, copy, nullable) NSString *pendingProviderId;

@property (nonatomic, strong, nullable) NSPopover *historyPopover;
@property (nonatomic, strong, nullable) AIAssistantHistoryPanel *historyPanel;

@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, copy, nullable) NSString *inFlightSessionId;

@property (nonatomic, strong, nullable) id registryObserver;
@property (nonatomic, strong, nullable) id serviceObserver;
@property (nonatomic, strong, nullable) id storeObserver;
@end

@implementation BrowserAIAssistantSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        CGFloat w = BrowserAIAssistantPreferences.sharedPreferences.sidebarWidth;
        if (w < kSidebarMinWidth || w > kSidebarMaxWidth) w = kSidebarDefaultWidth;
        _currentWidth = w;
        _pane = AIAssistantPaneChat;
        [self buildUI];
        __weak typeof(self) weakSelf = self;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        _registryObserver = [nc addObserverForName:AIBridgeRegistryDidChangeNotification
                                             object:nil
                                              queue:NSOperationQueue.mainQueue
                                         usingBlock:^(__unused NSNotification *n) {
            [weakSelf refreshConnectionState];
            [weakSelf reloadUI];
        }];
        _serviceObserver = [nc addObserverForName:AIBridgeServiceStateDidChangeNotification
                                            object:nil
                                             queue:NSOperationQueue.mainQueue
                                        usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
        _storeObserver = [nc addObserverForName:AIAssistantSessionStoreDidChangeNotification
                                          object:nil
                                           queue:NSOperationQueue.mainQueue
                                      usingBlock:^(__unused NSNotification *n) {
            [weakSelf.historyPanel reload];
            [weakSelf reloadUI];
        }];
        [self refreshConnectionState];
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (self.registryObserver) [nc removeObserver:self.registryObserver];
    if (self.serviceObserver) [nc removeObserver:self.serviceObserver];
    if (self.storeObserver) [nc removeObserver:self.storeObserver];
}

#pragma mark - Symbols / rail buttons

- (NSImage *)symbolNamed:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:14
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return [img imageWithSymbolConfiguration:cfg] ?: img;
    }
    return nil;
}

- (NSButton *)railButtonSymbol:(NSString *)symbol
                       tooltip:(NSString *)tip
                        action:(SEL)action
                     enabled:(BOOL)enabled {
    NSImage *img = [self symbolNamed:symbol];
    NSButton *b = img ? [NSButton buttonWithImage:img target:self action:action]
                      : [NSButton buttonWithTitle:@"·" target:self action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.bezelStyle = NSBezelStyleInline;
    b.bordered = NO;
    b.imagePosition = NSImageOnly;
    b.imageScaling = NSImageScaleProportionallyDown;
    b.toolTip = tip;
    b.enabled = enabled;
    if (@available(macOS 10.14, *)) {
        b.contentTintColor = enabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
    }
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:32],
        [b.heightAnchor constraintEqualToConstant:32],
    ]];
    return b;
}

#pragma mark - UI

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;
    root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    __weak typeof(self) weakSelf = self;
    BrowserAIAssistantResizeView *handle = [[BrowserAIAssistantResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
        weakSelf.isResizingWidth = YES;
    };
    handle.onDragToOffset = ^(CGFloat delta) {
        [weakSelf applyWidth:weakSelf.dragStartWidth - delta];
    };
    handle.onDragEnded = ^{
        weakSelf.isResizingWidth = NO;
        [weakSelf persistWidth];
    };
    self.resizeHandle = handle;

    NSView *edgeSeparator = [[NSView alloc] initWithFrame:NSZeroRect];
    edgeSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    edgeSeparator.wantsLayer = YES;
    edgeSeparator.layer.backgroundColor = NSColor.separatorColor.CGColor;

    self.leftRail = [self buildLeftRail];
    self.mainColumn = [self buildMainColumn];

    NSView *railSep = [[NSView alloc] initWithFrame:NSZeroRect];
    railSep.translatesAutoresizingMaskIntoConstraints = NO;
    railSep.wantsLayer = YES;
    railSep.layer.backgroundColor = NSColor.separatorColor.CGColor;

    for (NSView *v in @[handle, edgeSeparator, self.leftRail, railSep, self.mainColumn]) {
        [root addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.widthAnchor constraintEqualToConstant:6],
        [edgeSeparator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edgeSeparator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edgeSeparator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [edgeSeparator.widthAnchor constraintEqualToConstant:1],

        [self.leftRail.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.leftRail.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [self.leftRail.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:6],
        [self.leftRail.widthAnchor constraintEqualToConstant:kRailWidth],

        [railSep.topAnchor constraintEqualToAnchor:root.topAnchor constant:8],
        [railSep.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-8],
        [railSep.leadingAnchor constraintEqualToAnchor:self.leftRail.trailingAnchor],
        [railSep.widthAnchor constraintEqualToConstant:1],

        [self.mainColumn.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.mainColumn.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [self.mainColumn.leadingAnchor constraintEqualToAnchor:railSep.trailingAnchor],
        [self.mainColumn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];

    self.view = root;
    [self showPane:AIAssistantPaneChat];
    [self reloadUI];
}

- (NSView *)buildLeftRail {
    NSView *rail = [[NSView alloc] initWithFrame:NSZeroRect];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        rail.wantsLayer = YES;
        rail.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    }

    self.plusButton = [self railButtonSymbol:@"plus"
                                     tooltip:@"新建会话"
                                      action:@selector(newClicked:)
                                     enabled:YES];
    self.historyButton = [self railButtonSymbol:@"clock"
                                         tooltip:@"会话历史"
                                          action:@selector(historyClicked:)
                                         enabled:YES];
    self.skillsButton = [self railButtonSymbol:@"wand.and.stars"
                                        tooltip:@"技能（即将推出）"
                                         action:@selector(placeholderClicked:)
                                        enabled:YES];
    self.pluginsButton = [self railButtonSymbol:@"puzzlepiece.extension"
                                         tooltip:@"插件（即将推出）"
                                          action:@selector(placeholderClicked:)
                                         enabled:YES];
    self.tasksButton = [self railButtonSymbol:@"checklist"
                                       tooltip:@"任务（即将推出）"
                                        action:@selector(placeholderClicked:)
                                       enabled:YES];
    self.displayButton = [self railButtonSymbol:@"rectangle.split.3x3"
                                         tooltip:@"大屏（即将推出）"
                                          action:@selector(placeholderClicked:)
                                         enabled:YES];
    self.bridgeRailButton = [self railButtonSymbol:@"arrow.left.arrow.right.circle"
                                            tooltip:@"AI Bridge 设置"
                                             action:@selector(openBridgeClicked:)
                                            enabled:YES];
    self.settingsButton = [self railButtonSymbol:@"gearshape"
                                          tooltip:@"设置（即将推出）"
                                           action:@selector(placeholderClicked:)
                                          enabled:YES];

    NSStackView *top = [NSStackView stackViewWithViews:@[
        self.plusButton, self.historyButton, self.skillsButton,
        self.pluginsButton, self.tasksButton, self.displayButton
    ]];
    top.translatesAutoresizingMaskIntoConstraints = NO;
    top.orientation = NSUserInterfaceLayoutOrientationVertical;
    top.spacing = 4;
    top.alignment = NSLayoutAttributeCenterX;

    NSStackView *bottom = [NSStackView stackViewWithViews:@[ self.bridgeRailButton, self.settingsButton ]];
    bottom.translatesAutoresizingMaskIntoConstraints = NO;
    bottom.orientation = NSUserInterfaceLayoutOrientationVertical;
    bottom.spacing = 4;
    bottom.alignment = NSLayoutAttributeCenterX;

    [rail addSubview:top];
    [rail addSubview:bottom];
    [NSLayoutConstraint activateConstraints:@[
        [top.topAnchor constraintEqualToAnchor:rail.topAnchor constant:10],
        [top.centerXAnchor constraintEqualToAnchor:rail.centerXAnchor],
        [bottom.bottomAnchor constraintEqualToAnchor:rail.bottomAnchor constant:-12],
        [bottom.centerXAnchor constraintEqualToAnchor:rail.centerXAnchor],
    ]];
    return rail;
}

- (NSView *)buildMainColumn {
    NSView *col = [[NSView alloc] initWithFrame:NSZeroRect];
    col.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [NSTextField labelWithString:@"AI 助手"];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.editable = YES;
    self.titleLabel.selectable = YES;
    self.titleLabel.bezeled = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.delegate = self;

    self.closeBtn = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeClicked:)];
    self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeBtn.bezelStyle = NSBezelStyleRounded;
    self.closeBtn.controlSize = NSControlSizeSmall;

    self.chatPane = [self buildChatPane];
    self.createSessionPane = [self buildCreateSessionPane];

    for (NSView *v in @[self.titleLabel, self.closeBtn, self.chatPane, self.createSessionPane]) {
        [col addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:col.topAnchor constant:12],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:col.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeBtn.leadingAnchor constant:-8],

        [self.closeBtn.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.closeBtn.trailingAnchor constraintEqualToAnchor:col.trailingAnchor constant:-12],

        [self.chatPane.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.chatPane.leadingAnchor constraintEqualToAnchor:col.leadingAnchor],
        [self.chatPane.trailingAnchor constraintEqualToAnchor:col.trailingAnchor],
        [self.chatPane.bottomAnchor constraintEqualToAnchor:col.bottomAnchor],

        [self.createSessionPane.topAnchor constraintEqualToAnchor:self.chatPane.topAnchor],
        [self.createSessionPane.leadingAnchor constraintEqualToAnchor:self.chatPane.leadingAnchor],
        [self.createSessionPane.trailingAnchor constraintEqualToAnchor:self.chatPane.trailingAnchor],
        [self.createSessionPane.bottomAnchor constraintEqualToAnchor:self.chatPane.bottomAnchor],
    ]];
    return col;
}

- (NSView *)buildChatPane {
    NSView *pane = [[NSView alloc] initWithFrame:NSZeroRect];
    pane.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusDot = [[NSView alloc] initWithFrame:NSZeroRect];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 4.0;
    self.statusDot.layer.backgroundColor = NSColor.systemGrayColor.CGColor;

    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.maximumNumberOfLines = 2;

    self.focusTabButton = [NSButton buttonWithTitle:@"显示网页" target:self action:@selector(focusTabClicked:)];
    self.focusTabButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.focusTabButton.bezelStyle = NSBezelStyleRounded;
    self.focusTabButton.controlSize = NSControlSizeSmall;

    self.reopenButton = [NSButton buttonWithTitle:@"重新打开网页" target:self action:@selector(reopenClicked:)];
    self.reopenButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.reopenButton.bezelStyle = NSBezelStyleRounded;
    self.reopenButton.controlSize = NSControlSizeSmall;
    self.reopenButton.hidden = YES;

    self.moreButton = [NSButton buttonWithTitle:@"⋯" target:self action:@selector(moreClicked:)];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreButton.bezelStyle = NSBezelStyleInline;
    self.moreButton.bordered = NO;
    self.moreButton.toolTip = @"更多";

    self.chatPanel = [[BrowserAIAssistantChatPanel alloc] initWithFrame:NSZeroRect];
    self.chatPanel.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    inputScroll.translatesAutoresizingMaskIntoConstraints = NO;
    inputScroll.hasVerticalScroller = YES;
    inputScroll.borderType = NSBezelBorder;
    SBTextView *input = [SBTextView standardTextView];
    input.font = [NSFont systemFontOfSize:12];
    input.delegate = self;
    inputScroll.documentView = input;
    self.inputView = input;

    self.sendButton = [NSButton buttonWithTitle:@"发送" target:self action:@selector(sendClicked:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleRounded;

    self.cancelButton = [NSButton buttonWithTitle:@"停止" target:self action:@selector(cancelClicked:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.enabled = NO;

    for (NSView *v in @[self.statusDot, self.statusLabel, self.focusTabButton, self.reopenButton, self.moreButton,
                        self.chatPanel, inputScroll, self.sendButton, self.cancelButton]) {
        [pane addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.topAnchor constraintEqualToAnchor:pane.topAnchor constant:4],
        [self.statusDot.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.statusDot.widthAnchor constraintEqualToConstant:8],
        [self.statusDot.heightAnchor constraintEqualToConstant:8],

        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:6],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor constant:-6],

        [self.moreButton.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        [self.moreButton.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],

        [self.focusTabButton.topAnchor constraintEqualToAnchor:self.statusDot.bottomAnchor constant:8],
        [self.focusTabButton.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.reopenButton.centerYAnchor constraintEqualToAnchor:self.focusTabButton.centerYAnchor],
        [self.reopenButton.leadingAnchor constraintEqualToAnchor:self.focusTabButton.trailingAnchor constant:8],

        [self.chatPanel.topAnchor constraintEqualToAnchor:self.focusTabButton.bottomAnchor constant:8],
        [self.chatPanel.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.chatPanel.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        [self.chatPanel.heightAnchor constraintGreaterThanOrEqualToConstant:160],

        [inputScroll.topAnchor constraintEqualToAnchor:self.chatPanel.bottomAnchor constant:8],
        [inputScroll.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [inputScroll.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        [inputScroll.heightAnchor constraintEqualToConstant:80],

        [self.sendButton.topAnchor constraintEqualToAnchor:inputScroll.bottomAnchor constant:8],
        [self.sendButton.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.sendButton.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor constant:-14],

        [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.sendButton.trailingAnchor constant:8],
    ]];
    return pane;
}

- (NSView *)buildCreateSessionPane {
    NSView *pane = [[NSView alloc] initWithFrame:NSZeroRect];
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    pane.hidden = YES;

    NSTextField *caption = [NSTextField labelWithString:@"选择平台（将自动打开网页并绑定）"];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    self.providerStack = [NSStackView stackViewWithViews:@[]];
    self.providerStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.providerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.providerStack.spacing = 8;
    self.providerStack.alignment = NSLayoutAttributeLeading;

    for (NSDictionary *p in [BrowserAIAssistantPrompts providerCatalog]) {
        NSButton *btn = [NSButton buttonWithTitle:p[@"title"] ?: @""
                                           target:self
                                           action:@selector(providerPicked:)];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.bezelStyle = NSBezelStyleRounded;
        btn.identifier = p[@"id"];
        [btn.widthAnchor constraintEqualToConstant:220].active = YES;
        [self.providerStack addArrangedSubview:btn];
    }

    NSButton *cancel = [NSButton buttonWithTitle:@"取消" target:self action:@selector(backToChatClicked:)];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.controlSize = NSControlSizeSmall;

    [pane addSubview:caption];
    [pane addSubview:self.providerStack];
    [pane addSubview:cancel];
    [NSLayoutConstraint activateConstraints:@[
        [caption.topAnchor constraintEqualToAnchor:pane.topAnchor constant:8],
        [caption.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [caption.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        [self.providerStack.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:14],
        [self.providerStack.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [cancel.topAnchor constraintEqualToAnchor:self.providerStack.bottomAnchor constant:20],
        [cancel.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
    ]];
    return pane;
}

- (void)showPane:(AIAssistantPane)pane {
    self.pane = pane;
    self.chatPane.hidden = (pane != AIAssistantPaneChat);
    self.createSessionPane.hidden = (pane != AIAssistantPaneNewSession);
    if (pane == AIAssistantPaneNewSession) {
        self.titleLabel.stringValue = @"新建会话";
        self.titleLabel.editable = NO;
    } else {
        self.titleLabel.editable = YES;
        [self syncChatFromCurrentSession];
    }
}

#pragma mark - Width

- (void)applyWidth:(CGFloat)width {
    CGFloat next = width;
    if (next < kSidebarMinWidth) next = kSidebarMinWidth;
    if (next > kSidebarMaxWidth) next = kSidebarMaxWidth;
    self.currentWidth = next;
    if (self.visible) {
        self.widthConstraint.constant = next;
    }
}

- (void)persistWidth {
    BrowserAIAssistantPreferences.sharedPreferences.sidebarWidth = self.currentWidth;
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.visible = visible;
    self.view.hidden = NO;
    CGFloat target = visible ? self.currentWidth : 0;
    if (!visible) {
        [self.historyPopover performClose:nil];
    }
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.18;
            self.widthConstraint.animator.constant = target;
        } completionHandler:^{
            if (!visible) self.view.hidden = YES;
        }];
    } else {
        self.widthConstraint.constant = target;
        if (!visible) self.view.hidden = YES;
    }
    if (visible) {
        [self reloadUI];
    }
}

#pragma mark - Session helpers

- (AIAssistantSession *)currentSession {
    return AIAssistantSessionStore.sharedStore.currentSession;
}

- (NSString *)providerDisplayName:(NSString *)pid {
    for (NSDictionary *p in [BrowserAIAssistantPrompts providerCatalog]) {
        if ([p[@"id"] isEqualToString:pid]) {
            return p[@"title"] ?: pid;
        }
    }
    return pid ?: @"";
}

- (void)refreshConnectionState {
    for (AIAssistantSession *s in AIAssistantSessionStore.sharedStore.allSessionsSorted) {
        // 打开网页过程中不要改写状态，否则会变成 Detached 并被 prune 误删
        if (s.connection == AIAssistantSessionConnectionOpening) {
            continue;
        }
        if (s.bindingId.length == 0) {
            if (s.connection != AIAssistantSessionConnectionError) {
                s.connection = AIAssistantSessionConnectionDetached;
            }
            continue;
        }
        AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForId:s.bindingId];
        if (!b || !b.tab) {
            s.connection = AIAssistantSessionConnectionDetached;
        } else {
            s.connection = AIAssistantSessionConnectionReady;
            if (b.modelId.length) s.modelId = b.modelId;
        }
    }
}

- (void)syncChatFromCurrentSession {
    AIAssistantSession *s = [self currentSession];
    if (!s) {
        self.titleLabel.stringValue = @"AI 助手";
        [self.chatPanel clear];
        return;
    }
    self.titleLabel.stringValue = s.title.length ? s.title : @"新对话";
    [self.chatPanel reloadMessages:s.messages];
}

- (void)reloadUI {
    if (self.isResizingWidth) return;
    [self refreshConnectionState];
    if (self.pane == AIAssistantPaneNewSession) {
        return;
    }

    AIAssistantSession *s = [self currentSession];
    if (!s) {
        self.titleLabel.stringValue = @"AI 助手";
        self.statusLabel.stringValue = @"还没有会话，点击左侧 ＋ 开始";
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
        self.statusDot.layer.backgroundColor = NSColor.systemGrayColor.CGColor;
        self.sendButton.enabled = NO;
        self.focusTabButton.enabled = NO;
        self.reopenButton.hidden = YES;
        self.cancelButton.enabled = self.inFlight;
        return;
    }

    self.titleLabel.stringValue = s.title.length ? s.title : @"新对话";
    NSString *platform = [self providerDisplayName:s.providerId];
    BOOL ready = (s.connection == AIAssistantSessionConnectionReady && s.modelId.length > 0);
    BOOL detached = (s.connection == AIAssistantSessionConnectionDetached);
    self.reopenButton.hidden = !detached;
    self.focusTabButton.enabled = ready;
    self.focusTabButton.hidden = detached;

    if (detached) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ · 网页已关闭", platform];
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        self.statusDot.layer.backgroundColor = NSColor.systemOrangeColor.CGColor;
        self.sendButton.enabled = NO;
    } else if (ready) {
        AIBridgeService *svc = AIBridgeService.sharedService;
        NSString *extra = svc.isListening ? (svc.statusText ?: @"就绪") : @"发送时将启动 Bridge";
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", platform, extra];
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
        self.statusDot.layer.backgroundColor = NSColor.systemGreenColor.CGColor;
        self.sendButton.enabled = !self.inFlight;
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ · 连接中…", platform];
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
        self.statusDot.layer.backgroundColor = NSColor.systemYellowColor.CGColor;
        self.sendButton.enabled = NO;
    }
    self.cancelButton.enabled = self.inFlight;
}

#pragma mark - History popover

- (void)applyHistoryPopoverSize:(NSSize)size {
    if (!self.historyPopover) return;
    self.historyPopover.contentSize = size;
    self.historyPopover.contentViewController.preferredContentSize = size;
}

- (void)ensureHistoryPopover {
    if (self.historyPopover) return;
    AIAssistantHistoryPanel *panel = [[AIAssistantHistoryPanel alloc] initWithFrame:NSMakeRect(0, 0, 320, 120)];
    __weak typeof(self) weakSelf = self;
    panel.onSelectSession = ^(AIAssistantSession *session) {
        [weakSelf selectSessionFromHistory:session];
    };
    panel.onTogglePin = ^(AIAssistantSession *session) {
        [AIAssistantSessionStore.sharedStore setPinned:!session.pinned forSessionId:session.sessionId];
        [weakSelf.historyPanel reload];
    };
    panel.onDeleteSession = ^(AIAssistantSession *session) {
        [weakSelf deleteSessionFromHistory:session];
    };
    panel.onPreferredSizeChanged = ^(NSSize size) {
        [weakSelf applyHistoryPopoverSize:size];
    };
    self.historyPanel = panel;
    [panel reload];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = panel;
    vc.preferredContentSize = [panel preferredPopoverSize];

    NSPopover *pop = [[NSPopover alloc] init];
    pop.contentViewController = vc;
    pop.behavior = NSPopoverBehaviorTransient;
    pop.delegate = self;
    pop.contentSize = [panel preferredPopoverSize];
    self.historyPopover = pop;
}

- (void)selectSessionFromHistory:(AIAssistantSession *)session {
    [self.historyPopover performClose:nil];
    AIAssistantSessionStore.sharedStore.currentSessionId = session.sessionId;
    [self showPane:AIAssistantPaneChat];
    [self syncChatFromCurrentSession];
    [self reloadUI];
}

- (void)deleteSessionFromHistory:(AIAssistantSession *)session {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除该会话？";
    alert.informativeText = session.title.length ? session.title : @"新对话";
    [alert addButtonWithTitle:@"删除并解绑"];
    [alert addButtonWithTitle:@"仅删除会话"];
    [alert addButtonWithTitle:@"取消"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertThirdButtonReturn) return;
    if (r == NSAlertFirstButtonReturn && session.bindingId.length) {
        [[AIBridgeService sharedService] unbindBindingId:session.bindingId];
    }
    NSString *deletedId = session.sessionId;
    [AIAssistantSessionStore.sharedStore deleteSessionId:deletedId];
    [self.historyPanel reload];
    if ([[self currentSession].sessionId isEqualToString:deletedId] || ![self currentSession]) {
        [self syncChatFromCurrentSession];
    }
    [self reloadUI];
}

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
}

#pragma mark - Text

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (textView != self.inputView) return NO;
    if (commandSelector == @selector(insertNewline:)) {
        NSEvent *e = NSApp.currentEvent;
        BOOL shift = (e.modifierFlags & NSEventModifierFlagShift) != 0;
        if (shift) return NO;
        if (!self.inFlight && self.sendButton.enabled) {
            [self sendClicked:nil];
        }
        return YES;
    }
    return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object == self.titleLabel) {
        AIAssistantSession *s = [self currentSession];
        if (!s) return;
        NSString *t = [self.titleLabel.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length == 0) t = @"新对话";
        s.title = t;
        [AIAssistantSessionStore.sharedStore touchAndPersist:s];
    }
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.historyPopover performClose:nil];
    [self.delegate aiAssistantSidebarDidRequestClose:self];
}

- (void)openBridgeClicked:(id)sender {
    (void)sender;
    [self.historyPopover performClose:nil];
    [self.delegate aiAssistantSidebarDidRequestOpenBridge:self];
}

- (void)placeholderClicked:(id)sender {
    (void)sender;
    NSButton *b = [sender isKindOfClass:[NSButton class]] ? sender : nil;
    NSString *tip = b.toolTip.length ? b.toolTip : @"即将推出";
    self.statusLabel.stringValue = tip;
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
}

- (void)historyClicked:(id)sender {
    (void)sender;
    [self ensureHistoryPopover];
    if (self.historyPopover.shown) {
        [self.historyPopover performClose:nil];
        return;
    }
    [self.historyPanel reload];
    [self applyHistoryPopoverSize:[self.historyPanel preferredPopoverSize]];
    [self.historyPopover showRelativeToRect:self.historyButton.bounds
                                     ofView:self.historyButton
                              preferredEdge:NSRectEdgeMaxX];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyHistoryPopoverSize:[self.historyPanel preferredPopoverSize]];
        [self.historyPanel focusSearch];
    });
}

- (void)backToChatClicked:(id)sender {
    (void)sender;
    [self showPane:AIAssistantPaneChat];
    [self reloadUI];
}

- (void)newClicked:(id)sender {
    (void)sender;
    [self.historyPopover performClose:nil];
    [self showPane:AIAssistantPaneNewSession];
}

- (void)providerPicked:(NSButton *)sender {
    NSString *pid = sender.identifier;
    if (pid.length == 0) return;
    [self createSessionWithProviderId:pid];
}

- (void)createSessionWithProviderId:(NSString *)providerId {
    BrowserAIAssistantPreferences.sharedPreferences.lastProviderId = providerId;
    AIAssistantSession *session = [AIAssistantSessionStore.sharedStore createSessionWithProviderId:providerId
                                                                                         bindingId:nil
                                                                                           modelId:nil
                                                                                             title:@"新对话"];
    session.connection = AIAssistantSessionConnectionOpening;
    [AIAssistantSessionStore.sharedStore saveSession:session];
    [self showPane:AIAssistantPaneChat];
    [self syncChatFromCurrentSession];
    self.statusLabel.stringValue = @"正在打开网页…";
    self.statusDot.layer.backgroundColor = NSColor.systemYellowColor.CGColor;
    self.sendButton.enabled = NO;

    id<BrowserAIAssistantSidebarControllerDelegate> del = self.delegate;
    if (![del respondsToSelector:@selector(aiAssistantSidebar:openAndBindProviderId:sessionId:completion:)]) {
        self.statusLabel.stringValue = @"无法打开网页（无窗口委托）";
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSString *sid = session.sessionId;
    [del aiAssistantSidebar:self openAndBindProviderId:providerId sessionId:sid completion:^(AIBridgeBinding *binding, NSString *errorDetail) {
        AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sid];
        if (!s) return;
        if (!binding) {
            s.connection = AIAssistantSessionConnectionError;
            [AIAssistantSessionStore.sharedStore saveSession:s];
            weakSelf.statusLabel.stringValue = errorDetail.length ? errorDetail : @"打开失败";
            weakSelf.statusLabel.textColor = NSColor.systemRedColor;
            weakSelf.statusDot.layer.backgroundColor = NSColor.systemRedColor.CGColor;
            [weakSelf reloadUI];
            return;
        }
        binding.sessionId = sid;
        s.bindingId = binding.bindingId;
        s.modelId = binding.modelId;
        s.connection = AIAssistantSessionConnectionReady;
        [AIAssistantSessionStore.sharedStore touchAndPersist:s];
        BrowserAIAssistantPreferences.sharedPreferences.lastModelId = binding.modelId ?: @"";
        [weakSelf reloadUI];
    }];
}

- (void)focusTabClicked:(id)sender {
    (void)sender;
    AIAssistantSession *s = [self currentSession];
    if (!s.bindingId.length) return;
    [self.delegate aiAssistantSidebar:self focusTabForBindingId:s.bindingId];
}

- (void)reopenClicked:(id)sender {
    (void)sender;
    AIAssistantSession *s = [self currentSession];
    if (!s) return;
    // 清掉失效 binding，避免 Opening 期间被 prune 当成「标签已死」删掉
    s.bindingId = nil;
    s.modelId = nil;
    s.connection = AIAssistantSessionConnectionOpening;
    [AIAssistantSessionStore.sharedStore saveSession:s];
    [self reloadUI];
    __weak typeof(self) weakSelf = self;
    NSString *sid = s.sessionId;
    NSString *pid = s.providerId;
    [self.delegate aiAssistantSidebar:self reopenAndBindProviderId:pid sessionId:sid completion:^(AIBridgeBinding *binding, NSString *errorDetail) {
        AIAssistantSession *sess = [AIAssistantSessionStore.sharedStore sessionForId:sid];
        if (!sess) return;
        if (!binding) {
            sess.connection = AIAssistantSessionConnectionDetached;
            [AIAssistantSessionStore.sharedStore saveSession:sess];
            weakSelf.statusLabel.stringValue = errorDetail.length ? errorDetail : @"重新打开失败";
            [weakSelf reloadUI];
            return;
        }
        binding.sessionId = sid;
        sess.bindingId = binding.bindingId;
        sess.modelId = binding.modelId;
        sess.connection = AIAssistantSessionConnectionReady;
        [AIAssistantSessionStore.sharedStore touchAndPersist:sess];
        [weakSelf reloadUI];
    }];
}

- (void)moreClicked:(id)sender {
    NSButton *btn = (NSButton *)sender;
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"导出会话到剪贴板" action:@selector(exportClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"删除当前会话" action:@selector(deleteCurrentClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"打开 AI Bridge…" action:@selector(openBridgeClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [NSMenu popUpContextMenu:menu withEvent:NSApp.currentEvent forView:btn];
}

- (void)exportClicked:(id)sender {
    (void)sender;
    AIAssistantSession *s = [self currentSession];
    if (!s) return;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"# %@\n平台: %@\n\n", s.title ?: @"会话", [self providerDisplayName:s.providerId]];
    for (AIAssistantMessage *m in s.messages) {
        [out appendFormat:@"## %@\n%@\n\n", m.role, m.content];
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:out forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"已复制到剪贴板";
}

- (void)deleteCurrentClicked:(id)sender {
    (void)sender;
    AIAssistantSession *s = [self currentSession];
    if (!s) return;
    [self deleteSessionFromHistory:s];
    [self.historyPopover performClose:nil];
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    [[BrowserAIAssistantClient sharedClient] cancelInFlight];
    self.inFlight = NO;
    self.inFlightSessionId = nil;
    AIAssistantSession *s = [self currentSession];
    if (s) {
        AIAssistantMessage *m = [AIAssistantMessage messageWithRole:@"system" content:@"已取消"];
        [s.messages addObject:m];
        [AIAssistantSessionStore.sharedStore touchAndPersist:s];
        [self.chatPanel appendSystemText:@"已取消"];
    }
    [self reloadUI];
}

- (void)sendClicked:(id)sender {
    (void)sender;
    NSString *prompt = [self.inputView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self sendPrompt:prompt clearInput:YES];
}

- (void)sendPrompt:(NSString *)prompt clearInput:(BOOL)clearInput {
    if (self.inFlight) return;
    NSString *text = [prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) {
        self.statusLabel.stringValue = @"请输入提示词";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    AIAssistantSession *s = [self currentSession];
    if (!s) {
        self.pendingProviderId = BrowserAIAssistantPreferences.sharedPreferences.lastProviderId ?: @"deepseek";
        self.inputView.string = text;
        [self createSessionWithProviderId:self.pendingProviderId];
        self.statusLabel.stringValue = @"已创建会话并开页，就绪后请再次发送";
        return;
    }
    if (s.connection != AIAssistantSessionConnectionReady || s.modelId.length == 0) {
        self.statusLabel.stringValue = @"网页未就绪，请等待或点「重新打开网页」";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }

    BOOL firstUser = YES;
    for (AIAssistantMessage *m in s.messages) {
        if ([m.role isEqualToString:@"user"]) { firstUser = NO; break; }
    }
    AIAssistantMessage *userMsg = [AIAssistantMessage messageWithRole:@"user" content:text];
    [s.messages addObject:userMsg];
    if (firstUser && [s.title isEqualToString:@"新对话"]) {
        NSString *t = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (t.length > 24) t = [[t substringToIndex:24] stringByAppendingString:@"…"];
        s.title = t;
        self.titleLabel.stringValue = t;
    }
    [AIAssistantSessionStore.sharedStore touchAndPersist:s];
    [self.chatPanel appendUserText:text];
    if (clearInput) self.inputView.string = @"";

    NSString *model = s.modelId;
    NSString *sid = s.sessionId;
    BrowserAIAssistantPreferences.sharedPreferences.lastModelId = model;
    self.inFlight = YES;
    self.inFlightSessionId = sid;
    [self reloadUI];
    self.statusLabel.stringValue = @"请求中…";

    __weak typeof(self) weakSelf = self;
    [[BrowserAIAssistantClient sharedClient] chatWithModel:model prompt:text completion:^(NSInteger httpStatus, NSString *assistantText, NSString *errorMessage) {
        weakSelf.inFlight = NO;
        weakSelf.inFlightSessionId = nil;
        AIAssistantSession *sess = [AIAssistantSessionStore.sharedStore sessionForId:sid];
        if (errorMessage.length) {
            NSString *sys = [NSString stringWithFormat:@"HTTP %ld · %@", (long)httpStatus, errorMessage];
            if (sess) {
                [sess.messages addObject:[AIAssistantMessage messageWithRole:@"system" content:sys]];
                [AIAssistantSessionStore.sharedStore touchAndPersist:sess];
            }
            if ([[weakSelf currentSession].sessionId isEqualToString:sid]) {
                [weakSelf.chatPanel appendSystemText:sys];
            }
            weakSelf.statusLabel.stringValue = errorMessage;
            weakSelf.statusLabel.textColor = NSColor.systemRedColor;
        } else {
            NSString *reply = assistantText ?: @"";
            if (sess) {
                [sess.messages addObject:[AIAssistantMessage messageWithRole:@"assistant" content:reply]];
                [AIAssistantSessionStore.sharedStore touchAndPersist:sess];
            }
            if ([[weakSelf currentSession].sessionId isEqualToString:sid]) {
                [weakSelf.chatPanel appendAssistantMarkdown:reply];
            }
            weakSelf.statusLabel.stringValue = [NSString stringWithFormat:@"完成 · HTTP %ld", (long)httpStatus];
            weakSelf.statusLabel.textColor = NSColor.systemGreenColor;
        }
        [weakSelf reloadUI];
    }];
}

- (void)presentAction:(NSString *)actionKey
              context:(NSString *)context
          pageContext:(BOOL)pageContext
             autoSend:(BOOL)autoSend {
    NSString *prompt = [BrowserAIAssistantPrompts promptForAction:actionKey
                                                          context:context ?: @""
                                                      pageContext:pageContext];
    [self showPane:AIAssistantPaneChat];
    AIAssistantSession *s = [self currentSession];
    if (!s) {
        self.inputView.string = prompt;
        NSString *pid = BrowserAIAssistantPreferences.sharedPreferences.lastProviderId ?: @"deepseek";
        [self createSessionWithProviderId:pid];
        self.statusLabel.stringValue = @"已创建会话，网页就绪后将可发送";
        return;
    }
    self.inputView.string = prompt;
    [self reloadUI];
    if (autoSend && s.connection == AIAssistantSessionConnectionReady && s.modelId.length) {
        [self sendPrompt:prompt clearInput:YES];
    } else {
        NSString *title = [BrowserAIAssistantPrompts displayTitleForAction:actionKey pageContext:pageContext];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已填入「%@」，可编辑后发送", title];
    }
}

@end
