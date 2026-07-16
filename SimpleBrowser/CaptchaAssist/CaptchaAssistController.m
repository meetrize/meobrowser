#import "CaptchaAssistController.h"
#import "BrowserWindowController.h"
#import "CaptchaAssistPreferences.h"
#import "CaptchaDetector.h"
#import "CaptchaDetection.h"
#import "CaptchaCaptureService.h"
#import "CaptchaSessionLog.h"
#import "CaptchaAssistPanel.h"
#import "CaptchaPipeline.h"
#import "BrowserTransientToast.h"

static const NSTimeInterval kDetectionDebounceSeconds = 5.0;

@interface CaptchaAssistController () <CaptchaAssistPanelDelegate>
@property (nonatomic, strong) NSArray<CaptchaDetection *> *currentDetections;
@property (nonatomic, strong, nullable) NSImage *lastPreviewImage;
@property (nonatomic, strong, nullable) CaptchaAssistPanel *panel;
@property (nonatomic, assign) BOOL panelVisible;
@property (nonatomic, copy, nullable) NSString *lastDebounceKey;
@property (nonatomic, assign) NSTimeInterval lastDebounceTimestamp;
@property (nonatomic, copy, nullable) NSString *statusMessage;
@property (nonatomic, assign) BOOL isSolving;
@end

@implementation CaptchaAssistController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _currentDetections = @[];
    }
    return self;
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [CaptchaDetector installOnConfiguration:configuration messageHandler:self];
}

- (void)wireCaptchaButton:(NSButton *)button {
    self.captchaButton = button;
    button.target = self;
    button.action = @selector(toggleCaptchaAssistPanel:);
    [self refreshButtonAppearance];
}

#pragma mark - Navigation

- (void)updateForURL:(NSURL *)url {
    (void)url;
    [self refreshButtonAppearance];
    [self refreshPanelIfVisible];
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    (void)webView;
    (void)url;
    // 新文档会重新注入脚本；清空旧检测，等待新上报
    self.currentDetections = @[];
    self.lastPreviewImage = nil;
    self.lastDebounceKey = nil;
    [self refreshButtonAppearance];
    [self refreshPanelIfVisible];
}

#pragma mark - Script messages

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:CaptchaAssistHandlerName]) {
        return;
    }
    // 仅处理当前活动 WebView 的消息，避免后台标签干扰
    if (message.webView && self.windowController.webView &&
        message.webView != self.windowController.webView) {
        return;
    }

    id body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)body;
    NSString *event = dict[@"event"];
    NSString *pageURL = message.webView.URL.absoluteString;

    if ([event isEqualToString:@"cleared"]) {
        self.currentDetections = @[];
        [self refreshButtonAppearance];
        [self refreshPanelIfVisible];
        return;
    }

    if (![event isEqualToString:@"detected"]) {
        return;
    }

    NSArray *raw = dict[@"findings"];
    if (![raw isKindOfClass:[NSArray class]]) {
        return;
    }

    NSMutableArray<CaptchaDetection *> *parsed = [NSMutableArray array];
    for (id item in raw) {
        CaptchaDetection *d = [CaptchaDetection detectionFromMessageBody:item pageURL:pageURL];
        if (d) {
            [parsed addObject:d];
        }
    }

    NSString *debounceKey = [self debounceKeyForDetections:parsed];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    BOOL shouldHighlight = YES;
    if (self.lastDebounceKey && [self.lastDebounceKey isEqualToString:debounceKey] &&
        (now - self.lastDebounceTimestamp) < kDetectionDebounceSeconds) {
        shouldHighlight = (self.currentDetections.count == 0);
    }
    self.lastDebounceKey = debounceKey;
    self.lastDebounceTimestamp = now;

    self.currentDetections = [parsed copy];
    if (shouldHighlight) {
        [self refreshButtonAppearance];
    }
    [self refreshPanelIfVisible];
}

