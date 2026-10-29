#import "BrowserAIAssistantSidebarController.h"
#import "BrowserAIAssistantPreferences.h"
#import "BrowserAIAssistantPrompts.h"
#import "BrowserAIAssistantClient.h"
#import "BrowserAIAssistantChatPanel.h"
#import "AIAssistantSession.h"
#import "AIAssistantSessionStore.h"
#import "AIAssistantCitation.h"
#import "AIAssistantHistoryPanel.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeService.h"
#import "AIPageContextCapturer.h"
#import "AIPageContextBundle.h"
#import "AIPageContextResource.h"
#import "AIPageContextStore.h"
#import "AIPageContextRecipe.h"
#import "AIPageContextRecipeStore.h"
#import "AIPageContextPromptBuilder.h"
#import "AIPageContextBundleExporter.h"
#import "AIPageContextScraperBridge.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserDownloadManager.h"
#import "SBTextView.h"
#import "SBTextField.h"

static const NSUInteger kPageContextPromptBudget = 32000;
static const CGFloat kPageContextPanelHeight = 210.0;

static const CGFloat kSidebarDefaultWidth = 400.0;
static const CGFloat kSidebarMinWidth = 320.0;
static const CGFloat kSidebarMaxWidthFraction = 0.80;
static const CGFloat kRailWidth = 44.0;
static const CGFloat kCitationChipRowHeight = 24.0;
static const CGFloat kCitationChipSpacing = 4.0;
static const CGFloat kCitationMaxVisibleRows = 3.0;
static const CGFloat kInputCornerRadius = 12.0;

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
@property (nonatomic, strong) NSStackView *recipeButtonStack;
@property (nonatomic, strong) NSButton *summarizePageButton;
@property (nonatomic, strong) NSButton *askPageButton;
@property (nonatomic, strong) NSButton *pageContextToggleButton;
@property (nonatomic, strong) NSButton *pageContextRecaptureButton;
@property (nonatomic, strong) NSView *pageContextPanel;
@property (nonatomic, strong) NSLayoutConstraint *pageContextPanelHeightConstraint;
@property (nonatomic, strong) NSStackView *layerCheckboxStack;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *layerCheckboxes;
@property (nonatomic, strong) NSScrollView *resourceScroll;
@property (nonatomic, strong) NSStackView *resourceStack;
@property (nonatomic, assign) BOOL pageContextExpanded;
@property (nonatomic, strong, nullable) AIPageContextBundle *currentPageBundle;
@property (nonatomic, copy, nullable) NSDictionary *lastPagePickResult;
@property (nonatomic, copy, nullable) NSString *pendingRegexPatternOverride;
@property (nonatomic, strong, nullable) NSPopover *citationPreviewPopover;
@property (nonatomic, strong, nullable) NSPopover *mentionPopover;
@property (nonatomic, assign) BOOL suppressMention;
@property (nonatomic, strong) NSScrollView *citationScroll;
@property (nonatomic, strong) NSStackView *citationStack;
@property (nonatomic, strong) NSLayoutConstraint *citationHeightConstraint;
@property (nonatomic, strong) NSMutableArray<AIAssistantCitation *> *citations;
@property (nonatomic, strong) NSBox *inputBox;
@property (nonatomic, strong) NSScrollView *inputScroll;
@property (nonatomic, strong) SBTextView *inputView;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, copy, nullable) NSString *pendingSystemHint;

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
        if (w < kSidebarMinWidth) w = kSidebarDefaultWidth;
        _currentWidth = w;
        _pane = AIAssistantPaneChat;
        _citations = [NSMutableArray array];
        _layerCheckboxes = [NSMutableDictionary dictionary];
        _pageContextExpanded = NO;
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
        [weakSelf reloadCitationChips];
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

    self.summarizePageButton = [NSButton buttonWithTitle:@"总结该网页"
                                                  target:self
                                                  action:@selector(summarizePageClicked:)];
    self.summarizePageButton.bezelStyle = NSBezelStyleRounded;
    self.summarizePageButton.controlSize = NSControlSizeSmall;
    self.summarizePageButton.toolTip = @"采集当前标签页正文并总结";

    self.askPageButton = [NSButton buttonWithTitle:@"问答本页"
                                            target:self
                                            action:@selector(askPageClicked:)];
    self.askPageButton.bezelStyle = NSBezelStyleRounded;
    self.askPageButton.controlSize = NSControlSizeSmall;
    self.askPageButton.toolTip = @"采集正文并填入问答提示（不自动发送）";

    self.recipeButtonStack = [NSStackView stackViewWithViews:@[self.summarizePageButton, self.askPageButton]];
    self.recipeButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.recipeButtonStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.recipeButtonStack.spacing = 6;
    self.recipeButtonStack.alignment = NSLayoutAttributeCenterY;

    self.pageContextToggleButton = [NSButton buttonWithTitle:@"本页上下文 · 未采集"
                                                      target:self
                                                      action:@selector(pageContextToggleClicked:)];
    self.pageContextToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageContextToggleButton.bezelStyle = NSBezelStyleInline;
    self.pageContextToggleButton.bordered = NO;
    self.pageContextToggleButton.font = [NSFont systemFontOfSize:11];
    self.pageContextToggleButton.alignment = NSTextAlignmentLeft;
    self.pageContextToggleButton.toolTip = @"展开资源盘，勾选要引用的层";

    self.pageContextRecaptureButton = [NSButton buttonWithTitle:@"重采"
                                                         target:self
                                                         action:@selector(pageContextRecaptureClicked:)];
    self.pageContextRecaptureButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageContextRecaptureButton.bezelStyle = NSBezelStyleRounded;
    self.pageContextRecaptureButton.controlSize = NSControlSizeMini;
    self.pageContextRecaptureButton.toolTip = @"重新采集当前标签页";

    self.pageContextPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    self.pageContextPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageContextPanel.hidden = YES;
    self.pageContextPanelHeightConstraint = [self.pageContextPanel.heightAnchor constraintEqualToConstant:0];

    self.layerCheckboxStack = [NSStackView stackViewWithViews:@[]];
    self.layerCheckboxStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.layerCheckboxStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.layerCheckboxStack.spacing = 2;
    self.layerCheckboxStack.alignment = NSLayoutAttributeLeading;
    [self.pageContextPanel addSubview:self.layerCheckboxStack];

    NSStackView *layerActions = [NSStackView stackViewWithViews:@[]];
    layerActions.translatesAutoresizingMaskIntoConstraints = NO;
    layerActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    layerActions.spacing = 6;
    NSButton *onlyArticle = [NSButton buttonWithTitle:@"仅正文" target:self action:@selector(pageContextOnlyArticleClicked:)];
    onlyArticle.bezelStyle = NSBezelStyleRounded;
    onlyArticle.controlSize = NSControlSizeMini;
    NSButton *attachAll = [NSButton buttonWithTitle:@"全部引用…" target:self action:@selector(pageContextAttachAllClicked:)];
    attachAll.bezelStyle = NSBezelStyleRounded;
    attachAll.controlSize = NSControlSizeMini;
    [layerActions addArrangedSubview:onlyArticle];
    [layerActions addArrangedSubview:attachAll];
    [self.pageContextPanel addSubview:layerActions];

    AIPageContextBundle *nameHelper = [[AIPageContextBundle alloc] init];
    for (NSString *layerId in [AIPageContextBundle allLayerIds]) {
        NSButton *cb = [NSButton checkboxWithTitle:[nameHelper displayNameForLayer:layerId]
                                            target:self
                                            action:@selector(pageContextLayerToggled:)];
        cb.translatesAutoresizingMaskIntoConstraints = NO;
        cb.identifier = layerId;
        cb.font = [NSFont systemFontOfSize:11];
        cb.controlSize = NSControlSizeSmall;
        self.layerCheckboxes[layerId] = cb;
        [self.layerCheckboxStack addArrangedSubview:cb];
    }

    NSTextField *resCaption = [NSTextField labelWithString:@"资源"];
    resCaption.translatesAutoresizingMaskIntoConstraints = NO;
    resCaption.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    resCaption.textColor = NSColor.secondaryLabelColor;
    [self.pageContextPanel addSubview:resCaption];

    self.resourceScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.resourceScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.resourceScroll.hasVerticalScroller = YES;
    self.resourceScroll.autohidesScrollers = YES;
    self.resourceScroll.borderType = NSNoBorder;
    self.resourceScroll.drawsBackground = NO;
    self.resourceStack = [NSStackView stackViewWithViews:@[]];
    self.resourceStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.resourceStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.resourceStack.spacing = 2;
    self.resourceStack.alignment = NSLayoutAttributeLeading;
    self.resourceScroll.documentView = self.resourceStack;
    [self.pageContextPanel addSubview:self.resourceScroll];

    [NSLayoutConstraint activateConstraints:@[
        [self.layerCheckboxStack.topAnchor constraintEqualToAnchor:self.pageContextPanel.topAnchor],
        [self.layerCheckboxStack.leadingAnchor constraintEqualToAnchor:self.pageContextPanel.leadingAnchor],
        [self.layerCheckboxStack.trailingAnchor constraintEqualToAnchor:self.pageContextPanel.trailingAnchor],
        [layerActions.topAnchor constraintEqualToAnchor:self.layerCheckboxStack.bottomAnchor constant:2],
        [layerActions.leadingAnchor constraintEqualToAnchor:self.pageContextPanel.leadingAnchor],
        [resCaption.topAnchor constraintEqualToAnchor:layerActions.bottomAnchor constant:4],
        [resCaption.leadingAnchor constraintEqualToAnchor:self.pageContextPanel.leadingAnchor],
        [self.resourceScroll.topAnchor constraintEqualToAnchor:resCaption.bottomAnchor constant:2],
        [self.resourceScroll.leadingAnchor constraintEqualToAnchor:self.pageContextPanel.leadingAnchor],
        [self.resourceScroll.trailingAnchor constraintEqualToAnchor:self.pageContextPanel.trailingAnchor],
        [self.resourceScroll.bottomAnchor constraintEqualToAnchor:self.pageContextPanel.bottomAnchor],
        [self.resourceStack.topAnchor constraintEqualToAnchor:self.resourceScroll.contentView.topAnchor],
        [self.resourceStack.leadingAnchor constraintEqualToAnchor:self.resourceScroll.contentView.leadingAnchor],
        [self.resourceStack.widthAnchor constraintEqualToAnchor:self.resourceScroll.contentView.widthAnchor],
    ]];

    self.citationScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.citationScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.citationScroll.hasHorizontalScroller = NO;
    self.citationScroll.hasVerticalScroller = YES;
    self.citationScroll.autohidesScrollers = YES;
    self.citationScroll.borderType = NSNoBorder;
    self.citationScroll.drawsBackground = NO;
    self.citationScroll.horizontalScrollElasticity = NSScrollElasticityNone;
    self.citationScroll.hidden = YES;

    self.citationStack = [NSStackView stackViewWithViews:@[]];
    self.citationStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.citationStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.citationStack.alignment = NSLayoutAttributeLeading;
    self.citationStack.spacing = kCitationChipSpacing;
    self.citationStack.edgeInsets = NSEdgeInsetsMake(2, 0, 2, 0);
    self.citationScroll.documentView = self.citationStack;
    self.citationHeightConstraint = [self.citationScroll.heightAnchor constraintEqualToConstant:0];

    NSBox *inputBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    inputBox.translatesAutoresizingMaskIntoConstraints = NO;
    inputBox.titlePosition = NSNoTitle;
    inputBox.boxType = NSBoxCustom;
    inputBox.borderType = NSLineBorder;
    inputBox.borderWidth = 1.0;
    inputBox.cornerRadius = kInputCornerRadius;
    inputBox.contentViewMargins = NSZeroSize;
    inputBox.fillColor = NSColor.textBackgroundColor;
    if (@available(macOS 10.14, *)) {
        inputBox.borderColor = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
            NSAppearanceName matched =
                [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            if ([matched isEqualToString:NSAppearanceNameDarkAqua]) {
                return [NSColor colorWithCalibratedWhite:1.0 alpha:0.28];
            }
            return [NSColor colorWithCalibratedWhite:0.0 alpha:0.20];
        }];
    } else {
        inputBox.borderColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.22];
    }

    NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    inputScroll.translatesAutoresizingMaskIntoConstraints = NO;
    inputScroll.hasVerticalScroller = YES;
    inputScroll.autohidesScrollers = YES;
    inputScroll.borderType = NSNoBorder;
    inputScroll.drawsBackground = NO;
    SBTextView *input = [SBTextView standardTextView];
    input.font = [NSFont systemFontOfSize:12];
    input.delegate = self;
    input.drawsBackground = NO;
    input.textContainerInset = NSMakeSize(8, 8);
    inputScroll.documentView = input;
    [inputBox.contentView addSubview:inputScroll];
    [NSLayoutConstraint activateConstraints:@[
        [inputScroll.topAnchor constraintEqualToAnchor:inputBox.contentView.topAnchor],
        [inputScroll.leadingAnchor constraintEqualToAnchor:inputBox.contentView.leadingAnchor],
        [inputScroll.trailingAnchor constraintEqualToAnchor:inputBox.contentView.trailingAnchor],
        [inputScroll.bottomAnchor constraintEqualToAnchor:inputBox.contentView.bottomAnchor],
    ]];
    self.inputBox = inputBox;
    self.inputScroll = inputScroll;
    self.inputView = input;

    self.sendButton = [NSButton buttonWithTitle:@"发送" target:self action:@selector(sendClicked:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleRounded;

    self.cancelButton = [NSButton buttonWithTitle:@"停止" target:self action:@selector(cancelClicked:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.enabled = NO;

    for (NSView *v in @[self.statusDot, self.statusLabel, self.focusTabButton, self.reopenButton, self.moreButton,
                        self.chatPanel, self.recipeButtonStack, self.pageContextToggleButton, self.pageContextRecaptureButton,
                        self.pageContextPanel, self.citationScroll, inputBox, self.sendButton, self.cancelButton]) {
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
        [self.chatPanel.heightAnchor constraintGreaterThanOrEqualToConstant:120],

        [self.recipeButtonStack.topAnchor constraintEqualToAnchor:self.chatPanel.bottomAnchor constant:6],
        [self.recipeButtonStack.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],

        [self.pageContextToggleButton.topAnchor constraintEqualToAnchor:self.recipeButtonStack.bottomAnchor constant:4],
        [self.pageContextToggleButton.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.pageContextToggleButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.pageContextRecaptureButton.leadingAnchor constant:-6],

        [self.pageContextRecaptureButton.centerYAnchor constraintEqualToAnchor:self.pageContextToggleButton.centerYAnchor],
        [self.pageContextRecaptureButton.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],

        [self.pageContextPanel.topAnchor constraintEqualToAnchor:self.pageContextToggleButton.bottomAnchor constant:2],
        [self.pageContextPanel.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.pageContextPanel.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        self.pageContextPanelHeightConstraint,

        [self.citationScroll.topAnchor constraintEqualToAnchor:self.pageContextPanel.bottomAnchor constant:6],
        [self.citationScroll.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [self.citationScroll.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        self.citationHeightConstraint,

        [self.citationStack.topAnchor constraintEqualToAnchor:self.citationScroll.contentView.topAnchor],
        [self.citationStack.leadingAnchor constraintEqualToAnchor:self.citationScroll.contentView.leadingAnchor],
        [self.citationStack.widthAnchor constraintEqualToAnchor:self.citationScroll.contentView.widthAnchor],

        [inputBox.topAnchor constraintEqualToAnchor:self.citationScroll.bottomAnchor constant:6],
        [inputBox.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:12],
        [inputBox.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-12],
        [inputBox.heightAnchor constraintEqualToConstant:80],

        [self.sendButton.topAnchor constraintEqualToAnchor:inputBox.bottomAnchor constant:8],
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

- (CGFloat)effectiveMaxWidth {
    CGFloat hostW = 0;
    NSView *host = self.view.superview;
    if (host && NSWidth(host.bounds) > 1) {
        hostW = NSWidth(host.bounds);
    } else if (self.view.window.contentView) {
        hostW = NSWidth(self.view.window.contentView.bounds);
    } else if (self.view.window) {
        hostW = NSWidth(self.view.window.frame);
    }
    if (hostW < kSidebarMinWidth) {
        return 1200.0; // 尚未入窗时给较宽临时上限，真正拖拽时会再按窗口裁
    }
    return MAX(kSidebarMinWidth, floor(hostW * kSidebarMaxWidthFraction));
}

- (void)applyWidth:(CGFloat)width {
    CGFloat next = width;
    if (next < kSidebarMinWidth) next = kSidebarMinWidth;
    CGFloat maxW = [self effectiveMaxWidth];
    if (next > maxW) next = maxW;
    self.currentWidth = next;
    if (self.visible) {
        self.widthConstraint.constant = next;
    }
    if (self.citations.count > 0 && !self.isResizingWidth) {
        [self reloadCitationChips];
    }
}

- (void)persistWidth {
    BrowserAIAssistantPreferences.sharedPreferences.sidebarWidth = self.currentWidth;
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.visible = visible;
    self.view.hidden = NO;
    if (visible) {
        [self applyWidth:self.currentWidth];
    }
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
            else [self reloadCitationChips];
        }];
    } else {
        self.widthConstraint.constant = target;
        if (!visible) self.view.hidden = YES;
        else [self reloadCitationChips];
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
        [self refreshPageContextTray];
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
    [self refreshPageContextTray];
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

    NSMenu *recipeMenu = [[NSMenu alloc] init];
    for (AIPageContextRecipe *r in [[AIPageContextRecipeStore sharedStore] allRecipes]) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:r.title
                                                    action:@selector(runRecipeFromMenu:)
                                             keyEquivalent:@""];
        it.target = self;
        it.representedObject = r.recipeId;
        [recipeMenu addItem:it];
    }
    NSMenuItem *runRecipes = [[NSMenuItem alloc] initWithTitle:@"运行配方" action:nil keyEquivalent:@""];
    runRecipes.submenu = recipeMenu;
    [menu addItem:runRecipes];

    [menu addItemWithTitle:@"管理用户配方…" action:@selector(manageRecipesClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;

    NSMenu *privMenu = [[NSMenu alloc] init];
    NSString *cur = BrowserAIAssistantPreferences.sharedPreferences.pageContextPrivacyMode ?: @"standard";
    NSArray *modes = @[
        @[@"严格（禁 HTML/脚本）", @"strict"],
        @[@"标准（默认）", @"standard"],
        @[@"开发（允许脚本资源）", @"developer"],
    ];
    for (NSArray *m in modes) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:m[0]
                                                    action:@selector(privacyModeClicked:)
                                             keyEquivalent:@""];
        it.target = self;
        it.representedObject = m[1];
        it.state = [cur isEqualToString:m[1]] ? NSControlStateValueOn : NSControlStateValueOff;
        [privMenu addItem:it];
    }
    NSMenuItem *privItem = [[NSMenuItem alloc] initWithTitle:@"页面上下文隐私" action:nil keyEquivalent:@""];
    privItem.submenu = privMenu;
    [menu addItem:privItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"导出 Bundle 到剪贴板" action:@selector(exportCurrentBundleToPasteboard) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"导出 Bundle 到下载目录" action:@selector(exportCurrentBundleToDownloads) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"应用到页面爬虫…" action:@selector(applyCurrentContextToScraperDraft) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"点选区域加入引用…" action:@selector(startPickPageSubtreeForCitation) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"Regex Lab…" action:@selector(showRegexLab) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"导出会话到剪贴板" action:@selector(exportClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItemWithTitle:@"删除当前会话" action:@selector(deleteCurrentClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"打开 AI Bridge…" action:@selector(openBridgeClicked:) keyEquivalent:@""];
    menu.itemArray.lastObject.target = self;
    [NSMenu popUpContextMenu:menu withEvent:NSApp.currentEvent forView:btn];
}

- (void)runRecipeFromMenu:(NSMenuItem *)sender {
    NSString *rid = sender.representedObject;
    if (![rid isKindOfClass:[NSString class]]) return;
    BOOL autoSend = [rid isEqualToString:AIPageContextRecipeIDSummarizePage];
    [self presentPageRecipe:rid autoSend:autoSend];
}

- (void)privacyModeClicked:(NSMenuItem *)sender {
    NSString *mode = sender.representedObject;
    if (![mode isKindOfClass:[NSString class]]) return;
    BrowserAIAssistantPreferences.sharedPreferences.pageContextPrivacyMode = mode;
    [self refreshPageContextTray];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"隐私档：%@", mode];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
}

- (void)manageRecipesClicked:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"管理用户配方";
    alert.informativeText = @"可将内置配方复制为可编辑的用户配方（保存到 Application Support）。";
    [alert addButtonWithTitle:@"复制「总结该网页」"];
    [alert addButtonWithTitle:@"删除全部用户配方"];
    [alert addButtonWithTitle:@"关闭"];
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        AIPageContextRecipe *src = [[AIPageContextRecipeStore sharedStore] recipeWithId:AIPageContextRecipeIDSummarizePage];
        AIPageContextRecipe *dup = [[AIPageContextRecipeStore sharedStore] duplicateRecipe:src withTitle:@"我的总结提示"];
        // 简单编辑提示词
        NSAlert *edit = [[NSAlert alloc] init];
        edit.messageText = @"编辑用户提示词";
        SBTextField *field = [SBTextField standardField];
        field.frame = NSMakeRect(0, 0, 360, 24);
        field.stringValue = dup.userPrompt ?: @"";
        edit.accessoryView = field;
        [edit addButtonWithTitle:@"保存"];
        [edit addButtonWithTitle:@"取消"];
        if ([edit runModal] == NSAlertFirstButtonReturn) {
            dup.userPrompt = field.stringValue ?: @"";
            NSError *err = nil;
            if ([[AIPageContextRecipeStore sharedStore] saveUserRecipe:dup error:&err]) {
                self.statusLabel.stringValue = @"已保存用户配方「我的总结提示」";
                self.statusLabel.textColor = NSColor.systemGreenColor;
            } else {
                self.statusLabel.stringValue = err.localizedDescription ?: @"保存失败";
                self.statusLabel.textColor = NSColor.systemRedColor;
            }
        }
    } else if (resp == NSAlertSecondButtonReturn) {
        for (AIPageContextRecipe *r in [[AIPageContextRecipeStore sharedStore] userRecipes]) {
            [[AIPageContextRecipeStore sharedStore] deleteUserRecipeId:r.recipeId error:nil];
        }
        self.statusLabel.stringValue = @"已删除全部用户配方";
    }
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

#pragma mark - Slash / @ mentions

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.inputView) return;
    if (self.suppressMention) return;
    NSString *text = self.inputView.string ?: @"";
    NSUInteger loc = self.inputView.selectedRange.location;
    if (loc == 0 || loc > text.length) {
        [self.mentionPopover performClose:nil];
        return;
    }
    // 取光标前 token
    NSUInteger start = loc;
    while (start > 0) {
        unichar ch = [text characterAtIndex:start - 1];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:ch]) break;
        start -= 1;
        if (loc - start > 40) break;
    }
    NSString *token = [text substringWithRange:NSMakeRange(start, loc - start)];
    if ([token hasPrefix:@"/"]) {
        [self showMentionPopoverKind:@"/" query:[token substringFromIndex:1] tokenRange:NSMakeRange(start, loc - start)];
    } else if ([token hasPrefix:@"@"]) {
        [self showMentionPopoverKind:@"@" query:[token substringFromIndex:1] tokenRange:NSMakeRange(start, loc - start)];
    } else {
        [self.mentionPopover performClose:nil];
    }
}

