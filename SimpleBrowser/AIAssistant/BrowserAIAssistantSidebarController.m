#import "BrowserAIAssistantSidebarController.h"
#import "BrowserAIAssistantPreferences.h"
#import "BrowserAIAssistantPrompts.h"
#import "BrowserAIAssistantClient.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeService.h"
#import "SBTextView.h"

static const CGFloat kSidebarDefaultWidth = 360.0;
static const CGFloat kSidebarMinWidth = 280.0;
static const CGFloat kSidebarMaxWidth = 560.0;

@interface BrowserAIAssistantFlippedView : NSView
@end
@implementation BrowserAIAssistantFlippedView
- (BOOL)isFlipped { return YES; }
@end

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

@interface BrowserAIAssistantSidebarController ()
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat dragStartWidth;
@property (nonatomic, assign) BOOL isResizingWidth;
@property (nonatomic, strong) BrowserAIAssistantResizeView *resizeHandle;

@property (nonatomic, strong) NSPopUpButton *modelPopup;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *transcriptView;
@property (nonatomic, strong) SBTextView *inputView;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *bridgeButton;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, strong) NSMutableString *transcriptBuffer;

@property (nonatomic, strong, nullable) id registryObserver;
@property (nonatomic, strong, nullable) id serviceObserver;
@end

@implementation BrowserAIAssistantSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
        CGFloat w = BrowserAIAssistantPreferences.sharedPreferences.sidebarWidth;
        if (w < kSidebarMinWidth || w > kSidebarMaxWidth) w = kSidebarDefaultWidth;
        _currentWidth = w;
        _transcriptBuffer = [NSMutableString string];
        [self buildUI];
        __weak typeof(self) weakSelf = self;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        _registryObserver = [nc addObserverForName:AIBridgeRegistryDidChangeNotification
                                             object:nil
                                              queue:NSOperationQueue.mainQueue
                                         usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
        _serviceObserver = [nc addObserverForName:AIBridgeServiceStateDidChangeNotification
                                            object:nil
                                             queue:NSOperationQueue.mainQueue
                                        usingBlock:^(__unused NSNotification *n) {
            [weakSelf reloadUI];
        }];
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (self.registryObserver) [nc removeObserver:self.registryObserver];
    if (self.serviceObserver) [nc removeObserver:self.serviceObserver];
}

#pragma mark - UI

