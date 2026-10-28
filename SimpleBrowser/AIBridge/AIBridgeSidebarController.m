#import "AIBridgeSidebarController.h"
#import "AIBridgeService.h"
#import "AIBridgePreferences.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeDOMProvider.h"
#import "SBTextField.h"
#import "SBTextView.h"
#import "BrowserTab.h"

static const CGFloat kSidebarDefaultWidth = 320.0;
static const CGFloat kSidebarMinWidth = 260.0;
static const CGFloat kSidebarMaxWidth = 560.0;

@interface AIBridgeFlippedView : NSView
@end
@implementation AIBridgeFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface AIBridgeSidebarResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDragToOffset)(CGFloat mouseDeltaXFromStart);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@property (nonatomic, assign) CGFloat dragStartScreenX;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation AIBridgeSidebarResizeView
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

@interface AIBridgeSidebarController () <NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, strong) AIBridgeSidebarResizeView *resizeHandle;

@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *urlLabel;
@property (nonatomic, strong) SBTextField *tokenField;
@property (nonatomic, strong) NSPopUpButton *providerPopup;
@property (nonatomic, strong) NSTextField *bindLabel;
@property (nonatomic, strong) NSTextField *bindingsSummaryLabel;
@property (nonatomic, strong) NSTextView *logView;

@property (nonatomic, strong) SBTextView *testPromptView;
@property (nonatomic, strong) SBTextView *testResultView;
@property (nonatomic, strong) NSButton *testSendButton;
@property (nonatomic, strong) NSTextField *testStatusLabel;
@property (nonatomic, assign) BOOL testInFlight;

@property (nonatomic, strong) NSButton *startStopButton;
@property (nonatomic, strong, nullable) id prefsObserver;
@property (nonatomic, strong, nullable) id registryObserver;
@property (nonatomic, strong, nullable) id serviceObserver;
@end