- (void)showMentionPopoverKind:(NSString *)kind query:(NSString *)query tokenRange:(NSRange)tokenRange {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSString *q = query.lowercaseString ?: @"";
    if ([kind isEqualToString:@"/"]) {
        for (AIPageContextRecipe *r in [[AIPageContextRecipeStore sharedStore] allRecipes]) {
            if (q.length &&
                [r.title.lowercaseString rangeOfString:q].location == NSNotFound &&
                [r.recipeId.lowercaseString rangeOfString:q].location == NSNotFound) {
                continue;
            }
            [items addObject:@{ @"title": r.title ?: r.recipeId, @"id": r.recipeId, @"type": @"recipe" }];
        }
    } else {
        AIPageContextBundle *helper = [[AIPageContextBundle alloc] init];
        for (NSString *layerId in [AIPageContextBundle allLayerIds]) {
            NSString *name = [helper displayNameForLayer:layerId];
            if (q.length && [name.lowercaseString rangeOfString:q].location == NSNotFound &&
                [layerId rangeOfString:q].location == NSNotFound) continue;
            if ([layerId isEqualToString:AIPageContextLayerHTML] &&
                !BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsHTML) continue;
            [items addObject:@{ @"title": [NSString stringWithFormat:@"@%@", name],
                                @"id": layerId, @"type": @"layer" }];
        }
        for (AIPageContextResource *res in self.currentPageBundle.resources) {
            if (res.kind == AIPageContextResourceKindScript &&
                !BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsScriptResources) continue;
            NSString *label = res.chipLabel;
            if (q.length && [label.lowercaseString rangeOfString:q].location == NSNotFound) continue;
            [items addObject:@{ @"title": [NSString stringWithFormat:@"@%@", label],
                                @"id": res.resourceId ?: @"", @"type": @"resource" }];
            if (items.count > 24) break;
        }
    }
    if (items.count == 0) {
        [self.mentionPopover performClose:nil];
        return;
    }

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 2;
    stack.edgeInsets = NSEdgeInsetsMake(6, 6, 6, 6);
    NSInteger i = 0;
    for (NSDictionary *item in items) {
        if (i >= 12) break;
        NSButton *b = [NSButton buttonWithTitle:item[@"title"] target:self action:@selector(mentionItemClicked:)];
        b.bezelStyle = NSBezelStyleRecessed;
        b.controlSize = NSControlSizeSmall;
        b.identifier = [NSString stringWithFormat:@"%@|%@|%lu|%lu",
                        item[@"type"], item[@"id"],
                        (unsigned long)tokenRange.location, (unsigned long)tokenRange.length];
        [stack addArrangedSubview:b];
        i += 1;
    }
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = stack;
    [stack layoutSubtreeIfNeeded];
    vc.preferredContentSize = NSMakeSize(220, MIN(280, 8 + i * 26.0));

    if (!self.mentionPopover) {
        self.mentionPopover = [[NSPopover alloc] init];
        self.mentionPopover.behavior = NSPopoverBehaviorTransient;
    }
    self.mentionPopover.contentViewController = vc;
    NSRect caret = [self.inputView firstRectForCharacterRange:self.inputView.selectedRange actualRange:NULL];
    // firstRect 是屏幕坐标；popover 需要相对 view
    NSRect inWindow = [self.inputView.window convertRectFromScreen:caret];
    NSRect inView = [self.inputView convertRect:inWindow fromView:nil];
    if (NSIsEmptyRect(inView)) inView = NSMakeRect(8, 8, 1, 1);
    [self.mentionPopover showRelativeToRect:inView ofView:self.inputView preferredEdge:NSRectEdgeMaxY];
}