- (NSString *)debounceKeyForDetections:(NSArray<CaptchaDetection *> *)detections {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (CaptchaDetection *d in detections) {
        [parts addObject:[NSString stringWithFormat:@"%@:%@", d.vendor, d.kind]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@"|"];
}

#pragma mark - UI

- (void)refreshButtonAppearance {
    NSButton *button = self.captchaButton;
    if (!button) {
        return;
    }
    BOOL enabledPref = [CaptchaAssistPreferences assistEnabled];
    BOOL hasDetection = self.currentDetections.count > 0;
    button.enabled = YES; // 始终可点开面板开关

    if (@available(macOS 10.14, *)) {
        if (hasDetection && enabledPref) {
            button.contentTintColor = [NSColor controlAccentColor];
        } else {
            button.contentTintColor = [NSColor secondaryLabelColor];
        }
    }

    if (!enabledPref) {
        button.toolTip = @"验证码助手（已关闭 · 点击打开）";
    } else if (hasDetection) {
        CaptchaDetection *d = self.currentDetections.firstObject;
        button.toolTip = [NSString stringWithFormat:@"验证码助手 · 检测到 %@", [d summaryLabel]];
    } else {
        button.toolTip = @"验证码助手（未检测到验证码）";
    }
}

- (IBAction)toggleCaptchaAssistPanel:(id)sender {
    (void)sender;
    if (self.panelVisible && self.panel.isVisible) {
        [self.panel dismissPanel];
        return;
    }
    [self presentPanel];
}

- (void)presentPanel {
    if (!self.panel) {
        self.panel = [[CaptchaAssistPanel alloc] init];
        self.panel.panelDelegate = self;
    }
    [self refreshPanelContent];

    NSButton *button = self.captchaButton;
    NSRect buttonRect = button ? [button convertRect:button.bounds toView:nil] : NSZeroRect;
    NSRect screenRect = button ? [self.windowController.window convertRectToScreen:buttonRect] : NSZeroRect;
    self.panel.dismissExclusionRectOnScreen = NSInsetRect(screenRect, -4, -4);
    [self.panel presentAnchoredToRect:screenRect ofWindow:self.windowController.window];
    self.panelVisible = YES;
}

- (void)refreshPanelIfVisible {
    if (self.panelVisible && self.panel.isVisible) {
        [self refreshPanelContent];
    }
}

- (void)refreshPanelContent {
    CaptchaDetection *solvable = [CaptchaPipeline preferredSolvableDetectionFrom:self.currentDetections];
    BOOL solveEnabled = (solvable != nil) && [CaptchaAssistPreferences assistEnabled];
    [self.panel updateWithDetections:self.currentDetections
                       previewImage:self.lastPreviewImage
                            enabled:[CaptchaAssistPreferences assistEnabled]
                             status:self.statusMessage
                            solving:self.isSolving
                       solveEnabled:solveEnabled];
}

#pragma mark - Capture

- (void)captureNow {
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        self.statusMessage = @"当前没有可截图的页面。";
        [self refreshPanelIfVisible];
        return;
    }

    CaptchaDetection *primary = self.currentDetections.firstObject;
    CGRect rect = (primary && !CGRectIsNull(primary.rect)) ? primary.rect : CGRectNull;
    self.statusMessage = @"正在截图…";
    [self refreshPanelIfVisible];

    __weak typeof(self) weakSelf = self;
    [CaptchaCaptureService captureInWebView:webView
                               viewportRect:rect
                                 completion:^(NSImage *image, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || !image) {
            strongSelf.statusMessage = error.localizedDescription ?: @"截图失败";
            [strongSelf refreshPanelIfVisible];
            return;
        }
        strongSelf.lastPreviewImage = image;
        NSError *writeError = nil;
        NSURL *dir = [CaptchaSessionLog writeSessionWithDetection:primary
                                                            image:image
                                                             note:@"manual_capture"
                                                            error:&writeError];
        if (dir) {
            strongSelf.statusMessage = [NSString stringWithFormat:@"已保存会话 %@", dir.lastPathComponent];
            NSWindow *window = strongSelf.windowController.window;
            if (window) {
                [BrowserTransientToast showMessage:@"验证码截图已保存"
                                          inWindow:window
                                          duration:2.0];
            }
        } else {
            strongSelf.statusMessage = writeError.localizedDescription ?: @"保存失败";
        }
        [strongSelf refreshPanelIfVisible];
    }];
}