@implementation AIBridgeSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        CGFloat w = AIBridgePreferences.sharedPreferences.sidebarWidth;
        if (w < kSidebarMinWidth || w > kSidebarMaxWidth) w = kSidebarDefaultWidth;
        _currentWidth = w;
        [self buildUI];
        __weak typeof(self) weakSelf = self;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        _prefsObserver = [nc addObserverForName:AIBridgePreferencesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
        _registryObserver = [nc addObserverForName:AIBridgeRegistryDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
        _serviceObserver = [nc addObserverForName:AIBridgeServiceStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (self.prefsObserver) [nc removeObserver:self.prefsObserver];
    if (self.registryObserver) [nc removeObserver:self.registryObserver];
    if (self.serviceObserver) [nc removeObserver:self.serviceObserver];
}

- (NSArray<NSDictionary *> *)providerCatalog {
    return @[
        @{@"id": @"deepseek", @"title": @"DeepSeek 网页"},
        @{@"id": @"kimi", @"title": @"Kimi 网页"},
        @{@"id": @"iwencai", @"title": @"问财 网页"},
        @{@"id": @"doubao", @"title": @"豆包 网页"},
        @{@"id": @"gemini", @"title": @"Gemini 网页"},
        @{@"id": @"chatgpt", @"title": @"ChatGPT 网页"},
        @{@"id": @"mock", @"title": @"Mock 对话页"},
    ];
}

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
    AIBridgeSidebarResizeView *handle = [[AIBridgeSidebarResizeView alloc] initWithFrame:NSZeroRect];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.onDragBegan = ^{
        weakSelf.dragStartWidth = weakSelf.currentWidth;
        weakSelf.isResizingWidth = YES;
    };
    handle.onDragToOffset = ^(CGFloat delta) {
        // 右侧栏：鼠标左移 → 变宽
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

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    AIBridgeFlippedView *content = [[AIBridgeFlippedView alloc] initWithFrame:NSMakeRect(0, 0, self.currentWidth, 1100)];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [NSTextField labelWithString:@"AI Bridge"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    NSButton *close = [NSButton buttonWithTitle:@"⟩" target:self action:@selector(closeClicked:)];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.bezelStyle = NSBezelStyleInline;
    close.bordered = NO;
    close.toolTip = @"关闭侧栏";

    self.statusLabel = [NSTextField labelWithString:@"服务未启动"];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;

    self.urlLabel = [NSTextField labelWithString:@"http://127.0.0.1:3921"];
    self.urlLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.urlLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.startStopButton = [NSButton buttonWithTitle:@"启动服务" target:self action:@selector(toggleServer:)];
    self.startStopButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.startStopButton.bezelStyle = NSBezelStyleRounded;

    NSTextField *tokenCaption = [NSTextField labelWithString:@"Bearer Token"];
    tokenCaption.translatesAutoresizingMaskIntoConstraints = NO;
    tokenCaption.font = [NSFont systemFontOfSize:11];
    tokenCaption.textColor = NSColor.secondaryLabelColor;

    self.tokenField = [SBTextField standardField];
    self.tokenField.translatesAutoresizingMaskIntoConstraints = NO;
    self.tokenField.editable = NO;
    self.tokenField.selectable = YES;

    NSButton *copyToken = [NSButton buttonWithTitle:@"复制 Token" target:self action:@selector(copyToken:)];
    copyToken.translatesAutoresizingMaskIntoConstraints = NO;
    copyToken.bezelStyle = NSBezelStyleRounded;

    NSButton *regen = [NSButton buttonWithTitle:@"重新生成" target:self action:@selector(regenToken:)];
    regen.translatesAutoresizingMaskIntoConstraints = NO;
    regen.bezelStyle = NSBezelStyleRounded;

    NSTextField *bindCaption = [NSTextField labelWithString:@"绑定"];
    bindCaption.translatesAutoresizingMaskIntoConstraints = NO;
    bindCaption.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    self.providerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.providerPopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.providerPopup.target = self;
    self.providerPopup.action = @selector(providerChanged:);
    for (NSDictionary *p in [self providerCatalog]) {
        [self.providerPopup addItemWithTitle:p[@"title"]];
        self.providerPopup.lastItem.representedObject = p[@"id"];
    }

    NSButton *bindBtn = [NSButton buttonWithTitle:@"绑定当前标签" target:self action:@selector(bindClicked:)];
    bindBtn.translatesAutoresizingMaskIntoConstraints = NO;
    bindBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *unbindBtn = [NSButton buttonWithTitle:@"解绑当前" target:self action:@selector(unbindClicked:)];
    unbindBtn.translatesAutoresizingMaskIntoConstraints = NO;
    unbindBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *unbindAllBtn = [NSButton buttonWithTitle:@"全部解绑" target:self action:@selector(unbindAllClicked:)];
    unbindAllBtn.translatesAutoresizingMaskIntoConstraints = NO;
    unbindAllBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *probeBtn = [NSButton buttonWithTitle:@"探测" target:self action:@selector(probeClicked:)];
    probeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    probeBtn.bezelStyle = NSBezelStyleRounded;

    self.bindLabel = [NSTextField wrappingLabelWithString:@"未绑定"];
    self.bindLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bindLabel.font = [NSFont systemFontOfSize:11];
    self.bindLabel.textColor = NSColor.secondaryLabelColor;

    self.bindingsSummaryLabel = [NSTextField wrappingLabelWithString:@"已绑定：无"];
    self.bindingsSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bindingsSummaryLabel.font = [NSFont systemFontOfSize:11];
    self.bindingsSummaryLabel.textColor = NSColor.secondaryLabelColor;

    NSButton *newChatBtn = [NSButton buttonWithTitle:@"新对话" target:self action:@selector(newChatClicked:)];
    newChatBtn.translatesAutoresizingMaskIntoConstraints = NO;
    newChatBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *cancelBtn = [NSButton buttonWithTitle:@"取消任务" target:self action:@selector(cancelClicked:)];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    cancelBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *copyURL = [NSButton buttonWithTitle:@"复制 Base URL" target:self action:@selector(copyBaseURL:)];
    copyURL.translatesAutoresizingMaskIntoConstraints = NO;
    copyURL.bezelStyle = NSBezelStyleRounded;

    NSButton *copyCurl = [NSButton buttonWithTitle:@"复制 curl 示例" target:self action:@selector(copyCurl:)];
    copyCurl.translatesAutoresizingMaskIntoConstraints = NO;
    copyCurl.bezelStyle = NSBezelStyleRounded;

    // —— 测试区 ——
    NSTextField *testCaption = [NSTextField labelWithString:@"快速测试"];
    testCaption.translatesAutoresizingMaskIntoConstraints = NO;
    testCaption.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    NSTextField *testHint = [NSTextField wrappingLabelWithString:@"对当前选中 Provider 调用本机 /v1/chat/completions"];
    testHint.translatesAutoresizingMaskIntoConstraints = NO;
    testHint.font = [NSFont systemFontOfSize:10];
    testHint.textColor = NSColor.tertiaryLabelColor;

    NSScrollView *promptScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    promptScroll.translatesAutoresizingMaskIntoConstraints = NO;
    promptScroll.hasVerticalScroller = YES;
    promptScroll.borderType = NSBezelBorder;
    promptScroll.drawsBackground = YES;
    SBTextView *promptView = [SBTextView standardTextView];
    promptView.font = [NSFont systemFontOfSize:12];
    promptView.string = @"";
    promptScroll.documentView = promptView;
    self.testPromptView = promptView;

    self.testSendButton = [NSButton buttonWithTitle:@"发送测试" target:self action:@selector(testSendClicked:)];
    self.testSendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.testSendButton.bezelStyle = NSBezelStyleRounded;
    self.testSendButton.keyEquivalent = @"\r";
    self.testSendButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    self.testStatusLabel = [NSTextField labelWithString:@""];
    self.testStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.testStatusLabel.font = [NSFont systemFontOfSize:11];
    self.testStatusLabel.textColor = NSColor.secondaryLabelColor;

    NSScrollView *resultScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    resultScroll.translatesAutoresizingMaskIntoConstraints = NO;
    resultScroll.hasVerticalScroller = YES;
    resultScroll.borderType = NSBezelBorder;
    SBTextView *resultView = [SBTextView standardTextView];
    resultView.editable = NO;
    resultView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    resultScroll.documentView = resultView;
    self.testResultView = resultView;

    NSTextField *logCaption = [NSTextField labelWithString:@"最近请求"];
    logCaption.translatesAutoresizingMaskIntoConstraints = NO;
    logCaption.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    NSScrollView *logScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    logScroll.hasVerticalScroller = YES;
    logScroll.borderType = NSBezelBorder;
    NSTextView *log = [[NSTextView alloc] initWithFrame:NSZeroRect];
    log.editable = NO;
    log.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    logScroll.documentView = log;
    self.logView = log;

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"仅本机 127.0.0.1。model：bridge__*（网页）/ ollama__* / openai__*。"
         "请遵守各 AI 平台条款，仅供个人实验。左侧边缘可拖拽调宽。"];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = NSColor.tertiaryLabelColor;

    NSArray *subs = @[
        title, close, self.statusLabel, self.urlLabel, self.startStopButton,
        tokenCaption, self.tokenField, copyToken, regen,
        bindCaption, self.providerPopup, bindBtn, unbindBtn, unbindAllBtn, probeBtn,
        self.bindLabel, self.bindingsSummaryLabel,
        newChatBtn, cancelBtn, copyURL, copyCurl,
        testCaption, testHint, promptScroll, self.testSendButton, self.testStatusLabel, resultScroll,
        logCaption, logScroll, hint
    ];
    for (NSView *v in subs) {
        [content addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],

        [self.statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [self.urlLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [self.urlLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.urlLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [self.startStopButton.topAnchor constraintEqualToAnchor:self.urlLabel.bottomAnchor constant:8],
        [self.startStopButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [tokenCaption.topAnchor constraintEqualToAnchor:self.startStopButton.bottomAnchor constant:14],
        [tokenCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [self.tokenField.topAnchor constraintEqualToAnchor:tokenCaption.bottomAnchor constant:4],
        [self.tokenField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.tokenField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [self.tokenField.heightAnchor constraintEqualToConstant:22],

        [copyToken.topAnchor constraintEqualToAnchor:self.tokenField.bottomAnchor constant:6],
        [copyToken.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [regen.centerYAnchor constraintEqualToAnchor:copyToken.centerYAnchor],
        [regen.leadingAnchor constraintEqualToAnchor:copyToken.trailingAnchor constant:8],

        [bindCaption.topAnchor constraintEqualToAnchor:copyToken.bottomAnchor constant:16],
        [bindCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [self.providerPopup.topAnchor constraintEqualToAnchor:bindCaption.bottomAnchor constant:6],
        [self.providerPopup.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.providerPopup.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [bindBtn.topAnchor constraintEqualToAnchor:self.providerPopup.bottomAnchor constant:8],
        [bindBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [unbindBtn.centerYAnchor constraintEqualToAnchor:bindBtn.centerYAnchor],
        [unbindBtn.leadingAnchor constraintEqualToAnchor:bindBtn.trailingAnchor constant:8],
        [unbindAllBtn.centerYAnchor constraintEqualToAnchor:bindBtn.centerYAnchor],
        [unbindAllBtn.leadingAnchor constraintEqualToAnchor:unbindBtn.trailingAnchor constant:8],

        [probeBtn.topAnchor constraintEqualToAnchor:bindBtn.bottomAnchor constant:8],
        [probeBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [self.bindLabel.topAnchor constraintEqualToAnchor:probeBtn.bottomAnchor constant:8],
        [self.bindLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.bindLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [self.bindingsSummaryLabel.topAnchor constraintEqualToAnchor:self.bindLabel.bottomAnchor constant:6],
        [self.bindingsSummaryLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.bindingsSummaryLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [newChatBtn.topAnchor constraintEqualToAnchor:self.bindingsSummaryLabel.bottomAnchor constant:10],
        [newChatBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [cancelBtn.centerYAnchor constraintEqualToAnchor:newChatBtn.centerYAnchor],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:newChatBtn.trailingAnchor constant:8],

        [copyURL.topAnchor constraintEqualToAnchor:newChatBtn.bottomAnchor constant:8],
        [copyURL.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [copyCurl.centerYAnchor constraintEqualToAnchor:copyURL.centerYAnchor],
        [copyCurl.leadingAnchor constraintEqualToAnchor:copyURL.trailingAnchor constant:8],

        [testCaption.topAnchor constraintEqualToAnchor:copyURL.bottomAnchor constant:16],
        [testCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [testHint.topAnchor constraintEqualToAnchor:testCaption.bottomAnchor constant:2],
        [testHint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [testHint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [promptScroll.topAnchor constraintEqualToAnchor:testHint.bottomAnchor constant:6],
        [promptScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [promptScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [promptScroll.heightAnchor constraintEqualToConstant:56],

        [self.testSendButton.topAnchor constraintEqualToAnchor:promptScroll.bottomAnchor constant:6],
        [self.testSendButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.testStatusLabel.centerYAnchor constraintEqualToAnchor:self.testSendButton.centerYAnchor],
        [self.testStatusLabel.leadingAnchor constraintEqualToAnchor:self.testSendButton.trailingAnchor constant:10],
        [self.testStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-14],

        [resultScroll.topAnchor constraintEqualToAnchor:self.testSendButton.bottomAnchor constant:8],
        [resultScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [resultScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [resultScroll.heightAnchor constraintEqualToConstant:120],

        [logCaption.topAnchor constraintEqualToAnchor:resultScroll.bottomAnchor constant:16],
        [logCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [logScroll.topAnchor constraintEqualToAnchor:logCaption.bottomAnchor constant:6],
        [logScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [logScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [logScroll.heightAnchor constraintEqualToConstant:110],

        [hint.topAnchor constraintEqualToAnchor:logScroll.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [hint.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
    ]];

    scroll.documentView = content;
    [root addSubview:scroll];
    [root addSubview:handle];
    [root addSubview:edgeSeparator];

    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:root.topAnchor],
        [handle.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [handle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [handle.widthAnchor constraintEqualToConstant:6],

        [edgeSeparator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [edgeSeparator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [edgeSeparator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [edgeSeparator.widthAnchor constraintEqualToConstant:1],

        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:6],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];

    self.view = root;
    [self reloadUI];
}

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
    AIBridgePreferences.sharedPreferences.sidebarWidth = self.currentWidth;
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.visible = visible;
    self.view.hidden = NO;
    CGFloat target = visible ? self.currentWidth : 0;
    void (^apply)(void) = ^{
        self.widthConstraint.constant = target;
        if (!visible) {
            self.view.hidden = YES;
        }
    };
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.18;
            self.widthConstraint.animator.constant = target;
        } completionHandler:^{
            if (!visible) {
                self.view.hidden = YES;
            }
        }];
    } else {
        apply();
    }
    if (visible) {
        [self reloadUI];
    }
}

- (NSString *)selectedProviderId {
    id obj = self.providerPopup.selectedItem.representedObject;
    return [obj isKindOfClass:[NSString class]] ? obj : @"deepseek";
}

- (BOOL)isProviderBound:(NSString *)pid {
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    return b && b.tab != nil;
}

- (void)refreshProviderPopupTitles {
    NSInteger selected = self.providerPopup.indexOfSelectedItem;
    NSString *selectedId = [self selectedProviderId];
    [self.providerPopup removeAllItems];
    for (NSDictionary *p in [self providerCatalog]) {
        NSString *pid = p[@"id"];
        BOOL bound = [self isProviderBound:pid];
        NSString *mark = bound ? @"●" : @"○";
        NSString *title = [NSString stringWithFormat:@"%@ %@", mark, p[@"title"]];
        [self.providerPopup addItemWithTitle:title];
        self.providerPopup.lastItem.representedObject = pid;
        if ([pid isEqualToString:selectedId]) {
            selected = self.providerPopup.numberOfItems - 1;
        }
    }
    if (selected >= 0 && selected < self.providerPopup.numberOfItems) {
        [self.providerPopup selectItemAtIndex:selected];
    }
}

- (void)reloadUI {
    if (self.isResizingWidth) return;

    AIBridgeService *svc = AIBridgeService.sharedService;
    AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
    self.statusLabel.stringValue = svc.statusText;
    self.urlLabel.stringValue = svc.baseURLString;
    self.tokenField.stringValue = prefs.bearerToken ?: @"";
    self.startStopButton.title = svc.isListening ? @"停止服务" : @"启动服务";

    [self refreshProviderPopupTitles];

    NSString *pid = [self selectedProviderId];
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    if (b && b.tab) {
        self.bindLabel.stringValue = [NSString stringWithFormat:@"当前 ● 已绑定 %@ → %@\n%@",
                                      b.modelId, b.tabTitle ?: @"标签", b.pageURL ?: @""];
        self.bindLabel.textColor = NSColor.systemGreenColor;
    } else {
        self.bindLabel.stringValue = @"当前 ○ 未绑定（打开对应 AI 页后点「绑定当前标签」）";
        self.bindLabel.textColor = NSColor.secondaryLabelColor;
    }

    NSArray<AIBridgeBinding *> *all = AIBridgeRegistry.sharedRegistry.allBindings;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (AIBridgeBinding *item in all) {
        if (!item.tab) continue;
        [lines addObject:[NSString stringWithFormat:@"● %@（%@）",
                          item.displayName ?: item.providerId,
                          item.modelId ?: @""]];
    }
    if (lines.count == 0) {
        self.bindingsSummaryLabel.stringValue = @"全部已绑定：无";
    } else {
        self.bindingsSummaryLabel.stringValue =
            [NSString stringWithFormat:@"全部已绑定（%lu）：\n%@",
             (unsigned long)lines.count, [lines componentsJoinedByString:@"\n"]];
    }

    NSMutableString *log = [NSMutableString string];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    for (AIBridgeRequestLogEntry *e in svc.recentRequests) {
        NSString *t = [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:e.timestamp]];
        [log appendFormat:@"%@  %@  %ld  %.1fs%@\n",
         t, e.modelId, (long)e.status, e.durationSec,
         e.detail.length ? [NSString stringWithFormat:@"  %@", e.detail] : @""];
    }
    if (log.length == 0) {
        [log appendString:@"（暂无）\n"];
    }
    self.logView.string = log;

    self.testSendButton.enabled = !self.testInFlight;
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.delegate aiBridgeSidebarDidRequestClose:self];
}

- (void)providerChanged:(id)sender {
    (void)sender;
    [self reloadUI];
}

- (void)toggleServer:(id)sender {
    (void)sender;
    AIBridgeService *svc = AIBridgeService.sharedService;
    if (svc.isListening) {
        [svc stopServer];
    } else {
        NSError *err = nil;
        if (![svc startServer:&err]) {
            self.statusLabel.stringValue = err.localizedDescription ?: @"启动失败";
        }
    }
    [self reloadUI];
}

- (void)copyToken:(id)sender {
    (void)sender;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:AIBridgePreferences.sharedPreferences.bearerToken ?: @"" forType:NSPasteboardTypeString];
}

- (void)regenToken:(id)sender {
    (void)sender;
    [AIBridgePreferences.sharedPreferences regenerateToken];
    [self reloadUI];
}

- (void)bindClicked:(id)sender {
    (void)sender;
    BrowserTab *tab = [self.delegate aiBridgeSidebarCurrentTab:self];
    NSURL *url = [self.delegate aiBridgeSidebarCurrentURL:self];
    NSError *err = nil;
    [[AIBridgeService sharedService] bindCurrentTab:tab
                                            pageURL:url
                                         providerId:[self selectedProviderId]
                                              error:&err];
    if (err) {
        self.bindLabel.stringValue = err.localizedDescription;
        self.bindLabel.textColor = NSColor.systemRedColor;
    }
    [self reloadUI];
}

- (void)unbindClicked:(id)sender {
    (void)sender;
    [[AIBridgeService sharedService] unbindProviderId:[self selectedProviderId]];
    [self reloadUI];
}

- (void)unbindAllClicked:(id)sender {
    (void)sender;
    [[AIBridgeService sharedService] unbindAllProviders];
    self.testStatusLabel.stringValue = @"已全部解绑";
    [self reloadUI];
}

- (void)probeClicked:(id)sender {
    (void)sender;
    NSString *pid = [self selectedProviderId];
    // 已绑定时探测绑定标签（与快速测试同一 WebView），避免误测当前前台页。
    WKWebView *wv = nil;
    AIBridgeBinding *binding = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    if (binding.tab) {
        [binding.tab wakeFromHibernationIfNeeded];
        if (binding.tab.pendingRestorableLoad) {
            [binding.tab loadPendingRestorableURLIfNeeded];
        }
        wv = binding.tab.webView ?: [binding.tab ensureWebView];
    }
    if (!wv) {
        wv = [self.delegate aiBridgeSidebarCurrentWebView:self];
    }
    if (!wv) {
        self.bindLabel.stringValue = @"当前无网页可探测";
        self.bindLabel.textColor = NSColor.systemOrangeColor;
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[AIBridgeDOMProvider sharedProvider] ensureReadyOnWebView:wv providerId:pid completion:^(NSError *error) {
        if (error) {
            weakSelf.bindLabel.stringValue = error.localizedDescription;
            weakSelf.bindLabel.textColor = NSColor.systemRedColor;
            return;
        }
        [[AIBridgeDOMProvider sharedProvider] probeOnWebView:wv completion:^(NSDictionary *result, NSError *probeErr) {
            if (probeErr) {
                weakSelf.bindLabel.stringValue = probeErr.localizedDescription;
                weakSelf.bindLabel.textColor = NSColor.systemRedColor;
                return;
            }
            BOOL hostOk = result[@"hostOk"] == nil || [result[@"hostOk"] boolValue];
            BOOL ok = [result[@"ok"] boolValue];
            weakSelf.bindLabel.stringValue = [NSString stringWithFormat:@"probe: %@", result ?: @{}];
            weakSelf.bindLabel.textColor = (ok && hostOk) ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
        }];
    }];
}

- (void)copyCurl:(id)sender {
    (void)sender;
    NSString *pid = [self selectedProviderId];
    NSString *model = [NSString stringWithFormat:@"bridge__%@", pid];
    NSString *curl = [[AIBridgeService sharedService] curlExampleForModel:model];
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:curl forType:NSPasteboardTypeString];
}

- (void)copyBaseURL:(id)sender {
    (void)sender;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:AIBridgeService.sharedService.baseURLString forType:NSPasteboardTypeString];
}

- (void)newChatClicked:(id)sender {
    (void)sender;
    NSString *pid = [self selectedProviderId];
    __weak typeof(self) weakSelf = self;
    [[AIBridgeService sharedService] newChatForProviderId:pid completion:^(BOOL ok, NSString *detail) {
        weakSelf.bindLabel.stringValue = ok ? @"已触发新对话" : (detail ?: @"新对话失败");
        weakSelf.bindLabel.textColor = ok ? NSColor.systemGreenColor : NSColor.systemRedColor;
        [weakSelf reloadUI];
    }];
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    [[AIBridgeService sharedService] cancelAllJobs];
    self.bindLabel.stringValue = @"已取消排队/当前任务";
    self.bindLabel.textColor = NSColor.secondaryLabelColor;
    [self reloadUI];
}

#pragma mark - Quick test

- (void)testSendClicked:(id)sender {
    (void)sender;
    if (self.testInFlight) return;

    NSString *prompt = [self.testPromptView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (prompt.length == 0) {
        self.testStatusLabel.stringValue = @"请输入提示词";
        self.testStatusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }

    NSString *pid = [self selectedProviderId];
    if (![self isProviderBound:pid]) {
        self.testStatusLabel.stringValue = @"当前 Provider 未绑定";
        self.testStatusLabel.textColor = NSColor.systemOrangeColor;
        return;
    }

    AIBridgeService *svc = AIBridgeService.sharedService;
    if (!svc.isListening) {
        NSError *err = nil;
        if (![svc startServer:&err]) {
            self.testStatusLabel.stringValue = err.localizedDescription ?: @"无法启动服务";
            self.testStatusLabel.textColor = NSColor.systemRedColor;
            return;
        }
    }

    NSString *model = [NSString stringWithFormat:@"bridge__%@", pid];
    NSString *token = AIBridgePreferences.sharedPreferences.bearerToken ?: @"";
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1/chat/completions", svc.baseURLString];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        self.testStatusLabel.stringValue = @"URL 无效";
        return;
    }

    NSDictionary *body = @{
        @"model": model,
        @"stream": @NO,
        @"messages": @[ @{ @"role": @"user", @"content": prompt } ]
    };
    NSError *jsonErr = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (!payload) {
        self.testStatusLabel.stringValue = jsonErr.localizedDescription ?: @"JSON 编码失败";
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = payload;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    req.timeoutInterval = 200;

    self.testInFlight = YES;
    self.testSendButton.enabled = NO;
    self.testStatusLabel.stringValue = [NSString stringWithFormat:@"请求中… %@", model];
    self.testStatusLabel.textColor = NSColor.secondaryLabelColor;
    self.testResultView.string = @"";

    __weak typeof(self) weakSelf = self;
    NSDate *started = [NSDate date];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.testInFlight = NO;
            weakSelf.testSendButton.enabled = YES;
            NSTimeInterval sec = [[NSDate date] timeIntervalSinceDate:started];
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            if (error) {
                weakSelf.testStatusLabel.stringValue = [NSString stringWithFormat:@"失败 %.1fs", sec];
                weakSelf.testStatusLabel.textColor = NSColor.systemRedColor;
                weakSelf.testResultView.string = error.localizedDescription ?: @"网络错误";
                [weakSelf reloadUI];
                return;
            }
            NSInteger code = http.statusCode;
            NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            NSString *answer = [weakSelf extractAssistantContentFromJSONData:data] ?: raw;
            if (code >= 200 && code < 300) {
                weakSelf.testStatusLabel.stringValue = [NSString stringWithFormat:@"成功 %ld · %.1fs", (long)code, sec];
                weakSelf.testStatusLabel.textColor = NSColor.systemGreenColor;
                weakSelf.testResultView.string = answer.length ? answer : @"（空回复）";
            } else {
                weakSelf.testStatusLabel.stringValue = [NSString stringWithFormat:@"HTTP %ld · %.1fs", (long)code, sec];
                weakSelf.testStatusLabel.textColor = NSColor.systemRedColor;
                weakSelf.testResultView.string = answer.length ? answer : raw;
            }
            [weakSelf reloadUI];
        });
    }] resume];
}

- (nullable NSString *)extractAssistantContentFromJSONData:(NSData *)data {
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *json = obj;
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
        NSString *msg = json[@"error"][@"message"];
        if ([msg isKindOfClass:[NSString class]]) return msg;
        NSString *message = json[@"message"];
        if ([message isKindOfClass:[NSString class]]) return message;
        return nil;
    }
    id first = choices.firstObject;
    if (![first isKindOfClass:[NSDictionary class]]) return nil;
    id message = first[@"message"];
    if ([message isKindOfClass:[NSDictionary class]]) {
        id content = message[@"content"];
        if ([content isKindOfClass:[NSString class]]) return content;
    }
    id text = first[@"text"];
    if ([text isKindOfClass:[NSString class]]) return text;
    return nil;
}

@end