- (void)mentionItemClicked:(NSButton *)sender {
    NSArray *parts = [sender.identifier componentsSeparatedByString:@"|"];
    if (parts.count < 4) return;
    NSString *type = parts[0];
    NSString *oid = parts[1];
    NSUInteger loc = (NSUInteger)[parts[2] integerValue];
    NSUInteger len = (NSUInteger)[parts[3] integerValue];
    [self.mentionPopover performClose:nil];

    self.suppressMention = YES;
    NSString *text = self.inputView.string ?: @"";
    if (loc + len <= text.length) {
        NSString *replacement = @"";
        if ([type isEqualToString:@"recipe"]) {
            // 删掉 /token，再跑配方
            NSMutableString *m = [text mutableCopy];
            [m replaceCharactersInRange:NSMakeRange(loc, len) withString:@""];
            self.inputView.string = m;
            self.suppressMention = NO;
            BOOL autoSend = [oid isEqualToString:AIPageContextRecipeIDSummarizePage];
            [self presentPageRecipe:oid autoSend:autoSend];
            return;
        }
        // @ 层/资源：删 token，挂引用
        NSMutableString *m = [text mutableCopy];
        [m replaceCharactersInRange:NSMakeRange(loc, len) withString:replacement];
        self.inputView.string = m;
    }
    self.suppressMention = NO;

    if ([type isEqualToString:@"layer"]) {
        if (!self.currentPageBundle) {
            [self capturePageContextOnlyUpdatingTray:YES];
            self.statusLabel.stringValue = @"请先采集，再使用 @ 引用";
            return;
        }
        if ([oid isEqualToString:AIPageContextLayerHTML] &&
            !BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsHTML) {
            self.statusLabel.stringValue = @"隐私档禁止 HTML";
            return;
        }
        [self attachLayer:oid fromBundle:self.currentPageBundle];
        [self reloadCitationChips];
        [self refreshPageContextTray];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已引用 %@", oid];
    } else if ([type isEqualToString:@"resource"]) {
        AIPageContextResource *res = [self.currentPageBundle resourceWithId:oid];
        if (!res) {
            self.statusLabel.stringValue = @"资源不存在，请先采集";
            return;
        }
        // 复用 checkbox 逻辑
        NSButton *fake = [NSButton checkboxWithTitle:@"" target:nil action:nil];
        fake.identifier = oid;
        fake.state = NSControlStateValueOn;
        [self resourceCheckboxToggled:fake];
    }
}

- (void)sendClicked:(id)sender {
    (void)sender;
    [self.mentionPopover performClose:nil];
    NSString *prompt = [self.inputView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self sendPrompt:prompt clearInput:YES];
}

