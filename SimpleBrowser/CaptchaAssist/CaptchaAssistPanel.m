#import "CaptchaAssistPanel.h"
#import "CaptchaDetection.h"

@interface CaptchaAssistPanel () <NSWindowDelegate>
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSImageView *previewView;
@property (nonatomic, strong) NSButton *enabledCheckbox;
@property (nonatomic, strong) NSButton *captureButton;
@property (nonatomic, strong) NSButton *solveButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSButton *revealButton;
@property (nonatomic, strong) id localMouseMonitor;
@end

@implementation CaptchaAssistPanel

- (instancetype)init {
    NSRect contentRect = NSMakeRect(0, 0, 340, 460);
    self = [super initWithContentRect:contentRect
                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.title = @"验证码助手";
        self.level = NSFloatingWindowLevel;
        self.hidesOnDeactivate = NO;
        self.releasedWhenClosed = NO;
        self.delegate = self;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.contentView;
    content.wantsLayer = YES;

    self.titleLabel = [self labelWithText:@"未检测到验证码" bold:YES size:13];
    self.statusLabel = [self labelWithText:@"助手默认关闭。开启后刷新页面以注入检测。" bold:NO size:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.detailLabel = [self labelWithText:@"" bold:NO size:11];
    self.detailLabel.textColor = [NSColor secondaryLabelColor];

    self.previewView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.previewView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.previewView.imageAlignment = NSImageAlignCenter;
    self.previewView.wantsLayer = YES;
    self.previewView.layer.cornerRadius = 6;
    self.previewView.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;

    self.enabledCheckbox = [NSButton checkboxWithTitle:@"启用助手（点亮工具栏；默认关）"
                                                target:self
                                                action:@selector(toggleEnabled:)];
    self.enabledCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    self.enabledCheckbox.font = [NSFont systemFontOfSize:12];

    self.captureButton = [NSButton buttonWithTitle:@"立即截图"
                                            target:self
                                            action:@selector(capture:)];
    self.solveButton = [NSButton buttonWithTitle:@"求解（OCR/算术）"
                                          target:self
                                          action:@selector(solve:)];
    self.clearButton = [NSButton buttonWithTitle:@"清空检测"
                                          target:self
                                          action:@selector(clear:)];
    self.revealButton = [NSButton buttonWithTitle:@"打开会话目录"
                                           target:self
                                           action:@selector(reveal:)];
    for (NSButton *b in @[self.captureButton, self.solveButton, self.clearButton, self.revealButton]) {
        b.bezelStyle = NSBezelStyleRounded;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        b.controlSize = NSControlSizeSmall;
    }

    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.captureButton, self.solveButton, self.clearButton, self.revealButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.titleLabel, self.statusLabel, self.enabledCheckbox,
        self.previewView, self.detailLabel, buttons
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.previewView.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28],
        [self.previewView.heightAnchor constraintEqualToConstant:200],
        [self.titleLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28],
        [self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28],
        [self.detailLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28],
        [self.enabledCheckbox.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28],
    ]];
}

