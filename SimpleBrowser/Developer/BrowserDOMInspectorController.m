#import "BrowserDOMInspectorController.h"
#import "BrowserDOMInspectorPanel.h"
#import "BrowserDOMInspectorScript.h"
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorHUD.h"
#import "BrowserTransientToast.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"

NSNotificationName const BrowserDOMInspectorStateDidChangeNotification = @"BrowserDOMInspectorStateDidChangeNotification";

@interface BrowserDOMInspectorController ()
@property (nonatomic, strong) BrowserDOMInspectorBridge *bridge;
@property (nonatomic, strong) BrowserDOMInspectorHUD *hud;
@property (nonatomic, strong, nullable) BrowserDOMInspectorPanel *panel;
@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, assign, getter=isPanelVisible) BOOL panelVisible;
@property (nonatomic, strong, nullable) NSLayoutConstraint *panelWidthConstraint;
@property (nonatomic, strong) NSNumber *reinjectionGeneration;
@end

@implementation BrowserDOMInspectorController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _bridge = [[BrowserDOMInspectorBridge alloc] init];
        _hud = [[BrowserDOMInspectorHUD alloc] init];

        __weak typeof(self) weakSelf = self;
        _bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
            [weakSelf handleSnapshotType:type payload:payload];
        };
        _bridge.onCancelled = ^{
            [weakSelf stop];
        };
        _hud.onCopySelector = ^(NSString *selector) {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            [pb clearContents];
            [pb setString:selector forType:NSPasteboardTypeString];
            [weakSelf showToast:@"已复制 CSS 选择器"];
        };

        _reinjectionGeneration = @0;
        _panel = [[BrowserDOMInspectorPanel alloc] initWithFrame:NSZeroRect];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        _panel.onCopy = ^(NSString *description) {
            [weakSelf showToast:[NSString stringWithFormat:@"已复制 %@", description]];
        };
        _panel.onRequestClose = ^{
            [weakSelf hidePanel];
        };

        BrowserTabController *tabController = self.windowController.tabController;
        if (tabController) {
            [tabController addObserver:self
                            forKeyPath:@"selectedTab"
                               options:NSKeyValueObservingOptionNew
                               context:NULL];
        }
    }
    return self;
}