- (NSString *)composePromptWithUserText:(NSString *)userText {
    NSString *q = [userText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSMutableString *out = [NSMutableString string];
    if (self.pendingSystemHint.length > 0) {
        [out appendString:self.pendingSystemHint];
        [out appendString:@"\n\n"];
    }
    if (self.citations.count == 0) {
        if (out.length == 0) return q;
        [out appendString:q];
        return out;
    }
    [out appendString:@"以下是用户提供的上下文引用，请结合它们回答后面的问题：\n\n"];
    NSInteger i = 1;
    for (AIAssistantCitation *c in self.citations) {
        [out appendFormat:@"### 引用 %ld\n%@\n\n", (long)i, [c promptBlock]];
        i += 1;
    }
    [out appendString:@"### 用户问题\n"];
    [out appendString:q.length ? q : @"（请根据以上引用作答）"];
    return out;
}

- (void)sendPrompt:(NSString *)prompt clearInput:(BOOL)clearInput {
    if (self.inFlight) return;
    NSString *text = [prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0 && self.citations.count == 0) {
        self.statusLabel.stringValue = @"请输入提示词或加入引用";
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

    NSString *apiPrompt = [self composePromptWithUserText:text];
    self.pendingSystemHint = nil;
    NSString *displayText = text.length ? text : @"（引用上下文）";
    if (self.citations.count > 0 && text.length > 0) {
        displayText = [NSString stringWithFormat:@"📎 %lu 条引用 · %@",
                       (unsigned long)self.citations.count, text];
    } else if (self.citations.count > 0) {
        displayText = [NSString stringWithFormat:@"📎 %lu 条引用", (unsigned long)self.citations.count];
    }
    NSArray<NSString *> *citationImages = [self jpegDataURLsFromImageCitations:self.citations];

    BOOL firstUser = YES;
    for (AIAssistantMessage *m in s.messages) {
        if ([m.role isEqualToString:@"user"]) { firstUser = NO; break; }
    }
    AIAssistantMessage *userMsg = [AIAssistantMessage messageWithRole:@"user" content:apiPrompt];
    userMsg.displayContent = displayText;
    if (citationImages.count) userMsg.imageDataURLs = citationImages;
    [s.messages addObject:userMsg];
    if (firstUser && [s.title isEqualToString:@"新对话"]) {
        NSString *t = [displayText stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (t.length > 24) t = [[t substringToIndex:24] stringByAppendingString:@"…"];
        s.title = t;
        self.titleLabel.stringValue = t;
    }
    [AIAssistantSessionStore.sharedStore touchAndPersist:s];
    [self.chatPanel appendUserText:displayText imageDataURLs:citationImages];
    if (clearInput) {
        self.inputView.string = @"";
        [self.citations removeAllObjects];
        [self reloadCitationChips];
        [self refreshPageContextTray];
    }

    NSString *model = s.modelId;
    NSString *sid = s.sessionId;
    BrowserAIAssistantPreferences.sharedPreferences.lastModelId = model;
    self.inFlight = YES;
    self.inFlightSessionId = sid;
    [self reloadUI];
    self.statusLabel.stringValue = @"请求中…";

    __weak typeof(self) weakSelf = self;
    [[BrowserAIAssistantClient sharedClient] chatWithModel:model prompt:apiPrompt completion:^(NSInteger httpStatus, NSString *assistantText, NSString *errorMessage) {
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
    if (pageContext && [actionKey isEqualToString:BrowserAIAssistantActionSummarize]) {
        [self presentPageRecipe:AIPageContextRecipeIDSummarizePage autoSend:autoSend];
        return;
    }
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

- (void)summarizePageClicked:(id)sender {
    (void)sender;
    [self presentPageRecipe:AIPageContextRecipeIDSummarizePage autoSend:YES];
}

- (void)askPageClicked:(id)sender {
    (void)sender;
    [self presentPageRecipe:AIPageContextRecipeIDAskPage autoSend:NO];
}

- (BOOL)isPageContextCitationKind:(AIAssistantCitationKind)kind {
    switch (kind) {
        case AIAssistantCitationKindPageMeta:
        case AIAssistantCitationKindPageArticle:
        case AIAssistantCitationKindPageOutline:
        case AIAssistantCitationKindPageHTML:
        case AIAssistantCitationKindPageMarkdown:
        case AIAssistantCitationKindResourceScript:
        case AIAssistantCitationKindResourceStyle:
        case AIAssistantCitationKindResourceJSON:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)hasCitationForResourceId:(NSString *)resourceId {
    if (resourceId.length == 0) return NO;
    for (AIAssistantCitation *c in self.citations) {
        if ([c.resourceId isEqualToString:resourceId]) return YES;
    }
    return NO;
}

- (void)removeCitationForResourceId:(NSString *)resourceId {
    if (resourceId.length == 0) return;
    NSIndexSet *idx = [self.citations indexesOfObjectsPassingTest:^BOOL(AIAssistantCitation *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.resourceId isEqualToString:resourceId];
    }];
    if (idx.count) [self.citations removeObjectsAtIndexes:idx];
}

- (void)removePageContextCitations {
    NSIndexSet *idx = [self.citations indexesOfObjectsPassingTest:^BOOL(AIAssistantCitation *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [self isPageContextCitationKind:obj.kind];
    }];
    if (idx.count) {
        [self.citations removeObjectsAtIndexes:idx];
    }
}

- (void)removeCitationForLayer:(NSString *)layerId {
    NSInteger kind = [AIPageContextPromptBuilder citationKindForLayerId:layerId];
    if (kind < 0) return;
    NSIndexSet *idx = [self.citations indexesOfObjectsPassingTest:^BOOL(AIAssistantCitation *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return obj.kind == (AIAssistantCitationKind)kind;
    }];
    if (idx.count) [self.citations removeObjectsAtIndexes:idx];
}

- (BOOL)hasCitationForLayer:(NSString *)layerId {
    NSInteger kind = [AIPageContextPromptBuilder citationKindForLayerId:layerId];
    if (kind < 0) return NO;
    for (AIAssistantCitation *c in self.citations) {
        if (c.kind == (AIAssistantCitationKind)kind) return YES;
    }
    return NO;
}

- (void)attachLayer:(NSString *)layerId fromBundle:(AIPageContextBundle *)bundle {
    if (!bundle || layerId.length == 0) return;
    [self removeCitationForLayer:layerId];
    AIAssistantCitation *c = [AIPageContextPromptBuilder citationForLayer:layerId inBundle:bundle recipe:nil];
    if (c) [self.citations addObject:c];
}

- (nullable WKWebView *)currentBrowseWebView {
    id<BrowserAIAssistantSidebarControllerDelegate> del = self.delegate;
    if ([del respondsToSelector:@selector(aiAssistantSidebarCurrentWebView:)]) {
        return [del aiAssistantSidebarCurrentWebView:self];
    }
    return nil;
}

- (nullable NSUUID *)currentBrowseTabID {
    id<BrowserAIAssistantSidebarControllerDelegate> del = self.delegate;
    if ([del respondsToSelector:@selector(aiAssistantSidebarCurrentTabID:)]) {
        return [del aiAssistantSidebarCurrentTabID:self];
    }
    return nil;
}

- (void)setPageContextButtonsEnabled:(BOOL)enabled {
    self.summarizePageButton.enabled = enabled;
    self.askPageButton.enabled = enabled;
    self.pageContextRecaptureButton.enabled = enabled;
}

- (void)refreshPageContextTray {
    NSUUID *tabID = [self currentBrowseTabID];
    if (tabID && !self.currentPageBundle) {
        self.currentPageBundle = [[AIPageContextStore sharedStore] bundleForTabID:tabID];
    } else if (tabID && self.currentPageBundle &&
               ![self.currentPageBundle.tabID isEqual:tabID]) {
        self.currentPageBundle = [[AIPageContextStore sharedStore] bundleForTabID:tabID];
    } else if (tabID) {
        AIPageContextBundle *stored = [[AIPageContextStore sharedStore] bundleForTabID:tabID];
        if (stored) self.currentPageBundle = stored;
    }

    AIPageContextBundle *b = self.currentPageBundle;
    NSString *title;
    if (!b) {
        title = @"▸ 本页上下文 · 未采集";
        self.pageContextToggleButton.contentTintColor = NSColor.secondaryLabelColor;
    } else if (b.stale) {
        title = [NSString stringWithFormat:@"%@ 本页上下文 · 已过期 · %@",
                 self.pageContextExpanded ? @"▾" : @"▸", [b ageDescription]];
        if (@available(macOS 10.14, *)) {
            self.pageContextToggleButton.contentTintColor = NSColor.systemOrangeColor;
        }
    } else {
        title = [NSString stringWithFormat:@"%@ 本页上下文 · %@",
                 self.pageContextExpanded ? @"▾" : @"▸", [b ageDescription]];
        if (@available(macOS 10.14, *)) {
            self.pageContextToggleButton.contentTintColor = NSColor.secondaryLabelColor;
        }
    }
    self.pageContextToggleButton.title = title;

    for (NSString *layerId in self.layerCheckboxes) {
        NSButton *cb = self.layerCheckboxes[layerId];
        BOOL has = b && [b hasContentForLayer:layerId];
        cb.enabled = has;
        NSString *name = [b ?: [[AIPageContextBundle alloc] init] displayNameForLayer:layerId];
        if (has) {
            NSUInteger n = [b charCountForLayer:layerId];
            if (n >= 1000) {
                cb.title = [NSString stringWithFormat:@"%@（%.1fk）", name, n / 1000.0];
            } else {
                cb.title = [NSString stringWithFormat:@"%@（%lu）", name, (unsigned long)n];
            }
        } else {
            cb.title = name;
        }
        cb.state = [self hasCitationForLayer:layerId] ? NSControlStateValueOn : NSControlStateValueOff;
        if ([layerId isEqualToString:AIPageContextLayerHTML] &&
            !BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsHTML) {
            cb.enabled = NO;
            cb.toolTip = @"当前隐私档为「严格」，禁止引用 HTML";
        } else {
            cb.toolTip = nil;
        }
    }

    [self rebuildResourceRows];

    self.pageContextPanel.hidden = !self.pageContextExpanded;
    self.pageContextPanelHeightConstraint.constant = self.pageContextExpanded ? kPageContextPanelHeight : 0;
}

- (void)rebuildResourceRows {
    for (NSView *v in [self.resourceStack.arrangedSubviews copy]) {
        [self.resourceStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    AIPageContextBundle *b = self.currentPageBundle;
    if (!b.resources.count) {
        NSTextField *empty = [NSTextField labelWithString:@"（无资源或未采集）"];
        empty.font = [NSFont systemFontOfSize:10];
        empty.textColor = NSColor.tertiaryLabelColor;
        [self.resourceStack addArrangedSubview:empty];
        return;
    }
    BOOL allowScript = BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsScriptResources;
    NSUInteger shown = 0;
    for (AIPageContextResource *res in b.resources) {
        if (shown >= 30) break;
        if (res.kind == AIPageContextResourceKindScript && !allowScript) {
            // 标准/严格：仍列出，但禁用挂载；开发档才可挂 JS
        }
        NSView *row = [self resourceRowForResource:res allowScript:allowScript];
        [self.resourceStack addArrangedSubview:row];
        shown += 1;
    }
}

- (NSView *)resourceRowForResource:(AIPageContextResource *)res allowScript:(BOOL)allowScript {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *cb = [NSButton checkboxWithTitle:res.chipLabel target:self action:@selector(resourceCheckboxToggled:)];
    cb.translatesAutoresizingMaskIntoConstraints = NO;
    cb.identifier = res.resourceId;
    cb.font = [NSFont systemFontOfSize:10];
    cb.controlSize = NSControlSizeMini;
    cb.state = [self hasCitationForResourceId:res.resourceId] ? NSControlStateValueOn : NSControlStateValueOff;
    BOOL blockedScript = (res.kind == AIPageContextResourceKindScript && !allowScript);
    cb.enabled = !blockedScript;
    if (blockedScript) {
        cb.toolTip = @"将隐私档设为「开发」后可引用脚本";
    } else if (!res.hasTextBody && res.kind != AIPageContextResourceKindImage) {
        cb.toolTip = @"勾选将先加载正文（同源）";
    }

    NSButton *loadBtn = [NSButton buttonWithTitle:res.loading ? @"…" : (res.hasTextBody ? @"已载" : @"加载")
                                           target:self
                                           action:@selector(resourceLoadClicked:)];
    loadBtn.translatesAutoresizingMaskIntoConstraints = NO;
    loadBtn.bezelStyle = NSBezelStyleRounded;
    loadBtn.controlSize = NSControlSizeMini;
    loadBtn.identifier = res.resourceId;
    loadBtn.enabled = res.canFetchSameOrigin && !res.loading && !blockedScript;
    loadBtn.hidden = (res.kind == AIPageContextResourceKindImage) || res.inlineContent;

    [row addSubview:cb];
    [row addSubview:loadBtn];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:20],
        [cb.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [cb.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [cb.trailingAnchor constraintLessThanOrEqualToAnchor:loadBtn.leadingAnchor constant:-4],
        [loadBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [loadBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.widthAnchor constraintEqualToConstant:280],
    ]];
    return row;
}

- (void)resourceLoadClicked:(NSButton *)sender {
    NSString *rid = sender.identifier;
    AIPageContextResource *res = [self.currentPageBundle resourceWithId:rid];
    WKWebView *wv = [self currentBrowseWebView];
    if (!res || !wv) return;
    sender.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[AIPageContextCapturer sharedCapturer] loadTextForResource:res
                                                      inWebView:wv
                                                       maxChars:65536
                                                     completion:^(BOOL ok, NSString *text, NSString *errorMessage) {
        (void)text;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!ok) {
            strongSelf.statusLabel.stringValue = errorMessage.length ? errorMessage : @"资源加载失败";
            strongSelf.statusLabel.textColor = NSColor.systemRedColor;
        } else {
            strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已加载 %@", res.chipLabel];
            strongSelf.statusLabel.textColor = NSColor.secondaryLabelColor;
        }
        [strongSelf refreshPageContextTray];
    }];
}

- (void)resourceCheckboxToggled:(NSButton *)sender {
    NSString *rid = sender.identifier;
    AIPageContextResource *res = [self.currentPageBundle resourceWithId:rid];
    if (!res) {
        sender.state = NSControlStateValueOff;
        return;
    }
    if (res.kind == AIPageContextResourceKindScript &&
        !BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsScriptResources) {
        sender.state = NSControlStateValueOff;
        self.statusLabel.stringValue = @"隐私档「开发」才可引用脚本";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    if (sender.state != NSControlStateValueOn) {
        [self removeCitationForResourceId:rid];
        [self reloadCitationChips];
        return;
    }
    void (^attach)(void) = ^{
        [self removeCitationForResourceId:rid];
        AIAssistantCitation *c = [AIPageContextPromptBuilder citationForResource:res inBundle:self.currentPageBundle];
        if (c) [self.citations addObject:c];
        [self reloadCitationChips];
        [self refreshPageContextTray];
    };
    if (!res.hasTextBody && res.kind != AIPageContextResourceKindImage) {
        WKWebView *wv = [self currentBrowseWebView];
        if (!wv) {
            sender.state = NSControlStateValueOff;
            return;
        }
        self.statusLabel.stringValue = @"正在加载资源…";
        __weak typeof(self) weakSelf = self;
        [[AIPageContextCapturer sharedCapturer] loadTextForResource:res
                                                          inWebView:wv
                                                           maxChars:65536
                                                         completion:^(BOOL ok, NSString *text, NSString *errorMessage) {
            (void)text;
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) {
                sender.state = NSControlStateValueOff;
                strongSelf.statusLabel.stringValue = errorMessage.length ? errorMessage : @"加载失败";
                strongSelf.statusLabel.textColor = NSColor.systemRedColor;
                [strongSelf refreshPageContextTray];
                return;
            }
            attach();
        }];
        return;
    }
    attach();
}

- (void)pageContextToggleClicked:(id)sender {
    (void)sender;
    self.pageContextExpanded = !self.pageContextExpanded;
    [self refreshPageContextTray];
}

- (void)pageContextRecaptureClicked:(id)sender {
    (void)sender;
    [self capturePageContextOnlyUpdatingTray:YES];
}

- (void)pageContextOnlyArticleClicked:(id)sender {
    (void)sender;
    if (!self.currentPageBundle) {
        [self capturePageContextOnlyUpdatingTray:YES];
        return;
    }
    [self removePageContextCitations];
    [self attachLayer:AIPageContextLayerMeta fromBundle:self.currentPageBundle];
    [self attachLayer:AIPageContextLayerArticle fromBundle:self.currentPageBundle];
    [self reloadCitationChips];
    [self refreshPageContextTray];
    self.statusLabel.stringValue = @"已改为仅引用页信息 + 正文";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
}

- (void)pageContextAttachAllClicked:(id)sender {
    (void)sender;
    if (!self.currentPageBundle) {
        self.statusLabel.stringValue = @"请先采集本页上下文";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"引用全部页面层？";
    alert.informativeText = @"将挂上页信息、正文、提纲、HTML、Markdown（若有）。超长内容会自动裁剪，可能影响模型回复质量。";
    [alert addButtonWithTitle:@"引用全部"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [self removePageContextCitations];
    NSMutableArray<AIAssistantCitation *> *added =
        [[AIPageContextPromptBuilder citationsFromBundle:self.currentPageBundle
                                                  layers:[AIPageContextBundle allLayerIds]
                                                  recipe:nil] mutableCopy];
    NSString *trimNote = [AIPageContextPromptBuilder trimCitations:added toMaxChars:kPageContextPromptBudget];
    [self.citations addObjectsFromArray:added];
    [self reloadCitationChips];
    [self refreshPageContextTray];
    if (trimNote.length) {
        self.statusLabel.stringValue = trimNote;
        self.statusLabel.textColor = NSColor.systemOrangeColor;
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已引用 %lu 个页面层", (unsigned long)added.count];
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
    }
}

- (void)pageContextLayerToggled:(NSButton *)sender {
    NSString *layerId = sender.identifier;
    if (layerId.length == 0) return;
    if (!self.currentPageBundle) {
        sender.state = NSControlStateValueOff;
        self.statusLabel.stringValue = @"请先采集本页上下文";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    if (sender.state == NSControlStateValueOn) {
        if ([layerId isEqualToString:AIPageContextLayerHTML]) {
            if (!BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsHTML) {
                sender.state = NSControlStateValueOff;
                self.statusLabel.stringValue = @"隐私档「严格」禁止引用 HTML";
                self.statusLabel.textColor = NSColor.systemOrangeColor;
                return;
            }
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"引用整页 HTML？";
            alert.informativeText = @"HTML 通常很长，可能超出模型上下文。确定继续？";
            [alert addButtonWithTitle:@"引用"];
            [alert addButtonWithTitle:@"取消"];
            if ([alert runModal] != NSAlertFirstButtonReturn) {
                sender.state = NSControlStateValueOff;
                return;
            }
        }
        [self attachLayer:layerId fromBundle:self.currentPageBundle];
        NSMutableArray *pageOnly = [NSMutableArray array];
        for (AIAssistantCitation *c in self.citations) {
            if ([self isPageContextCitationKind:c.kind]) [pageOnly addObject:c];
        }
        NSMutableArray *mutablePage = [pageOnly mutableCopy];
        NSString *note = [AIPageContextPromptBuilder trimCitations:mutablePage toMaxChars:kPageContextPromptBudget];
        if (note.length && mutablePage.count < pageOnly.count) {
            // 若裁剪删了当前层，同步 checkbox
            [self removePageContextCitations];
            [self.citations addObjectsFromArray:mutablePage];
            self.statusLabel.stringValue = note;
            self.statusLabel.textColor = NSColor.systemOrangeColor;
        }
    } else {
        [self removeCitationForLayer:layerId];
    }
    [self reloadCitationChips];
    [self refreshPageContextTray];
}

- (void)capturePageContextOnlyUpdatingTray:(BOOL)updateTray {
    WKWebView *webView = [self currentBrowseWebView];
    NSUUID *tabID = [self currentBrowseTabID];
    if (!webView) {
        self.statusLabel.stringValue = @"当前没有可采集的网页标签";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    self.statusLabel.stringValue = @"正在采集页面上下文…";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self setPageContextButtonsEnabled:NO];
    __weak typeof(self) weakSelf = self;
    [[AIPageContextCapturer sharedCapturer] captureFromWebView:webView
                                                         tabID:tabID
                                              maxArticleChars:24000
                                                    completion:^(AIPageContextBundle *bundle, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setPageContextButtonsEnabled:YES];
        if (!bundle) {
            strongSelf.statusLabel.stringValue = errorMessage.length ? errorMessage : @"采集失败";
            strongSelf.statusLabel.textColor = NSColor.systemRedColor;
            return;
        }
        strongSelf.currentPageBundle = bundle;
        if (updateTray) {
            // 刷新已挂载页层内容
            NSArray *layers = [[strongSelf.citations valueForKey:@"kind"] copy];
            (void)layers;
            NSMutableArray<NSString *> *attached = [NSMutableArray array];
            for (AIAssistantCitation *c in strongSelf.citations) {
                NSString *lid = [AIPageContextPromptBuilder layerIdForCitationKind:c.kind];
                if (lid.length) [attached addObject:lid];
            }
            if (attached.count) {
                [strongSelf removePageContextCitations];
                for (NSString *lid in attached) {
                    [strongSelf attachLayer:lid fromBundle:bundle];
                }
                [strongSelf reloadCitationChips];
            }
            [strongSelf refreshPageContextTray];
            strongSelf.statusLabel.stringValue =
                [NSString stringWithFormat:@"已重新采集 · %@", [bundle ageDescription]];
            strongSelf.statusLabel.textColor = bundle.stale ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
            if (bundle.articleQuality == AIPageContextArticleQualityLow && bundle.articleWarning.length) {
                strongSelf.statusLabel.stringValue = bundle.articleWarning;
                strongSelf.statusLabel.textColor = NSColor.systemOrangeColor;
            }
        }
    }];
}

- (void)presentPageRecipe:(NSString *)recipeId autoSend:(BOOL)autoSend {
    AIPageContextRecipe *recipe = [[AIPageContextRecipeStore sharedStore] recipeWithId:recipeId];
    if (!recipe) {
        self.statusLabel.stringValue = @"未知配方";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    [self showPane:AIAssistantPaneChat];

    WKWebView *webView = [self currentBrowseWebView];
    NSUUID *tabID = [self currentBrowseTabID];
    if (!webView) {
        self.statusLabel.stringValue = @"当前没有可采集的网页标签";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        self.inputView.string = recipe.userPrompt;
        return;
    }

    self.statusLabel.stringValue = @"正在采集页面正文…";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self setPageContextButtonsEnabled:NO];

    __weak typeof(self) weakSelf = self;
    [[AIPageContextCapturer sharedCapturer] captureFromWebView:webView
                                                         tabID:tabID
                                              maxArticleChars:recipe.maxArticleChars
                                                    completion:^(AIPageContextBundle *bundle, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setPageContextButtonsEnabled:YES];
        if (!bundle) {
            strongSelf.statusLabel.stringValue = errorMessage.length ? errorMessage : @"采集失败";
            strongSelf.statusLabel.textColor = NSColor.systemRedColor;
            strongSelf.inputView.string = recipe.userPrompt;
            return;
        }
        strongSelf.currentPageBundle = bundle;
        if (![bundle hasUsableArticle]) {
            strongSelf.statusLabel.stringValue = @"未能提取到可用正文";
            strongSelf.statusLabel.textColor = NSColor.systemOrangeColor;
            strongSelf.inputView.string = recipe.userPrompt;
            [strongSelf refreshPageContextTray];
            return;
        }
        [strongSelf runPreprocessIfNeededForRecipe:recipe
                                           bundle:bundle
                                          webView:webView
                                       completion:^(NSArray<AIAssistantCitation *> *extra) {
            [strongSelf finishPresentPageRecipe:recipe
                                         bundle:bundle
                                       autoSend:autoSend
                                  extraCitations:extra];
        }];
    }];
}

/// PC-3：可选页内 preprocess（Recipe.preprocessScript 为 function(input) 函数体）。
- (void)runPreprocessIfNeededForRecipe:(AIPageContextRecipe *)recipe
                                bundle:(AIPageContextBundle *)bundle
                               webView:(WKWebView *)webView
                            completion:(void (^)(NSArray<AIAssistantCitation *> *extra))completion {
    if (!completion) return;
    NSString *scriptBody = recipe.preprocessScript;
    if (scriptBody.length == 0 || !webView) {
        completion(@[]);
        return;
    }
    NSString *article = [bundle effectiveArticleText] ?: @"";
    if (article.length > 8000) article = [article substringToIndex:8000];
    NSDictionary *input = @{
        @"url": bundle.urlString ?: @"",
        @"title": bundle.title ?: @"",
        @"article": article,
        @"outline": bundle.outlineText ?: @"",
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){\n"
                    @"  var __meoInput = %@;\n"
                    @"  try {\n"
                    @"    var __meoOut = (function(input){\n%@\n})(__meoInput);\n"
                    @"    if (__meoOut === undefined || __meoOut === null) return {ok:true};\n"
                    @"    return __meoOut;\n"
                    @"  } catch (e) {\n"
                    @"    return {ok:false, error: String(e && e.message ? e.message : e)};\n"
                    @"  }\n"
                    @"})();", json, scriptBody];
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        (void)strongSelf;
        NSMutableArray<AIAssistantCitation *> *extra = [NSMutableArray array];
        if (error) {
            completion(extra);
            return;
        }
        NSDictionary *dict = nil;
        if ([result isKindOfClass:[NSDictionary class]]) {
            dict = (NSDictionary *)result;
        } else if ([result isKindOfClass:[NSString class]] && [(NSString *)result length] > 0) {
            AIAssistantCitation *c = [AIAssistantCitation textCitation:(NSString *)result
                                                             sourceURL:[NSURL URLWithString:bundle.urlString ?: @""]
                                                             pageTitle:bundle.title];
            if (c) [extra addObject:c];
            completion(extra);
            return;
        }
        if (![dict isKindOfClass:[NSDictionary class]]) {
            completion(extra);
            return;
        }
        if ([dict[@"ok"] respondsToSelector:@selector(boolValue)] && ![dict[@"ok"] boolValue]) {
            completion(extra);
            return;
        }
        NSString *extraText = [dict[@"extraText"] isKindOfClass:[NSString class]] ? dict[@"extraText"] : nil;
        if (extraText.length == 0 && [dict[@"text"] isKindOfClass:[NSString class]]) {
            extraText = dict[@"text"];
        }
        if (extraText.length) {
            AIAssistantCitation *c = [AIAssistantCitation textCitation:extraText
                                                             sourceURL:[NSURL URLWithString:bundle.urlString ?: @""]
                                                             pageTitle:bundle.title];
            if (c) [extra addObject:c];
        }
        NSArray *cites = [dict[@"citations"] isKindOfClass:[NSArray class]] ? dict[@"citations"] : nil;
        for (id item in cites) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *cd = (NSDictionary *)item;
            NSString *body = [cd[@"body"] isKindOfClass:[NSString class]] ? cd[@"body"] : nil;
            if (!body.length && [cd[@"text"] isKindOfClass:[NSString class]]) body = cd[@"text"];
            if (!body.length) continue;
            NSString *title = [cd[@"title"] isKindOfClass:[NSString class]] ? cd[@"title"] : @"预处理";
            AIAssistantCitation *c = [AIAssistantCitation textCitation:body
                                                             sourceURL:[NSURL URLWithString:bundle.urlString ?: @""]
                                                             pageTitle:title];
            if (c) [extra addObject:c];
            if (extra.count >= 8) break;
        }
        completion(extra);
    }];
}

- (void)finishPresentPageRecipe:(AIPageContextRecipe *)recipe
                         bundle:(AIPageContextBundle *)bundle
                       autoSend:(BOOL)autoSend
                  extraCitations:(NSArray<AIAssistantCitation *> *)extra {
    [self removePageContextCitations];
    NSMutableArray<NSString *> *layers = [recipe.autoAttachLayers mutableCopy] ?: [NSMutableArray array];
    if (!BrowserAIAssistantPreferences.sharedPreferences.pageContextAllowsHTML) {
        [layers removeObject:AIPageContextLayerHTML];
    }
    NSMutableArray<AIAssistantCitation *> *pageCites =
        [[AIPageContextPromptBuilder citationsFromBundle:bundle layers:layers recipe:recipe] mutableCopy];
    if (extra.count) [pageCites addObjectsFromArray:extra];
    NSString *trimNote = [AIPageContextPromptBuilder trimCitations:pageCites toMaxChars:kPageContextPromptBudget];
    [self.citations addObjectsFromArray:pageCites];
    [self reloadCitationChips];
    [self refreshPageContextTray];

    self.pendingSystemHint = recipe.systemHint;
    NSString *prompt = recipe.userPrompt ?: @"";
    if ([recipe.recipeId isEqualToString:AIPageContextRecipeIDRegexExtract] &&
        self.pendingRegexPatternOverride.length) {
        NSString *pat = self.pendingRegexPatternOverride;
        self.pendingRegexPatternOverride = nil;
        NSRange mark = [prompt rangeOfString:@"正则：\n"];
        if (mark.location != NSNotFound) {
            prompt = [[prompt substringToIndex:NSMaxRange(mark)] stringByAppendingFormat:@"%@\n", pat];
        } else {
            prompt = [prompt stringByAppendingFormat:@"\n正则：\n%@\n", pat];
        }
    }
    self.inputView.string = prompt;

    NSString *warn = bundle.articleWarning ?: @"";
    if (trimNote.length) {
        self.statusLabel.stringValue = trimNote;
        self.statusLabel.textColor = NSColor.systemOrangeColor;
    } else if (bundle.articleQuality == AIPageContextArticleQualityLow && warn.length) {
        self.statusLabel.stringValue = warn;
        self.statusLabel.textColor = NSColor.systemOrangeColor;
    } else {
        self.statusLabel.stringValue =
            [NSString stringWithFormat:@"已引用正文（%lu 字）",
             (unsigned long)[bundle effectiveArticleText].length];
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
    }

    AIAssistantSession *s = [self currentSession];
    if (!s) {
        NSString *pid = BrowserAIAssistantPreferences.sharedPreferences.lastProviderId ?: @"deepseek";
        [self createSessionWithProviderId:pid];
        self.statusLabel.stringValue = @"已采集正文并创建会话，网页就绪后请发送";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    [self reloadUI];
    [self refreshPageContextTray];
    if (autoSend && s.connection == AIAssistantSessionConnectionReady && s.modelId.length) {
        [self sendPrompt:prompt clearInput:YES];
    } else {
        NSString *msg = [NSString stringWithFormat:@"已填入「%@」，可编辑后发送", recipe.title];
        if (bundle.articleQuality == AIPageContextArticleQualityLow && warn.length) {
            msg = [NSString stringWithFormat:@"%@ · %@", warn, msg];
        }
        self.statusLabel.stringValue = msg;
        self.statusLabel.textColor = NSColor.systemOrangeColor;
    }
}

#pragma mark - Page Context PC-3 Actions

- (void)withCurrentOrCapturedBundle:(void (^)(AIPageContextBundle *_Nullable bundle, NSString *_Nullable error))block {
    if (!block) return;
    if (self.currentPageBundle && [self.currentPageBundle hasUsableArticle]) {
        block(self.currentPageBundle, nil);
        return;
    }
    WKWebView *webView = [self currentBrowseWebView];
    NSUUID *tabID = [self currentBrowseTabID];
    if (!webView) {
        block(nil, @"当前没有可采集的网页标签");
        return;
    }
    self.statusLabel.stringValue = @"正在采集页面…";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    __weak typeof(self) weakSelf = self;
    [[AIPageContextCapturer sharedCapturer] captureFromWebView:webView
                                                         tabID:tabID
                                              maxArticleChars:24000
                                                    completion:^(AIPageContextBundle *bundle, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (bundle) strongSelf.currentPageBundle = bundle;
        [strongSelf refreshPageContextTray];
        block(bundle, bundle ? nil : (errorMessage.length ? errorMessage : @"采集失败"));
    }];
}

- (void)exportCurrentBundleToPasteboard {
    [self withCurrentOrCapturedBundle:^(AIPageContextBundle *bundle, NSString *error) {
        if (!bundle) {
            self.statusLabel.stringValue = error ?: @"无 Bundle 可导出";
            self.statusLabel.textColor = NSColor.systemOrangeColor;
            return;
        }
        [AIPageContextBundleExporter copyBundleJSONToPasteboard:bundle];
        self.statusLabel.stringValue = @"已复制 Bundle JSON（摘要，无正文全文）到剪贴板";
        self.statusLabel.textColor = NSColor.systemGreenColor;
    }];
}

- (void)exportCurrentBundleToDownloads {
    [self withCurrentOrCapturedBundle:^(AIPageContextBundle *bundle, NSString *error) {
        if (!bundle) {
            self.statusLabel.stringValue = error ?: @"无 Bundle 可导出";
            self.statusLabel.textColor = NSColor.systemOrangeColor;
            return;
        }
        NSURL *dirURL = [BrowserDownloadManager.sharedManager downloadDirectoryURL];
        NSString *dir = dirURL.path;
        if (dir.length == 0) {
            dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
        }
        NSError *err = nil;
        NSString *path = [AIPageContextBundleExporter exportBundle:bundle toDirectory:dir error:&err];
        if (!path) {
            self.statusLabel.stringValue = err.localizedDescription ?: @"导出失败";
            self.statusLabel.textColor = NSColor.systemRedColor;
            return;
        }
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已导出 %@", path.lastPathComponent];
        self.statusLabel.textColor = NSColor.systemGreenColor;
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
    }];
}

- (void)applyCurrentContextToScraperDraft {
    __weak typeof(self) weakSelf = self;
    [self withCurrentOrCapturedBundle:^(AIPageContextBundle *bundle, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!bundle) {
            strongSelf.statusLabel.stringValue = error ?: @"无 Bundle 可导入爬虫";
            strongSelf.statusLabel.textColor = NSColor.systemOrangeColor;
            return;
        }
        id recipe = [AIPageContextScraperBridge draftRecipeFromBundle:bundle
                                                          pickResult:strongSelf.lastPagePickResult];
        id<BrowserAIAssistantSidebarControllerDelegate> del = strongSelf.delegate;
        if ([del respondsToSelector:@selector(aiAssistantSidebar:applyScraperDraftRecipe:)]) {
            [del aiAssistantSidebar:strongSelf applyScraperDraftRecipe:recipe];
            strongSelf.statusLabel.stringValue = strongSelf.lastPagePickResult
                ? @"已打开页面爬虫并套用点选草稿"
                : @"已打开页面爬虫并套用草稿";
            strongSelf.statusLabel.textColor = NSColor.systemGreenColor;
        } else {
            strongSelf.statusLabel.stringValue = @"无法打开页面爬虫";
            strongSelf.statusLabel.textColor = NSColor.systemOrangeColor;
        }
    }];
}

- (void)startPickPageSubtreeForCitation {
    WKWebView *webView = [self currentBrowseWebView];
    if (!webView) {
        self.statusLabel.stringValue = @"当前没有可点选的网页";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    [self showPane:AIAssistantPaneChat];
    self.statusLabel.stringValue = @"请在页面上点选要引用的区域（Esc 取消）…";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    __weak typeof(self) weakSelf = self;
    [BrowserScraperElementPicker startPickingInWebView:webView
                                                  mode:BrowserScraperPickModeContainer
                                            completion:^(NSDictionary *result, BOOL cancelled) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (cancelled || !result) {
            strongSelf.statusLabel.stringValue = @"已取消点选";
            strongSelf.statusLabel.textColor = NSColor.secondaryLabelColor;
            return;
        }
        NSString *path = [result[@"absolutePath"] isKindOfClass:[NSString class]] ? result[@"absolutePath"] : nil;
        if (!path.length && [result[@"cssPath"] isKindOfClass:[NSString class]]) {
            path = result[@"cssPath"];
        }
        if (!path.length) {
            strongSelf.statusLabel.stringValue = @"未能解析点选路径";
            strongSelf.statusLabel.textColor = NSColor.systemOrangeColor;
            return;
        }
        NSString *nameHint = [result[@"nameHint"] isKindOfClass:[NSString class]] ? result[@"nameHint"] : @"";
        NSString *tag = [result[@"tagName"] isKindOfClass:[NSString class]] ? result[@"tagName"] : @"区域";
        NSString *pathJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:path options:0 error:nil]
                                                   encoding:NSUTF8StringEncoding] ?: @"\"\"";
        NSString *fetchJS = [NSString stringWithFormat:
                             @"(function(){\n"
                             @"  var p = %@;\n"
                             @"  var el = null;\n"
                             @"  try { el = document.querySelector(p); } catch (e) { el = null; }\n"
                             @"  if (!el) return null;\n"
                             @"  var text = (el.innerText || el.textContent || '').trim();\n"
                             @"  if (text.length > 50000) text = text.slice(0, 50000);\n"
                             @"  var html = '';\n"
                             @"  try { html = String(el.outerHTML || '').slice(0, 60000); } catch (e2) {}\n"
                             @"  return { text: text, html: html, tag: (el.tagName || '').toLowerCase() };\n"
                             @"})();", pathJSON];
        [webView evaluateJavaScript:fetchJS completionHandler:^(id payload, NSError *error) {
            typeof(self) s2 = weakSelf;
            if (!s2) return;
            NSString *text = nil;
            NSString *html = nil;
            if ([payload isKindOfClass:[NSDictionary class]]) {
                text = [payload[@"text"] isKindOfClass:[NSString class]] ? payload[@"text"] : nil;
                html = [payload[@"html"] isKindOfClass:[NSString class]] ? payload[@"html"] : nil;
            }
            if (!text.length) {
                text = [result[@"textSample"] isKindOfClass:[NSString class]] ? result[@"textSample"] : @"";
            }
            if (!text.length && !html.length) {
                s2.statusLabel.stringValue = error.localizedDescription ?: @"点选区域无可用文本";
                s2.statusLabel.textColor = NSColor.systemOrangeColor;
                return;
            }
            NSString *pageTitle = s2.currentPageBundle.title;
            NSString *pageURL = s2.currentPageBundle.urlString;
            if (!pageURL.length) {
                pageURL = webView.URL.absoluteString;
                pageTitle = webView.title;
            }
            NSString *chipTitle = nameHint.length ? nameHint
                : [NSString stringWithFormat:@"点选 · %@", tag.length ? tag : @"区域"];
            NSMutableString *body = [NSMutableString string];
            [body appendFormat:@"【DOM 区域】%@\n选择器：%@\n\n", chipTitle, path];
            if (text.length) {
                [body appendString:text];
            } else if (html.length) {
                [body appendString:html];
            }
            AIAssistantCitation *c = [AIAssistantCitation textCitation:body
                                                             sourceURL:[NSURL URLWithString:pageURL ?: @""]
                                                             pageTitle:pageTitle.length ? pageTitle : chipTitle];
            if (c) {
                [s2.citations addObject:c];
                [s2 reloadCitationChips];
            }
            // 可选：同时预填爬虫草稿（不强制打开）
            s2.lastPagePickResult = result;
            s2.statusLabel.stringValue =
                [NSString stringWithFormat:@"已加入点选引用（%lu 字）· 可用 ⋯ → 应用到页面爬虫",
                 (unsigned long)text.length];
            s2.statusLabel.textColor = NSColor.systemGreenColor;
        }];
    }];
}

- (void)showRegexLab {
    AIPageContextBundle *bundle = self.currentPageBundle;
    NSString *source = bundle ? [bundle effectiveArticleText] : @"";
    if (source.length == 0) {
        source = self.inputView.string ?: @"";
    }
    if (source.length == 0) {
        self.statusLabel.stringValue = @"请先采集页面或粘贴待匹配文本";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Regex Lab";
    alert.informativeText = @"对当前正文（或输入框文本）做本地正则预览；确认后可填入「按正则提取」配方。";

    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 120)];
    SBTextField *patternField = [SBTextField standardField];
    patternField.frame = NSMakeRect(0, 88, 420, 24);
    patternField.placeholderString = @"正则，例如 \\d{4}-\\d{2}-\\d{2}";
    NSString *existing = self.inputView.string ?: @"";
    NSRange r = [existing rangeOfString:@"正则：\n"];
    if (r.location != NSNotFound) {
        NSString *tail = [existing substringFromIndex:NSMaxRange(r)];
        NSString *line = [[tail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] firstObject];
        if (line.length) patternField.stringValue = line;
    }
    NSTextField *hint = [NSTextField labelWithString:
                         [NSString stringWithFormat:@"样本：%lu 字（取前 2 万）", (unsigned long)MIN(source.length, (NSUInteger)20000)]];
    hint.frame = NSMakeRect(0, 60, 420, 18);
    hint.textColor = NSColor.secondaryLabelColor;
    hint.font = [NSFont systemFontOfSize:11];
    SBTextField *previewField = [SBTextField standardField];
    previewField.frame = NSMakeRect(0, 0, 420, 52);
    previewField.editable = NO;
    previewField.selectable = YES;
    previewField.placeholderString = @"匹配预览";
    [box addSubview:patternField];
    [box addSubview:hint];
    [box addSubview:previewField];
    alert.accessoryView = box;
    [alert addButtonWithTitle:@"预览"];
    [alert addButtonWithTitle:@"填入配方"];
    [alert addButtonWithTitle:@"关闭"];

    // 循环：预览可反复点
    while (YES) {
        NSModalResponse resp = [alert runModal];
        NSString *pat = [patternField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (resp == NSAlertThirdButtonReturn) return;
        if (pat.length == 0) {
            previewField.stringValue = @"请输入正则";
            continue;
        }
        NSError *rxErr = nil;
        NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:pat
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:&rxErr];
        if (!rx) {
            previewField.stringValue = rxErr.localizedDescription ?: @"正则无效";
            if (resp == NSAlertSecondButtonReturn) continue;
            continue;
        }
        NSString *hay = source.length > 20000 ? [source substringToIndex:20000] : source;
        NSArray<NSTextCheckingResult *> *matches =
            [rx matchesInString:hay options:0 range:NSMakeRange(0, hay.length)];
        NSMutableArray<NSString *> *hits = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (NSTextCheckingResult *m in matches) {
            if (m.range.length == 0) continue;
            NSString *hit = [hay substringWithRange:m.range];
            if ([seen containsObject:hit]) continue;
            [seen addObject:hit];
            [hits addObject:hit];
            if (hits.count >= 30) break;
        }
        NSString *preview = hits.count
            ? [NSString stringWithFormat:@"%lu 命中（去重展示 %lu）：\n%@",
               (unsigned long)matches.count, (unsigned long)hits.count, [hits componentsJoinedByString:@" · "]]
            : @"无匹配";
        previewField.stringValue = preview;
        if (resp == NSAlertFirstButtonReturn) {
            continue; // 预览后再弹
        }
        if (resp == NSAlertSecondButtonReturn) {
            self.pendingRegexPatternOverride = pat;
            [self presentPageRecipe:AIPageContextRecipeIDRegexExtract autoSend:NO];
            self.statusLabel.stringValue =
                [NSString stringWithFormat:@"正在采集并填入正则（本地预览 %lu 命中）…",
                 (unsigned long)matches.count];
            self.statusLabel.textColor = NSColor.secondaryLabelColor;
            return;
        }
    }
}

#pragma mark - Citations

- (NSString *)stringValueFromPayload:(NSDictionary *)payload key:(NSString *)key {
    id v = payload[key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return @"";
}

- (nullable NSImage *)imageFromDataURLString:(NSString *)dataURL {
    if (dataURL.length == 0 || ![dataURL hasPrefix:@"data:"]) {
        return nil;
    }
    NSRange comma = [dataURL rangeOfString:@","];
    if (comma.location == NSNotFound || comma.location + 1 >= dataURL.length) {
        return nil;
    }
    NSString *b64 = [dataURL substringFromIndex:comma.location + 1];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64
                                                       options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (data.length == 0) {
        return nil;
    }
    return [[NSImage alloc] initWithData:data];
}

/// 对话气泡用 JPEG data URL；最长边限制，控制会话持久化体积。
- (nullable NSString *)jpegDataURLFromImage:(NSImage *)image maxSide:(CGFloat)maxSide {
    if (!image) return nil;
    NSSize src = image.size;
    if (src.width < 1 || src.height < 1) {
        NSArray *reps = image.representations;
        for (NSImageRep *rep in reps) {
            if (rep.pixelsWide > 0 && rep.pixelsHigh > 0) {
                src = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
                break;
            }
        }
    }
    if (src.width < 1 || src.height < 1) return nil;
    CGFloat longest = MAX(src.width, src.height);
    CGFloat scale = longest > maxSide ? (maxSide / longest) : 1.0;
    NSInteger w = MAX(1, (NSInteger)floor(src.width * scale));
    NSInteger h = MAX(1, (NSInteger)floor(src.height * scale));
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:w
                      pixelsHigh:h
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];
    if (!rep) return nil;
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!ctx) return nil;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    [[NSColor clearColor] set];
    NSRectFill(NSMakeRect(0, 0, w, h));
    [image drawInRect:NSMakeRect(0, 0, w, h)
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:@{ NSImageHintInterpolation: @(NSImageInterpolationHigh) }];
    [NSGraphicsContext restoreGraphicsState];
    NSData *jpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG
                                     properties:@{ NSImageCompressionFactor: @0.72 }];
    if (jpeg.length == 0 || jpeg.length > 450 * 1024) return nil;
    NSString *b64 = [jpeg base64EncodedStringWithOptions:0];
    if (b64.length == 0) return nil;
    return [NSString stringWithFormat:@"data:image/jpeg;base64,%@", b64];
}

