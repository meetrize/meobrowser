#import "AIBridgeSidebarController.h"
#import "AIBridgeService.h"
#import "AIBridgePreferences.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeDOMProvider.h"
#import "SBTextField.h"
#import "BrowserTab.h"

static const CGFloat kSidebarWidth = 320.0;

@interface AIBridgeFlippedView : NSView
@end
@implementation AIBridgeFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface AIBridgeSidebarController () <NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) NSView *view;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, assign, readwrite) BOOL visible;

@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *urlLabel;
@property (nonatomic, strong) SBTextField *tokenField;
@property (nonatomic, strong) NSPopUpButton *providerPopup;
@property (nonatomic, strong) NSTextField *bindLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSButton *startStopButton;
@property (nonatomic, strong, nullable) id prefsObserver;
@property (nonatomic, strong, nullable) id registryObserver;
@property (nonatomic, strong, nullable) id serviceObserver;
@end

@implementation AIBridgeSidebarController

- (instancetype)init {
    self = [super init];
    if (self) {
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

- (void)buildUI {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.clipsToBounds = YES;
    root.hidden = YES;
    root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    self.widthConstraint = [root.widthAnchor constraintEqualToConstant:0];
    self.widthConstraint.active = YES;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    AIBridgeFlippedView *content = [[AIBridgeFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, 760)];
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
    [self.providerPopup addItemWithTitle:@"DeepSeek 网页"];
    self.providerPopup.lastItem.representedObject = @"deepseek";
    [self.providerPopup addItemWithTitle:@"Kimi 网页"];
    self.providerPopup.lastItem.representedObject = @"kimi";
    [self.providerPopup addItemWithTitle:@"问财 网页"];
    self.providerPopup.lastItem.representedObject = @"iwencai";
    [self.providerPopup addItemWithTitle:@"豆包 网页"];
    self.providerPopup.lastItem.representedObject = @"doubao";
    [self.providerPopup addItemWithTitle:@"Gemini 网页"];
    self.providerPopup.lastItem.representedObject = @"gemini";
    [self.providerPopup addItemWithTitle:@"ChatGPT 网页"];
    self.providerPopup.lastItem.representedObject = @"chatgpt";
    [self.providerPopup addItemWithTitle:@"Mock 对话页"];
    self.providerPopup.lastItem.representedObject = @"mock";

    NSButton *bindBtn = [NSButton buttonWithTitle:@"绑定当前标签" target:self action:@selector(bindClicked:)];
    bindBtn.translatesAutoresizingMaskIntoConstraints = NO;
    bindBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *unbindBtn = [NSButton buttonWithTitle:@"解绑" target:self action:@selector(unbindClicked:)];
    unbindBtn.translatesAutoresizingMaskIntoConstraints = NO;
    unbindBtn.bezelStyle = NSBezelStyleRounded;

    NSButton *probeBtn = [NSButton buttonWithTitle:@"探测" target:self action:@selector(probeClicked:)];
    probeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    probeBtn.bezelStyle = NSBezelStyleRounded;

    self.bindLabel = [NSTextField wrappingLabelWithString:@"未绑定"];
    self.bindLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bindLabel.font = [NSFont systemFontOfSize:11];
    self.bindLabel.textColor = NSColor.secondaryLabelColor;

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
         "请遵守各 AI 平台条款，仅供个人实验。"];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = NSColor.tertiaryLabelColor;

    [content addSubview:title];
    [content addSubview:close];
    [content addSubview:self.statusLabel];
    [content addSubview:self.urlLabel];
    [content addSubview:self.startStopButton];
    [content addSubview:tokenCaption];
    [content addSubview:self.tokenField];
    [content addSubview:copyToken];
    [content addSubview:regen];
    [content addSubview:bindCaption];
    [content addSubview:self.providerPopup];
    [content addSubview:bindBtn];
    [content addSubview:unbindBtn];
    [content addSubview:probeBtn];
    [content addSubview:self.bindLabel];
    [content addSubview:newChatBtn];
    [content addSubview:cancelBtn];
    [content addSubview:copyURL];
    [content addSubview:copyCurl];
    [content addSubview:logCaption];
    [content addSubview:logScroll];
    [content addSubview:hint];

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
        [probeBtn.centerYAnchor constraintEqualToAnchor:bindBtn.centerYAnchor],
        [probeBtn.leadingAnchor constraintEqualToAnchor:unbindBtn.trailingAnchor constant:8],

        [self.bindLabel.topAnchor constraintEqualToAnchor:bindBtn.bottomAnchor constant:8],
        [self.bindLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.bindLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [newChatBtn.topAnchor constraintEqualToAnchor:self.bindLabel.bottomAnchor constant:10],
        [newChatBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [cancelBtn.centerYAnchor constraintEqualToAnchor:newChatBtn.centerYAnchor],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:newChatBtn.trailingAnchor constant:8],

        [copyURL.topAnchor constraintEqualToAnchor:newChatBtn.bottomAnchor constant:8],
        [copyURL.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [copyCurl.centerYAnchor constraintEqualToAnchor:copyURL.centerYAnchor],
        [copyCurl.leadingAnchor constraintEqualToAnchor:copyURL.trailingAnchor constant:8],

        [logCaption.topAnchor constraintEqualToAnchor:copyURL.bottomAnchor constant:16],
        [logCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],

        [logScroll.topAnchor constraintEqualToAnchor:logCaption.bottomAnchor constant:6],
        [logScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [logScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [logScroll.heightAnchor constraintEqualToConstant:140],

        [hint.topAnchor constraintEqualToAnchor:logScroll.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [hint.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
    ]];

    scroll.documentView = content;
    [root addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];

    self.view = root;
    [self reloadUI];
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.visible = visible;
    self.view.hidden = NO;
    CGFloat target = visible ? kSidebarWidth : 0;
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

- (void)reloadUI {
    AIBridgeService *svc = AIBridgeService.sharedService;
    AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
    self.statusLabel.stringValue = svc.statusText;
    self.urlLabel.stringValue = svc.baseURLString;
    self.tokenField.stringValue = prefs.bearerToken ?: @"";
    self.startStopButton.title = svc.isListening ? @"停止服务" : @"启动服务";

    NSString *pid = [self selectedProviderId];
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    if (b && b.tab) {
        self.bindLabel.stringValue = [NSString stringWithFormat:@"已绑定 %@ → %@\n%@",
                                      b.modelId, b.tabTitle ?: @"标签", b.pageURL ?: @""];
    } else {
        self.bindLabel.stringValue = @"未绑定（请打开对应 AI 页后点「绑定当前标签」）";
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
}

#pragma mark - Actions

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.delegate aiBridgeSidebarDidRequestClose:self];
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
    }
    [self reloadUI];
}

- (void)unbindClicked:(id)sender {
    (void)sender;
    [[AIBridgeService sharedService] unbindProviderId:[self selectedProviderId]];
    [self reloadUI];
}

- (void)probeClicked:(id)sender {
    (void)sender;
    WKWebView *wv = [self.delegate aiBridgeSidebarCurrentWebView:self];
    if (!wv) {
        self.bindLabel.stringValue = @"当前无网页可探测";
        return;
    }
    NSString *pid = [self selectedProviderId];
    __weak typeof(self) weakSelf = self;
    [[AIBridgeDOMProvider sharedProvider] ensureReadyOnWebView:wv providerId:pid completion:^(NSError *error) {
        if (error) {
            weakSelf.bindLabel.stringValue = error.localizedDescription;
            return;
        }
        [[AIBridgeDOMProvider sharedProvider] probeOnWebView:wv completion:^(NSDictionary *result, NSError *probeErr) {
            if (probeErr) {
                weakSelf.bindLabel.stringValue = probeErr.localizedDescription;
                return;
            }
            weakSelf.bindLabel.stringValue = [NSString stringWithFormat:@"probe: %@", result ?: @{}];
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
        [weakSelf reloadUI];
    }];
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    [[AIBridgeService sharedService] cancelAllJobs];
    self.bindLabel.stringValue = @"已取消排队/当前任务";
    [self reloadUI];
}

@end
