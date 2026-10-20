#import "BrowserDOMInspectorController.h"
#import "BrowserDOMInspectorScript.h"
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorHUD.h"
#import "BrowserTransientToast.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"
#import "BrowserTab.h"

NSNotificationName const BrowserDOMInspectorStateDidChangeNotification = @"BrowserDOMInspectorStateDidChangeNotification";

@interface BrowserDOMInspectorController ()
@property (nonatomic, strong) BrowserDOMInspectorBridge *bridge;
@property (nonatomic, strong) BrowserDOMInspectorHUD *hud;
@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, assign, getter=isBubblePinned) BOOL bubblePinned;
@property (nonatomic, strong) NSNumber *reinjectionGeneration;
/// 当前气泡所属标签；切走时隐藏，且只接受该标签 WebView 的快照。
@property (nonatomic, copy, nullable) NSUUID *hudBoundTabID;
/// 上次观察到的选中标签（用于在 tabControllerDidChange 中判断是否真的切了标签）。
@property (nonatomic, copy, nullable) NSUUID *observedSelectedTabID;
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
        _hud.onInteractiveLockFromCopy = ^{
            // 悬停点复制：冻结气泡为可交互，并尽量钉住当前悬停元素。
            weakSelf.bubblePinned = YES;
            [weakSelf.bridge pinLastHovered];
        };
        _hud.onCopiedSegment = ^(NSString *segment) {
            (void)segment;
            [weakSelf showToast:@"已复制"];
        };
        _hud.onClosePinned = ^{
            [weakSelf unpinBubbleFromHUD];
        };

        _reinjectionGeneration = @0;
        // 注意：此时 windowController.tabController 往往尚未创建，
        // 不能在这里做 KVO；改由 BrowserWindowController.tabControllerDidChange 回调。
    }
    return self;
}

- (void)dealloc {
    [_bridge stop];
}

- (BOOL)isPanelVisible {
    // 兼容旧 API：现表示「气泡已钉住」。
    return self.bubblePinned;
}

- (void)hideBubbleForTabSwitch {
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    [self.hud hide];
}

- (void)noteSelectedTabDidChange {
    NSUUID *currentID = self.windowController.tabController.selectedTab.tabID;
    // 气泡已绑到别的标签：无论 observed 如何，都立刻藏掉。
    if (self.hudBoundTabID != nil && currentID != nil &&
        ![self.hudBoundTabID isEqual:currentID]) {
        [self hideBubbleForTabSwitch];
    }
    if (self.observedSelectedTabID == currentID ||
        [self.observedSelectedTabID isEqual:currentID]) {
        return;
    }
    NSUUID *previousID = self.observedSelectedTabID;
    self.observedSelectedTabID = [currentID copy];
    // 首次同步选中态时不强制收起（窗口刚起来）；之后每次真正切标签都立刻隐藏。
    if (previousID == nil) {
        return;
    }
    [self hideBubbleForTabSwitch];
    if (self.active) {
        [self attachToCurrentWebView:self.windowController.webView];
    }
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
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    self.observedSelectedTabID = self.windowController.tabController.selectedTab.tabID;
    [self.hud hide];
    [self showToast:@"DOM 探针已开启：移动查看，点击钉住气泡"];
}

- (void)stop {
    if (!self.active) return;
    self.active = NO;
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    [self.hud hide];
    [self.bridge stop];
    [self notifyStateChanged];
}

- (void)unpinBubbleFromHUD {
    if (!self.active || !self.bubblePinned) return;
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    [self.hud hide];
    [self.bridge unpinBubble];
    [self showToast:@"已取消钉住：移动鼠标继续查看"];
}

- (void)attachToCurrentWebView:(WKWebView *)webView {
    if (!self.active) return;
    if (!webView) {
        [self stop];
        return;
    }
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    [self.hud hide];
    [self.bridge stop];
    if (![self.bridge startInWebView:webView]) {
        self.active = NO;
        [self notifyStateChanged];
        return;
    }
    [self scheduleReinjectionForWebView:webView];
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView {
    if (!self.active || !webView) return;
    // 仅处理当前选中标签的导航，避免后台标签刷新影响前景气泡。
    if (webView != self.windowController.webView) return;
    self.bubblePinned = NO;
    self.hudBoundTabID = nil;
    [self.hud hide];
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

- (BOOL)shouldAcceptSnapshotFromCurrentTab {
    if (!self.active) return NO;
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    WKWebView *selectedWV = tab.webView ?: self.windowController.webView;
    if (!selectedWV) return NO;
    if (self.bridge.boundWebView != selectedWV) return NO;
    if (self.hudBoundTabID && tab.tabID && ![self.hudBoundTabID isEqual:tab.tabID]) {
        return NO;
    }
    return YES;
}

- (void)handleSnapshotType:(NSString *)type payload:(NSDictionary *)payload {
    NSWindow *window = self.windowController.window;
    if (!window || !payload) return;
    if (![self shouldAcceptSnapshotFromCurrentTab]) return;

    WKWebView *webView = self.windowController.webView;
    if (!webView) return;
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    self.hudBoundTabID = tab.tabID;

    if ([type isEqualToString:@"pinned"]) {
        self.bubblePinned = YES;
        NSRect geoInContent = [self rectInWindowForGeometry:payload[@"geometry"] webView:webView window:window];
        NSRect webViewInContent = [webView convertRect:webView.bounds toView:window.contentView];
        [self.hud showSnapshot:payload
              geometryInContent:geoInContent
                webViewInContent:webViewInContent
                       inWindow:window
                         pinned:YES];
        [self showToast:@"气泡已钉住"];
        return;
    }

    // 气泡钉住后忽略后续 hover，避免跟着别的元素跑。
    if (self.bubblePinned) return;

    NSRect geoInContent = [self rectInWindowForGeometry:payload[@"geometry"] webView:webView window:window];
    NSRect webViewInContent = [webView convertRect:webView.bounds toView:window.contentView];
    [self.hud showSnapshot:payload
          geometryInContent:geoInContent
            webViewInContent:webViewInContent
                   inWindow:window
                     pinned:NO];
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
    CGFloat windowY = NSMaxY(webFrameInWindow) - (y + h);
    return NSMakeRect(NSMinX(webFrameInWindow) + x, windowY, w, h);
}

#pragma mark - Helpers

- (void)showToast:(NSString *)message {
    NSWindow *window = self.windowController.window;
    if (!window) return;
    [BrowserTransientToast showMessage:message inWindow:window duration:2.0];
}

- (void)notifyStateChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserDOMInspectorStateDidChangeNotification
                                                        object:self];
}

@end