- (NSArray<NSString *> *)jpegDataURLsFromImageCitations:(NSArray<AIAssistantCitation *> *)citations {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (AIAssistantCitation *c in citations ?: @[]) {
        if (c.kind != AIAssistantCitationKindImage || !c.previewImage) continue;
        NSString *dataURL = [self jpegDataURLFromImage:c.previewImage maxSide:280];
        if (dataURL.length) {
            [out addObject:dataURL];
            if (out.count >= 6) break;
        }
    }
    return out;
}

- (void)applyPreviewImage:(NSImage *)image forImageURLString:(NSString *)imageURL {
    if (!image) return;
    if (imageURL.length > 0) {
        for (AIAssistantCitation *c in self.citations) {
            if (c.kind == AIAssistantCitationKindImage &&
                [c.url.absoluteString isEqualToString:imageURL]) {
                c.previewImage = image;
                [self reloadCitationChips];
                return;
            }
        }
    }
    for (AIAssistantCitation *c in [self.citations reverseObjectEnumerator]) {
        if (c.kind == AIAssistantCitationKindImage && !c.previewImage) {
            c.previewImage = image;
            [self reloadCitationChips];
            return;
        }
    }
}

- (void)applyPreviewDataURL:(NSString *)dataURL forImageURLString:(NSString *)imageURL {
    [self applyPreviewImage:[self imageFromDataURLString:dataURL] forImageURLString:imageURL];
}