- (void)dealloc {
    [_windowController.tabController removeObserver:self forKeyPath:@"selectedTab"];
    [_bridge stop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    (void)object; (void)change; (void)context;
    if (![keyPath isEqualToString:@"selectedTab"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self attachToCurrentWebView:self.windowController.webView];
}

#pragma mark - Configuration

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [BrowserDOMInspectorBridge installOnConfiguration:configuration];
}

#pragma mark - Toggle

- (IBAction)toggle:(id)sender {
    (void)sender;
    if (self.active) {
        [self stop];
    } else {
        [self start];
    }
    [self notifyStateChanged];
}

- (void)start {
    WKWebView *webView = self.windowController.webView;
    NSWindow *window = self.windowController.window;
    if (!webView || !window) {
        [self showToast:@"当前标签没有可检查的页面"];
        return;
    }
    if (![self.bridge startInWebView:webView]) {
        [self showToast:@"另一个拾取工具正在使用中（页面爬虫）"];
        return;
    }
    self.active = YES;
    [self.hud hide];
    [self showToast:@"DOM 探针已开启：移动鼠标查看，点击钉住"];
}

- (void)stop {
    if (!self.active) return;
    self.active = NO;
    [self.hud hide];
    [self hidePanel];
    [self.bridge stop];
    [self notifyStateChanged];
}

- (void)attachToCurrentWebView:(WKWebView *)webView {
    if (!self.active) return;
    if (!webView) {
        [self stop];
        return;
    }
    [self.hud hide];
    [self hidePanel];
    [self.bridge stop];
    if (![self.bridge startInWebView:webView]) {
        self.active = NO;
        [self notifyStateChanged];
        return;
    }
    // 页面可能已完成加载，iframe 也已就绪：再补几轮以覆盖延迟渲染。
    [self scheduleReinjectionForWebView:webView];
}

- (void)attachPanelToWindowIfNeeded {
    NSWindow *window = self.windowController.window;
    if (!window || !self.panel) return;
    if (self.panel.superview == window.contentView) return;
    [window.contentView addSubview:self.panel positioned:NSWindowAbove relativeTo:nil];
    self.panelWidthConstraint = [self.panel.widthAnchor constraintEqualToConstant:320.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
        [self.panel.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        self.panelWidthConstraint,
    ]];
    self.panel.hidden = YES;
}

- (void)showPanelWithSnapshot:(NSDictionary *)snapshot {
    NSWindow *window = self.windowController.window;
    if (!window) return;
    [self attachPanelToWindowIfNeeded];
    [self.panel showSnapshot:snapshot];
    self.panel.hidden = NO;
    self.panelVisible = YES;
    [self.panel setNeedsLayout:YES];
}

- (void)hidePanel {
    if (!self.panelVisible) return;
    [self.panel hidePanel];
    self.panel.hidden = YES;
    self.panelVisible = NO;
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView {
    if (!self.active || !webView) return;
    [self scheduleReinjectionForWebView:webView];
}
/// iframe 常在主文档之后才加载完成，因此分批重试若干次。
- (void)scheduleReinjectionForWebView:(WKWebView *)webView {
    self.reinjectionGeneration = @(self.reinjectionGeneration.unsignedIntegerValue + 1);
    NSUInteger generation = self.reinjectionGeneration.unsignedIntegerValue;
    static const NSTimeInterval delays[] = {0.0, 0.4, 1.0, 2.0, 4.0};
    for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self.active) return;
            if (generation != self.reinjectionGeneration.unsignedIntegerValue) return;
            if (webView != self.windowController.webView) return;
            [self.bridge reinjectIntoWebView:webView];
        });
    }
}

#pragma mark - Snapshot

- (void)handleSnapshotType:(NSString *)type payload:(NSDictionary *)payload {
    NSWindow *window = self.windowController.window;
    if (!window) return;

    if ([type isEqualToString:@"pinned"]) {
        [self.hud hide];
        [self showPanelWithSnapshot:payload];
        return;
    }

    WKWebView *webView = self.windowController.webView;
    if (!webView) return;
    NSRect geoInContent = [self rectInWindowForGeometry:payload[@"geometry"] webView:webView window:window];
    NSRect webViewInContent = [webView convertRect:webView.bounds toView:window.contentView];
    [self.hud showSnapshot:payload
          geometryInContent:geoInContent
            webViewInContent:webViewInContent
                   inWindow:window];
}

- (NSRect)rectInWindowForGeometry:(id)geometry
                           webView:(WKWebView *)webView
                           window:(NSWindow *)window {
    NSDictionary *geo = [geometry isKindOfClass:[NSDictionary class]] ? geometry : nil;
    CGFloat x = [geo[@"x"] doubleValue];
    CGFloat y = [geo[@"y"] doubleValue];
    CGFloat w = [geo[@"width"] doubleValue];
    CGFloat h = [geo[@"height"] doubleValue];
    NSRect webFrameInWindow = [webView convertRect:webView.bounds toView:window.contentView];
    // 页面坐标原点在左上，AppKit 在左下。
    CGFloat windowY = NSMaxY(webFrameInWindow) - (y + h);
    return NSMakeRect(NSMinX(webFrameInWindow) + x, windowY, w, h);
}

#pragma mark - Helpers

- (void)showToast:(NSString *)message {
    NSWindow *window = self.windowController.window;
    if (!window) return;
    NSString *text = message;
    [BrowserTransientToast showMessage:text inWindow:window duration:2.0];
}

- (void)notifyStateChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserDOMInspectorStateDidChangeNotification
                                                        object:self];
}

@end