#pragma mark - Solve (CA-1)

- (void)solveNow {
    if (self.isSolving) {
        return;
    }
    if (![CaptchaAssistPreferences assistEnabled]) {
        self.statusMessage = @"请先启用验证码助手。";
        [self refreshPanelIfVisible];
        return;
    }

    CaptchaDetection *target = [CaptchaPipeline preferredSolvableDetectionFrom:self.currentDetections];
    if (!target) {
        self.statusMessage = @"当前页无可求解的 OCR/算术验证码。";
        [self refreshPanelIfVisible];
        return;
    }

    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        self.statusMessage = @"当前没有可操作的页面。";
        [self refreshPanelIfVisible];
        return;
    }

    self.isSolving = YES;
    self.statusMessage = @"正在求解 OCR / 算术…";
    [self refreshPanelIfVisible];

    __weak typeof(self) weakSelf = self;
    [CaptchaPipeline solveAllSolvableFrom:self.currentDetections inWebView:webView completion:^(BOOL success, NSString *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isSolving = NO;
        if (success) {
            strongSelf.statusMessage = message ?: @"求解成功";
            NSWindow *window = strongSelf.windowController.window;
            if (window) {
                [BrowserTransientToast showMessage:strongSelf.statusMessage inWindow:window duration:2.5];
            }
        } else {
            strongSelf.statusMessage = message.length > 0 ? message : (error.localizedDescription ?: @"求解失败");
        }
        [strongSelf refreshPanelIfVisible];
    }];
}

#pragma mark - Panel delegate

- (void)captchaAssistPanelDidRequestClose:(CaptchaAssistPanel *)panel {
    (void)panel;
    self.panelVisible = NO;
}

- (void)captchaAssistPanelDidRequestCapture:(CaptchaAssistPanel *)panel {
    (void)panel;
    [self captureNow];
}

- (void)captchaAssistPanelDidRequestClear:(CaptchaAssistPanel *)panel {
    (void)panel;
    self.currentDetections = @[];
    self.lastPreviewImage = nil;
    self.statusMessage = @"已清空当前检测。";
    [self refreshButtonAppearance];
    [self refreshPanelContent];
}

- (void)captchaAssistPanelDidRequestToggleEnabled:(CaptchaAssistPanel *)panel enabled:(BOOL)enabled {
    (void)panel;
    [CaptchaAssistPreferences setAssistEnabled:enabled];
    self.statusMessage = enabled
        ? @"已启用点亮与 OCR/算术求解。"
        : @"已关闭：仍检测但不点亮工具栏。";
    [self refreshButtonAppearance];
    [self refreshPanelContent];

    NSWindow *window = self.windowController.window;
    if (window) {
        NSString *msg = enabled ? @"验证码助手已开启" : @"验证码助手已关闭（不点亮）";
        [BrowserTransientToast showMessage:msg inWindow:window duration:2.0];
    }
}

- (void)captchaAssistPanelDidRequestRevealSessions:(CaptchaAssistPanel *)panel {
    (void)panel;
    NSURL *root = [CaptchaSessionLog sessionsRootDirectory];
    [[NSWorkspace sharedWorkspace] openURL:root];
}

- (void)captchaAssistPanelDidRequestSolve:(CaptchaAssistPanel *)panel {
    (void)panel;
    [self solveNow];
}

@end