- (void)addCitationFromPayload:(NSDictionary *)payload {
    [self showPane:AIAssistantPaneChat];
    NSString *kind = [self stringValueFromPayload:payload key:@"kind"];
    NSString *url = [self stringValueFromPayload:payload key:@"url"];
    NSString *title = [self stringValueFromPayload:payload key:@"title"];
    NSString *text = [self stringValueFromPayload:payload key:@"text"];
    NSString *thumb = [self stringValueFromPayload:payload key:@"thumb"];

    NSString *pageURL = [self stringValueFromPayload:payload key:@"pageURL"];
    NSString *pageTitle = [self stringValueFromPayload:payload key:@"pageTitle"];

    AIAssistantCitation *citation = nil;
    if ([kind isEqualToString:@"text"] || (text.length > 0 && ![kind isEqualToString:@"url"]
                                           && ![kind isEqualToString:@"image"]
                                           && ![kind isEqualToString:@"file"]
                                           && ![kind isEqualToString:@"link"]
                                           && url.length == 0)) {
        NSURL *sourceURL = url.length ? [NSURL URLWithString:url] : nil;
        citation = [AIAssistantCitation textCitation:(text.length ? text : title)
                                           sourceURL:sourceURL
                                           pageTitle:title];
    } else {
        citation = [AIAssistantCitation citationWithURLString:url.length ? url : text
                                                        title:title
                                                         hint:kind
                                                sourcePageURL:pageURL
                                              sourcePageTitle:pageTitle];
    }
    if (!citation) {
        self.statusLabel.stringValue = @"无法加入引用";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }

    // 去重：同选区文本 / 同非文本 URL 不重复加（划词可与同页「网页」引用并存）
    for (AIAssistantCitation *existing in self.citations) {
        if (citation.kind == AIAssistantCitationKindText &&
            existing.kind == AIAssistantCitationKindText &&
            [existing.body isEqualToString:citation.body]) {
            self.statusLabel.stringValue = @"该引用已在列表中";
            self.statusLabel.textColor = NSColor.secondaryLabelColor;
            [self focusAssistantInput];
            return;
        }
        if (citation.kind != AIAssistantCitationKindText &&
            existing.kind != AIAssistantCitationKindText &&
            citation.url && existing.url &&
            [existing.url.absoluteString isEqualToString:citation.url.absoluteString]) {
            // 已有同图：若新 payload 带缩略图则补上
            if (existing.kind == AIAssistantCitationKindImage && !existing.previewImage) {
                NSImage *fromThumb = [self imageFromDataURLString:thumb];
                if (!fromThumb && [url hasPrefix:@"data:image"]) {
                    fromThumb = [self imageFromDataURLString:url];
                }
                if (fromThumb) {
                    existing.previewImage = fromThumb;
                    [self reloadCitationChips];
                } else {
                    [self loadThumbnailForCitation:existing];
                }
            }
            self.statusLabel.stringValue = @"该引用已在列表中";
            self.statusLabel.textColor = NSColor.secondaryLabelColor;
            [self focusAssistantInput];
            return;
        }
    }

    if (citation.kind == AIAssistantCitationKindImage) {
        NSImage *fromThumb = [self imageFromDataURLString:thumb];
        if (!fromThumb && [url hasPrefix:@"data:image"]) {
            fromThumb = [self imageFromDataURLString:url];
        }
        if (fromThumb) {
            citation.previewImage = fromThumb;
        }
    }

    [self.citations addObject:citation];
    [self reloadCitationChips];
    if (citation.kind == AIAssistantCitationKindImage && citation.url && !citation.previewImage) {
        [self loadThumbnailForCitation:citation];
    }
    if (!self.currentSession) {
        NSString *pid = BrowserAIAssistantPreferences.sharedPreferences.lastProviderId ?: @"deepseek";
        [self createSessionWithProviderId:pid];
    }
    if (citation.kind == AIAssistantCitationKindImage) {
        NSString *img = citation.url.absoluteString ?: @"";
        NSString *page = citation.sourcePageURL.absoluteString ?: @"";
        if (img.length && page.length) {
            self.statusLabel.stringValue = @"已加入图片引用（含图片网址与网页地址）";
        } else if (img.length) {
            self.statusLabel.stringValue = @"已加入图片引用（含图片网址）";
        } else {
            self.statusLabel.stringValue = @"已加入引用 · 图片";
        }
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已加入引用 · %@", citation.kindDisplayName];
    }
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self focusAssistantInput];
}