- (NSTextField *)labelWithText:(NSString *)text bold:(BOOL)bold size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    label.maximumNumberOfLines = 4;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)updateWithDetections:(NSArray<CaptchaDetection *> *)detections
               previewImage:(NSImage *)image
                    enabled:(BOOL)enabled
                     status:(NSString *)status
                    solving:(BOOL)solving
               solveEnabled:(BOOL)solveEnabled {
    self.enabledCheckbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.captureButton.enabled = !solving;
    self.solveButton.enabled = solveEnabled && !solving;
    self.clearButton.enabled = !solving;
    self.revealButton.enabled = !solving;
    if (solving) {
        self.solveButton.title = @"求解中…";
    } else {
        self.solveButton.title = @"求解（OCR/算术）";
    }
    if (status.length > 0) {
        self.statusLabel.stringValue = status;
    }

    if (detections.count == 0) {
        self.titleLabel.stringValue = @"未检测到验证码";
        self.detailLabel.stringValue = enabled
            ? @"打开含验证码的页面，或加载 captcha-assist-test.html。"
            : @"页面检测仍运行；勾选上方开关后工具栏才会点亮。";
    } else {
        CaptchaDetection *first = detections.firstObject;
        self.titleLabel.stringValue = [NSString stringWithFormat:@"检测到 %lu 项", (unsigned long)detections.count];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (CaptchaDetection *d in detections) {
            [lines addObject:[NSString stringWithFormat:@"• %@（置信 %.0f%%）",
                              [d summaryLabel], d.confidence * 100.0]];
        }
        if (first.pageURL.length > 0) {
            [lines addObject:[NSString stringWithFormat:@"页：%@", first.pageURL]];
        }
        self.detailLabel.stringValue = [lines componentsJoinedByString:@"\n"];
        if (status.length == 0) {
            self.statusLabel.stringValue = @"CA-1：支持 OCR / 算术自动填入。";
        }
    }

    self.previewView.image = image;
}

- (void)presentAnchoredToRect:(NSRect)anchorRectOnScreen ofWindow:(NSWindow *)ownerWindow {
    NSRect panelFrame = self.frame;
    CGFloat x = NSMidX(anchorRectOnScreen) - NSWidth(panelFrame) / 2.0;
    CGFloat y = NSMinY(anchorRectOnScreen) - NSHeight(panelFrame) - 8;
    NSScreen *screen = ownerWindow.screen ?: [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    if (x < NSMinX(visible) + 8) {
        x = NSMinX(visible) + 8;
    }
    if (x + NSWidth(panelFrame) > NSMaxX(visible) - 8) {
        x = NSMaxX(visible) - NSWidth(panelFrame) - 8;
    }
    if (y < NSMinY(visible) + 8) {
        y = NSMaxY(anchorRectOnScreen) + 8;
    }
    [self setFrameOrigin:NSMakePoint(x, y)];
    [self makeKeyAndOrderFront:nil];
    [self installDismissMonitor];
}

- (void)dismissPanel {
    [self removeDismissMonitor];
    [self orderOut:nil];
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestClose:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestClose:self];
    }
}

- (void)installDismissMonitor {
    if (self.localMouseMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.localMouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                                   handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.isVisible) {
            return event;
        }
        NSPoint screenPoint = [NSEvent mouseLocation];
        if (NSPointInRect(screenPoint, strongSelf.frame)) {
            return event;
        }
        if (!NSEqualRects(strongSelf.dismissExclusionRectOnScreen, NSZeroRect) &&
            NSPointInRect(screenPoint, strongSelf.dismissExclusionRectOnScreen)) {
            return event;
        }
        [strongSelf dismissPanel];
        return event;
    }];
}

- (void)removeDismissMonitor {
    if (self.localMouseMonitor) {
        [NSEvent removeMonitor:self.localMouseMonitor];
        self.localMouseMonitor = nil;
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [self removeDismissMonitor];
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestClose:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestClose:self];
    }
}

- (void)toggleEnabled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestToggleEnabled:enabled:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestToggleEnabled:self enabled:on];
    }
}

- (void)capture:(id)sender {
    (void)sender;
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestCapture:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestCapture:self];
    }
}

- (void)clear:(id)sender {
    (void)sender;
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestClear:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestClear:self];
    }
}

- (void)reveal:(id)sender {
    (void)sender;
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestRevealSessions:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestRevealSessions:self];
    }
}

- (void)solve:(id)sender {
    (void)sender;
    if ([self.panelDelegate respondsToSelector:@selector(captchaAssistPanelDidRequestSolve:)]) {
        [self.panelDelegate captchaAssistPanelDidRequestSolve:self];
    }
}

- (void)dealloc {
    [self removeDismissMonitor];
}

@end