- (NSTextField *)makeCaption:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    f.textColor = NSColor.secondaryLabelColor;
    return f;
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

    NSTextField *title = [NSTextField labelWithString:@"AI 助手"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    NSButton *closeBtn = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeClicked:)];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.bezelStyle = NSBezelStyleRounded;
    closeBtn.controlSize = NSControlSizeSmall;

    NSTextField *modelCaption = [self makeCaption:@"模型（Bridge 平台）"];
    self.modelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modelPopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.modelPopup.target = self;
    self.modelPopup.action = @selector(modelChanged:);

    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.maximumNumberOfLines = 3;

    self.bridgeButton = [NSButton buttonWithTitle:@"打开 AI Bridge" target:self action:@selector(openBridgeClicked:)];
    self.bridgeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.bridgeButton.bezelStyle = NSBezelStyleRounded;
    self.bridgeButton.controlSize = NSControlSizeSmall;

    NSTextField *chatCaption = [self makeCaption:@"对话"];
    NSScrollView *transcriptScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    transcriptScroll.translatesAutoresizingMaskIntoConstraints = NO;
    transcriptScroll.hasVerticalScroller = YES;
    transcriptScroll.borderType = NSBezelBorder;
    transcriptScroll.drawsBackground = YES;
    NSTextView *transcript = [[NSTextView alloc] initWithFrame:NSZeroRect];
    transcript.editable = NO;
    transcript.selectable = YES;
    transcript.font = [NSFont systemFontOfSize:12];
    transcript.textContainerInset = NSMakeSize(6, 6);
    transcript.string = @"";
    transcriptScroll.documentView = transcript;
    self.transcriptView = transcript;

    NSTextField *inputCaption = [self makeCaption:@"输入"];
    NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    inputScroll.translatesAutoresizingMaskIntoConstraints = NO;
    inputScroll.hasVerticalScroller = YES;
    inputScroll.borderType = NSBezelBorder;
    SBTextView *input = [SBTextView standardTextView];
    input.font = [NSFont systemFontOfSize:12];
    inputScroll.documentView = input;
    self.inputView = input;

    self.sendButton = [NSButton buttonWithTitle:@"发送" target:self action:@selector(sendClicked:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.keyEquivalent = @"\r";

    self.cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelClicked:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.enabled = NO;

    NSButton *clearBtn = [NSButton buttonWithTitle:@"清空" target:self action:@selector(clearClicked:)];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    clearBtn.bezelStyle = NSBezelStyleRounded;
    clearBtn.controlSize = NSControlSizeSmall;

    NSArray *views = @[
        title, closeBtn, modelCaption, self.modelPopup, self.statusLabel, self.bridgeButton,
        chatCaption, transcriptScroll, inputCaption, inputScroll,
        self.sendButton, self.cancelButton, clearBtn
    ];
    for (NSView *v in views) {
        [root addSubview:v];
    }
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

        [title.topAnchor constraintEqualToAnchor:root.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],

        [closeBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],

        [modelCaption.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [modelCaption.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],

        [self.modelPopup.topAnchor constraintEqualToAnchor:modelCaption.bottomAnchor constant:4],
        [self.modelPopup.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.modelPopup.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.modelPopup.bottomAnchor constant:6],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        [self.bridgeButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:6],
        [self.bridgeButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],

        [chatCaption.topAnchor constraintEqualToAnchor:self.bridgeButton.bottomAnchor constant:12],
        [chatCaption.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],

        [transcriptScroll.topAnchor constraintEqualToAnchor:chatCaption.bottomAnchor constant:4],
        [transcriptScroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [transcriptScroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        [inputCaption.topAnchor constraintEqualToAnchor:transcriptScroll.bottomAnchor constant:10],
        [inputCaption.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],

        [inputScroll.topAnchor constraintEqualToAnchor:inputCaption.bottomAnchor constant:4],
        [inputScroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [inputScroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [inputScroll.heightAnchor constraintEqualToConstant:88],

        [self.sendButton.topAnchor constraintEqualToAnchor:inputScroll.bottomAnchor constant:8],
        [self.sendButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.sendButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-14],

        [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.sendButton.trailingAnchor constant:8],

        [clearBtn.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [clearBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        [transcriptScroll.bottomAnchor constraintEqualToAnchor:inputCaption.topAnchor constant:-10],
        [transcriptScroll.heightAnchor constraintGreaterThanOrEqualToConstant:160],
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
    BrowserAIAssistantPreferences.sharedPreferences.sidebarWidth = self.currentWidth;
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.visible = visible;
    self.view.hidden = NO;
    CGFloat target = visible ? self.currentWidth : 0;
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
        self.widthConstraint.constant = target;
        if (!visible) {
            self.view.hidden = YES;
        }
    }
    if (visible) {
        [self reloadUI];
    }
}

#pragma mark - Model

- (NSString *)selectedProviderId {
    id obj = self.modelPopup.selectedItem.representedObject;
    return [obj isKindOfClass:[NSString class]] ? obj : @"deepseek";
}

- (NSString *)selectedModelId {
    return [NSString stringWithFormat:@"bridge__%@", [self selectedProviderId]];
}

- (BOOL)isProviderBound:(NSString *)pid {
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    return b && b.tab != nil;
}

- (void)reloadModelPopup {
    NSString *wantModel = BrowserAIAssistantPreferences.sharedPreferences.lastModelId ?: @"bridge__deepseek";
    NSString *wantPid = [wantModel hasPrefix:@"bridge__"] ? [wantModel substringFromIndex:8] : @"deepseek";
    NSInteger selected = 0;
    [self.modelPopup removeAllItems];
    NSInteger idx = 0;
    for (NSDictionary *p in [BrowserAIAssistantPrompts providerCatalog]) {
        NSString *pid = p[@"id"];
        NSString *title = p[@"title"];
        BOOL bound = [self isProviderBound:pid];
        NSString *label = [NSString stringWithFormat:@"%@ %@", bound ? @"●" : @"○", title];
        [self.modelPopup addItemWithTitle:label];
        self.modelPopup.lastItem.representedObject = pid;
        if ([pid isEqualToString:wantPid]) {
            selected = idx;
        }
        idx++;
    }
    if (self.modelPopup.numberOfItems > 0) {
        [self.modelPopup selectItemAtIndex:selected];
    }
}

- (void)reloadUI {
    [self reloadModelPopup];
    NSString *pid = [self selectedProviderId];
    BOOL bound = [self isProviderBound:pid];
    AIBridgeService *svc = AIBridgeService.sharedService;

    if (!bound) {
        self.statusLabel.stringValue = @"未绑定，无法使用。请在 AI Bridge 侧栏绑定对应网页标签。";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        self.sendButton.enabled = NO;
    } else {
        NSString *listen = svc.isListening
            ? [NSString stringWithFormat:@"已绑定 · Bridge %@", svc.statusText ?: @"空闲"]
            : @"已绑定 · Bridge 未启动（发送时将自动启动）";
        self.statusLabel.stringValue = listen;
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
        self.sendButton.enabled = !self.inFlight;
    }
    self.cancelButton.enabled = self.inFlight;
    self.modelPopup.enabled = !self.inFlight;
}

#pragma mark - Transcript

- (void)appendTranscriptRole:(NSString *)role text:(NSString *)text {
    if (self.transcriptBuffer.length > 0) {
        [self.transcriptBuffer appendString:@"\n\n"];
    }
    [self.transcriptBuffer appendFormat:@"【%@】\n%@", role, text ?: @""];
    self.transcriptView.string = self.transcriptBuffer;
    [self.transcriptView scrollRangeToVisible:NSMakeRange(self.transcriptView.string.length, 0)];
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.delegate aiAssistantSidebarDidRequestClose:self];
}

- (void)openBridgeClicked:(id)sender {
    (void)sender;
    [self.delegate aiAssistantSidebarDidRequestOpenBridge:self];
}

- (void)modelChanged:(id)sender {
    (void)sender;
    BrowserAIAssistantPreferences.sharedPreferences.lastModelId = [self selectedModelId];
    [self reloadUI];
}

- (void)clearClicked:(id)sender {
    (void)sender;
    [self.transcriptBuffer setString:@""];
    self.transcriptView.string = @"";
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    [[BrowserAIAssistantClient sharedClient] cancelInFlight];
    self.inFlight = NO;
    [self appendTranscriptRole:@"系统" text:@"已取消"];
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
    NSString *pid = [self selectedProviderId];
    if (![self isProviderBound:pid]) {
        self.statusLabel.stringValue = @"未绑定，无法使用。请在 AI Bridge 侧栏绑定对应网页标签。";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
        self.sendButton.enabled = NO;
        return;
    }

    NSString *model = [self selectedModelId];
    BrowserAIAssistantPreferences.sharedPreferences.lastModelId = model;
    [self appendTranscriptRole:@"你" text:text];
    if (clearInput) {
        self.inputView.string = @"";
    }
    self.inFlight = YES;
    [self reloadUI];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"请求中… %@", model];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;

    __weak typeof(self) weakSelf = self;
    [[BrowserAIAssistantClient sharedClient] chatWithModel:model prompt:text completion:^(NSInteger httpStatus, NSString *assistantText, NSString *errorMessage) {
        weakSelf.inFlight = NO;
        if (errorMessage.length) {
            [weakSelf appendTranscriptRole:@"错误" text:[NSString stringWithFormat:@"HTTP %ld · %@", (long)httpStatus, errorMessage]];
            weakSelf.statusLabel.stringValue = errorMessage;
            weakSelf.statusLabel.textColor = NSColor.systemRedColor;
        } else {
            [weakSelf appendTranscriptRole:@"助手" text:assistantText ?: @""];
            weakSelf.statusLabel.stringValue = [NSString stringWithFormat:@"完成 · HTTP %ld", (long)httpStatus];
            weakSelf.statusLabel.textColor = NSColor.systemGreenColor;
        }
        [weakSelf reloadUI];
    }];
}

- (void)presentAction:(NSString *)actionKey selection:(NSString *)selection autoSend:(BOOL)autoSend {
    NSString *prompt = [BrowserAIAssistantPrompts promptForAction:actionKey selection:selection ?: @""];
    self.inputView.string = prompt;
    [self reloadUI];
    BOOL bound = [self isProviderBound:[self selectedProviderId]];
    if (autoSend && bound) {
        [self sendPrompt:prompt clearInput:YES];
    } else if (!bound) {
        self.statusLabel.stringValue = @"未绑定，无法使用。请在 AI Bridge 侧栏绑定对应网页标签。";
        self.statusLabel.textColor = NSColor.systemOrangeColor;
    } else {
        NSString *title = [BrowserAIAssistantPrompts displayTitleForAction:actionKey];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已填入「%@」，可编辑后发送", title];
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
    }
}

@end