- (void)focusAssistantInput {
    [self.view.window makeFirstResponder:self.inputView];
}

- (void)removeCitationId:(NSString *)citationId {
    if (citationId.length == 0) return;
    NSUInteger idx = [self.citations indexOfObjectPassingTest:^BOOL(AIAssistantCitation *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.citationId isEqualToString:citationId];
    }];
    if (idx != NSNotFound) {
        [self.citations removeObjectAtIndex:idx];
        [self reloadCitationChips];
    }
}

- (CGFloat)citationAvailableWidth {
    CGFloat w = NSWidth(self.citationScroll.bounds);
    if (w < 40) {
        w = MAX(120.0, self.currentWidth - kRailWidth - 36.0);
    }
    return w;
}

- (void)reloadCitationChips {
    for (NSView *v in [self.citationStack.arrangedSubviews copy]) {
        [self.citationStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    BOOL has = self.citations.count > 0;
    self.citationScroll.hidden = !has;
    if (!has) {
        self.citationHeightConstraint.constant = 0;
        return;
    }

    CGFloat avail = [self citationAvailableWidth];
    NSStackView *row = nil;
    CGFloat rowUsed = 0;
    NSInteger rowCount = 0;

    for (AIAssistantCitation *c in self.citations) {
        NSView *chip = [self chipViewForCitation:c];
        [chip layoutSubtreeIfNeeded];
        CGFloat chipW = chip.fittingSize.width;
        if (chipW < 1) {
            chipW = 72;
        }
        BOOL needNewRow = (row == nil) ||
            (row.arrangedSubviews.count > 0 && rowUsed + kCitationChipSpacing + chipW > avail);
        if (needNewRow) {
            row = [NSStackView stackViewWithViews:@[]];
            row.translatesAutoresizingMaskIntoConstraints = NO;
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.alignment = NSLayoutAttributeCenterY;
            row.spacing = kCitationChipSpacing;
            [row.heightAnchor constraintEqualToConstant:kCitationChipRowHeight].active = YES;
            [self.citationStack addArrangedSubview:row];
            rowUsed = 0;
            rowCount += 1;
        }
        [row addArrangedSubview:chip];
        rowUsed += (row.arrangedSubviews.count > 1 ? kCitationChipSpacing : 0) + chipW;
    }

    CGFloat contentH = rowCount * kCitationChipRowHeight
        + MAX(0, rowCount - 1) * kCitationChipSpacing
        + 4;
    CGFloat maxH = kCitationMaxVisibleRows * kCitationChipRowHeight
        + MAX(0, kCitationMaxVisibleRows - 1) * kCitationChipSpacing
        + 4;
    self.citationScroll.hasVerticalScroller = (contentH > maxH + 0.5);
    self.citationHeightConstraint.constant = MIN(contentH, maxH);
}

- (NSView *)chipViewForCitation:(AIAssistantCitation *)citation {
    NSView *chip = [[NSView alloc] initWithFrame:NSZeroRect];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.wantsLayer = YES;
    chip.layer.cornerRadius = 6;
    chip.layer.masksToBounds = YES;
    if (@available(macOS 10.14, *)) {
        chip.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.10].CGColor;
        chip.layer.borderColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.28].CGColor;
    } else {
        chip.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.05].CGColor;
        chip.layer.borderColor = NSColor.gridColor.CGColor;
    }
    chip.layer.borderWidth = 1.0;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.wantsLayer = YES;
    icon.layer.cornerRadius = 3;
    icon.layer.masksToBounds = YES;
    CGFloat iconSize = 14;
    if (citation.kind == AIAssistantCitationKindImage) {
        iconSize = 16;
        if (citation.previewImage) {
            citation.previewImage.template = NO;
            icon.image = citation.previewImage;
        } else {
            NSImage *ph = [NSImage imageNamed:NSImageNameIconViewTemplate];
            ph.template = YES;
            icon.image = ph;
        }
        icon.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.05].CGColor;
    } else if (citation.kind == AIAssistantCitationKindFile) {
        NSString *ext = citation.url.pathExtension.length ? citation.url.pathExtension : @"txt";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        icon.image = [[NSWorkspace sharedWorkspace] iconForFileType:ext]
            ?: [NSImage imageNamed:NSImageNameMultipleDocuments];
#pragma clang diagnostic pop
    } else if (citation.kind == AIAssistantCitationKindText ||
               citation.kind == AIAssistantCitationKindPageArticle ||
               citation.kind == AIAssistantCitationKindPageMarkdown) {
        icon.image = [NSImage imageNamed:NSImageNameFontPanel];
    } else if (citation.kind == AIAssistantCitationKindPageOutline) {
        icon.image = [NSImage imageNamed:NSImageNameListViewTemplate];
    } else if (citation.kind == AIAssistantCitationKindPageHTML) {
        icon.image = [NSImage imageNamed:NSImageNameActionTemplate];
    } else if (citation.kind == AIAssistantCitationKindPageMeta) {
        if (@available(macOS 11.0, *)) {
            icon.image = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil];
        } else {
            icon.image = [NSImage imageNamed:NSImageNameNetwork];
        }
    } else {
        icon.image = [NSImage imageNamed:NSImageNameNetwork];
    }

    NSTextField *label = [NSTextField labelWithString:citation.chipLabel];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:10];
    label.textColor = NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.toolTip = @"点击预览 · ✕ 移除";
    if (citation.kind == AIAssistantCitationKindImage) {
        NSMutableString *tip = [NSMutableString stringWithString:@"点击预览\n"];
        if (citation.url.absoluteString.length) {
            [tip appendFormat:@"图片：%@\n", citation.url.absoluteString];
        }
        if (citation.sourcePageURL.absoluteString.length) {
            [tip appendFormat:@"网页：%@", citation.sourcePageURL.absoluteString];
        }
        label.toolTip = tip;
    }

    NSButton *remove = [NSButton buttonWithTitle:@"✕" target:self action:@selector(citationRemoveClicked:)];
    remove.translatesAutoresizingMaskIntoConstraints = NO;
    remove.bezelStyle = NSBezelStyleInline;
    remove.bordered = NO;
    remove.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
    remove.identifier = citation.citationId;
    remove.toolTip = @"移除引用";

    [chip addSubview:icon];
    [chip addSubview:label];
    [chip addSubview:remove];

    NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(citationChipClicked:)];
    click.numberOfClicksRequired = 1;
    [chip addGestureRecognizer:click];
    chip.identifier = citation.citationId;

    [NSLayoutConstraint activateConstraints:@[
        [chip.heightAnchor constraintEqualToConstant:kCitationChipRowHeight],
        [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:4],
        [icon.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:iconSize],
        [icon.heightAnchor constraintEqualToConstant:iconSize],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:4],
        [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [label.trailingAnchor constraintEqualToAnchor:remove.leadingAnchor constant:-1],
        [label.widthAnchor constraintLessThanOrEqualToConstant:96],
        [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-2],
        [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [remove.widthAnchor constraintEqualToConstant:14],
        [remove.heightAnchor constraintEqualToConstant:14],
    ]];
    return chip;
}

- (void)citationRemoveClicked:(NSButton *)sender {
    [self removeCitationId:sender.identifier];
    [self refreshPageContextTray];
}

- (nullable AIAssistantCitation *)citationWithId:(NSString *)cid {
    if (cid.length == 0) return nil;
    for (AIAssistantCitation *c in self.citations) {
        if ([c.citationId isEqualToString:cid]) return c;
    }
    return nil;
}

- (void)citationChipClicked:(NSClickGestureRecognizer *)gr {
    if (gr.state != NSGestureRecognizerStateEnded) return;
    NSView *chip = gr.view;
    // 点在 ✕ 上时不弹预览
    NSPoint p = [gr locationInView:chip];
    for (NSView *sub in chip.subviews) {
        if (![sub isKindOfClass:[NSButton class]]) continue;
        if (NSPointInRect(p, sub.frame)) return;
    }
    AIAssistantCitation *c = [self citationWithId:chip.identifier];
    if (!c) return;
    [self showPreviewForCitation:c relativeToView:chip];
}

- (void)showPreviewForCitation:(AIAssistantCitation *)citation relativeToView:(NSView *)anchor {
    if (!citation || !anchor) return;
    [self.citationPreviewPopover performClose:nil];

    NSUInteger chars = citation.body.length;
    NSMutableString *header = [NSMutableString stringWithFormat:@"%@ · %lu 字",
                               citation.kindDisplayName, (unsigned long)chars];
    if ([citation.body containsString:@"…（已截断）"] ||
        [citation.body containsString:@"HTML 已截断"] ||
        [citation.title containsString:@"…"]) {
        [header appendString:@" · 已截断"];
    }

    NSArray<NSString *> *lines = [citation.body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *previewLines = [NSMutableArray array];
    NSUInteger count = 0;
    for (NSString *line in lines) {
        if (count >= 20) {
            [previewLines addObject:@"…"];
            break;
        }
        [previewLines addObject:line];
        count += 1;
    }
    NSString *body = [previewLines componentsJoinedByString:@"\n"];

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 220)];
    NSTextField *title = [NSTextField labelWithString:header];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    title.lineBreakMode = NSLineBreakByTruncatingTail;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    SBTextView *tv = [SBTextView standardTextView];
    tv.string = body.length ? body : @"(空)";
    tv.editable = NO;
    tv.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    if (![tv.font.fontName containsString:@"Mono"]) {
        tv.font = [NSFont userFixedPitchFontOfSize:11] ?: [NSFont systemFontOfSize:11];
    }
    tv.textContainerInset = NSMakeSize(6, 6);
    scroll.documentView = tv;
    [content addSubview:title];
    [content addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:4],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-4],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
        [content.widthAnchor constraintEqualToConstant:320],
        [content.heightAnchor constraintEqualToConstant:220],
    ]];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = content;
    vc.preferredContentSize = NSMakeSize(320, 220);

    NSPopover *pop = [[NSPopover alloc] init];
    pop.contentViewController = vc;
    pop.behavior = NSPopoverBehaviorTransient;
    self.citationPreviewPopover = pop;
    [pop showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}

- (void)applyPreviewImage:(NSImage *)img forCitationId:(NSString *)cid {
    if (!img || cid.length == 0) return;
    for (AIAssistantCitation *c in self.citations) {
        if ([c.citationId isEqualToString:cid]) {
            c.previewImage = img;
            [self reloadCitationChips];
            break;
        }
    }
}

- (void)loadThumbnailForCitation:(AIAssistantCitation *)citation {
    NSURL *url = citation.url;
    if (!url) return;
    NSString *cid = citation.citationId;
    __weak typeof(self) weakSelf = self;

    // data: / 本地 file: 直接解码
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    if ([scheme isEqualToString:@"data"]) {
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                                completionHandler:^(NSData *data, NSURLResponse *r, NSError *error) {
            (void)r;
            if (error || data.length == 0) return;
            NSImage *img = [[NSImage alloc] initWithData:data];
            if (!img) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf applyPreviewImage:img forCitationId:cid];
            });
        }];
        [task resume];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20;
    // 部分站点防盗链：带上所在页 Referer
    NSString *referer = citation.sourcePageURL.absoluteString;
    if (referer.length > 0) {
        [req setValue:referer forHTTPHeaderField:@"Referer"];
    }
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (error || data.length == 0) return;
        NSImage *img = [[NSImage alloc] initWithData:data];
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyPreviewImage:img forCitationId:cid];
        });
    }];
    [task resume];
}

@end
