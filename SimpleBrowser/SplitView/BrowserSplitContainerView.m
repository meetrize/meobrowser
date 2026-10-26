#import "BrowserSplitContainerView.h"
#import "BrowserPaneView.h"
#import "BrowserWebView.h"
#import <WebKit/WebKit.h>
#import "BrowserThinDivider.h"

static const CGFloat kMinPane = 120.0;

@implementation BrowserSplitContainerView {
    NSMutableArray<BrowserPaneView *> *_panes;
    NSMutableArray<BrowserThinDivider *> *_dividers;
    void (^_pendingActiveHandler)(NSInteger);
    BOOL _layoutScheduled;
    id _clickToFocusMonitor;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (self) {
        _layoutID = BrowserSplitLayoutSingle;
        _weights = [BrowserSplitLayout defaultWeightsForLayout:_layoutID];
        _panes = [NSMutableArray array];
        _dividers = [NSMutableArray array];
        _activePaneIndex = 0;
        [self applyLayout:_layoutID weights:_weights urls:nil];
        [self installClickToFocusMonitor];
    }
    return self;
}

- (void)dealloc {
    if (_clickToFocusMonitor) {
        [NSEvent removeMonitor:_clickToFocusMonitor];
        _clickToFocusMonitor = nil;
    }
}

// 点击切聚焦:WKWebView 会吃掉栏内的点击,pane 的 mouseDown 永远收不到,
// 只能在事件分发前按坐标命中 pane。点分隔线不切换。
- (void)installClickToFocusMonitor {
    if (_clickToFocusMonitor) return;
    __weak typeof(self) weak = self;
    _clickToFocusMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weak) strong = weak;
        if (strong && !strong.hidden && event.window == strong.window && NSPointInRect([strong convertPoint:event.locationInWindow fromView:nil], strong.bounds)) {
            NSPoint p = [strong convertPoint:event.locationInWindow fromView:nil];
            for (BrowserThinDivider *d in strong->_dividers) {
                if (NSPointInRect(p, d.frame)) return event;
            }
            for (BrowserPaneView *pane in strong->_panes) {
                if (NSPointInRect(p, pane.frame) && pane.paneIndex != strong->_activePaneIndex) {
                    [strong focusPaneAtIndex:pane.paneIndex];
                    break;
                }
            }
        }
        return event;
    }];
}

- (NSArray<BrowserPaneView *> *)panes { return [_panes copy]; }

- (void)applyLayout:(BrowserSplitLayoutID)layout weights:(NSArray<NSNumber *> *)weights urls:(NSArray *)urls {
    _layoutID = layout;
    NSArray *w = weights.count ? weights : [BrowserSplitLayout defaultWeightsForLayout:layout];
    _weights = [w copy];
    for (NSView *v in _panes) [v removeFromSuperview];
    for (NSView *v in _dividers) [v removeFromSuperview];
    [_panes removeAllObjects]; [_dividers removeAllObjects];
    NSInteger n = [BrowserSplitLayout paneCountForLayout:layout];
    for (NSInteger i = 0; i < n; i++) {
        BrowserPaneView *p = [[BrowserPaneView alloc] initWithIndex:i];
        // 手工 layout:用 autoresizing,初始 frame 给真实值,避免零尺寸导致内部约束被系统打断
        p.translatesAutoresizingMaskIntoConstraints = YES;
        p.autoresizingMask = NSViewNotSizable;
        p.frame = [BrowserSplitLayout frameForPaneAtIndex:i ofLayout:layout weights:_weights inBounds:self.bounds];
        p.active = (i == _activePaneIndex);
        // click-to-focus 由 BrowserPaneView.mouseDown 直接处理(手势会吞地址栏点击,导致无法输入)
        p.becameActiveHandler = nil;
        if (_pendingActiveHandler) p.becameActiveHandler = _pendingActiveHandler;
        [self addSubview:p];
        [_panes addObject:p];
        id u = (i < (NSInteger)urls.count) ? urls[i] : nil;
        NSURL *url = [u isKindOfClass:[NSURL class]] ? u : nil;
        [p setPlaceholderURL:url];
    }
    // divider 数量:线性布局 n-1;quad 1竖+1横(简化:只支持整体比例2个weights);nine 2+2(简化同理)
    NSInteger divCount = 0;
    BOOL vertical = YES;
    if (layout == BrowserSplitLayoutLR || layout == BrowserSplitLayoutUD ||
        layout == BrowserSplitLayoutLCR || layout == BrowserSplitLayoutUMD) {
        divCount = n - 1; vertical = [BrowserSplitLayout isHorizontalSplit:layout];
    } else if (layout == BrowserSplitLayoutQuad) { divCount = 2; }
    else if (layout == BrowserSplitLayoutNine) { divCount = 4; }
    for (NSInteger i = 0; i < divCount; i++) {
        BrowserThinDivider *d = [[BrowserThinDivider alloc] initWithFrame:NSZeroRect];
        d.translatesAutoresizingMaskIntoConstraints = YES;
        if (layout == BrowserSplitLayoutQuad) d.vertical = (i == 0);
        else if (layout == BrowserSplitLayoutNine) d.vertical = (i < 2);
        else d.vertical = vertical;
        NSInteger tag = i;
        __weak typeof(self) weak = self;
        d.dragDeltaHandler = ^(CGFloat delta) { [weak handleDividerDrag:tag delta:delta]; };
        d.dragDidEndHandler = ^{ if (weak.weightsDidChangeHandler) weak.weightsDidChangeHandler(weak.weights); };
        [self addSubview:d];
        [_dividers addObject:d];
    }
    [self setNeedsLayout:YES];
}

// click-to-focus 由 installClickToFocusMonitor 按坐标命中(见该方法)。

- (void)focusPaneAtIndex:(NSInteger)index {
    _activePaneIndex = index;
    for (BrowserPaneView *p in _panes) {
        // setActive 只改边框;用 setActiveAndReveal 让自动隐藏模式同步显隐地址栏
        if ([p respondsToSelector:@selector(setActiveAndReveal:)]) [p setActiveAndReveal:(p.paneIndex == index)];
        else p.active = (p.paneIndex == index);
    }
}

// 拖拽节流:一帧最多一次 layout,避免 mouseDragged 高频触发 9 个 webView 全量重排
- (void)scheduleCoalescedLayout {
    if (_layoutScheduled) return;
    _layoutScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_layoutScheduled = NO;
        [self setNeedsLayout:YES];
        [self layoutSubtreeIfNeeded];
    });
}
- (void)handleDividerDrag:(NSInteger)tag delta:(CGFloat)delta {
    NSMutableArray<NSNumber *> *w = [_weights mutableCopy];
    CGFloat totalPx = self.verticalSplit ? NSWidth(self.bounds) : NSHeight(self.bounds);
    // quad/nine 简化:weights[0]=横向比例,weights[1]=纵向比例
    if (_layoutID == BrowserSplitLayoutQuad || _layoutID == BrowserSplitLayoutNine) {
        if (w.count < 2) w = [@[@0.5, @0.5] mutableCopy];
        BOOL isVert = _dividers[tag].vertical;
        NSInteger wi = isVert ? 0 : 1;
        double dw = delta / fmax(totalPx, 1);
        // weights[1] 即上半高占比 h0(见 frameForPane:rowH[0]=h*(1-h0) 为上半)。
        // delta 定义往下为正,往下拖上半变大,故直接加,无需取负。
        double nv = fmin(fmax(((NSNumber *)w[wi]).doubleValue + dw, 0.15), 0.85);
        w[wi] = @(nv);
        _weights = [w copy];
        [self scheduleCoalescedLayout];
        return;
    }
    if (totalPx <= 0 || w.count < 2) return;
    NSInteger left = tag, right = tag + 1;
    if (right >= (NSInteger)w.count) return;
    double total = 0; for (NSNumber *n in w) total += n.doubleValue;
    double dw = delta / totalPx * total;
    // 最小 120pt 约束
    double leftPx = ((NSNumber *)w[left]).doubleValue / total * totalPx + dw * totalPx / total * 0 + delta;
    double rightPx = ((NSNumber *)w[right]).doubleValue / total * totalPx - delta;
    // NOTE: 简化按像素钳制
    if (leftPx < kMinPane || rightPx < kMinPane) return;
    double lv = ((NSNumber *)w[left]).doubleValue + dw, rv = ((NSNumber *)w[right]).doubleValue - dw;
    if (lv <= 0.05 || rv <= 0.05) return;
    w[left] = @(lv); w[right] = @(rv);
    _weights = [w copy];
    [self scheduleCoalescedLayout];
}

- (void)bindWebViewsWithConfiguration:(WKWebViewConfiguration *)config
                   navigationDelegate:(id<WKNavigationDelegate>)navDelegate
                           uiDelegate:(id<WKUIDelegate>)uiDelegate
                      openURLHandler:(void (^)(NSInteger, NSURL *))handler
                     activeHandler:(void (^)(NSInteger))activeHandler {
    for (BrowserPaneView *pane in _panes) {
        if (!pane.webView) {
            // 用 BrowserWebView(而非原生 WKWebView):分栏右键菜单(本栏缩放/查看源码/重新载入框架等)靠它的 willOpenMenu 注入
            WKWebView *wv = [[BrowserWebView alloc] initWithFrame:NSZeroRect configuration:config];
            wv.navigationDelegate = navDelegate;
            wv.UIDelegate = uiDelegate;
            wv.allowsBackForwardNavigationGestures = YES;
            [pane attachWebView:wv];
        }
        pane.openURLHandler = handler;
        pane.becameActiveHandler = activeHandler;
    }
    _pendingActiveHandler = [activeHandler copy];
    return;
}

- (void)loadURLs:(NSArray *)urls {
    for (NSInteger i = 0; i < (NSInteger)_panes.count; i++) {
        id u = (i < (NSInteger)urls.count) ? urls[i] : nil;
        NSURL *url = [u isKindOfClass:[NSURL class]] ? u : nil;
        if (url) [((BrowserPaneView *)_panes[i]) loadURL:url];
    }
}
- (void)setChromeMode:(NSInteger)mode forPane:(NSInteger)paneIndex {
    for (BrowserPaneView *pane in _panes) {
        if (paneIndex < 0 || pane.paneIndex == paneIndex) pane.chromeMode = (int)mode;
    }
}
- (BOOL)verticalSplit {
    if (_layoutID == BrowserSplitLayoutLR || _layoutID == BrowserSplitLayoutLCR) return YES;
    return NO;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    NSInteger n = _panes.count;
    for (NSInteger i = 0; i < n; i++) {
        _panes[i].frame = [BrowserSplitLayout frameForPaneAtIndex:i ofLayout:_layoutID weights:_weights inBounds:b];
    }
    // divider 摆位:取相邻 pane 边界中线,hit 宽 7
    for (BrowserThinDivider *d in _dividers) {
        NSInteger tag = [_dividers indexOfObject:d];
        if (_layoutID == BrowserSplitLayoutQuad) {
            if (d.vertical) {
                CGFloat x = NSMinX(b) + NSWidth(b) * ( _weights.count > 0 ? _weights[0].doubleValue : 0.5);
                d.frame = NSMakeRect(x - 3.5, NSMinY(b), 7, NSHeight(b));
            } else {
                CGFloat y = NSMinY(b) + NSHeight(b) * (1 - (_weights.count > 1 ? _weights[1].doubleValue : 0.5));
                // NOTE: quad weights[1] 为上半高?Layout中 h0=weights[1]为上半?保持一致:上半 h0
                // frameForPane 用 h0 作上半高,下半分界 y = minY + h*(1-h0)
                d.frame = NSMakeRect(NSMinX(b), y - 3.5, NSWidth(b), 7);
            }
            continue;
        }
        if (_layoutID == BrowserSplitLayoutNine) {
            // 简化:weights[0]=列宽比例,weights[1]=行高比例
            double cw = _weights.count > 0 ? _weights[0].doubleValue : 1.0/3;
            double ch = _weights.count > 1 ? _weights[1].doubleValue : 1.0/3;
            if (d.vertical) {
                NSInteger col = (tag == 0) ? 0 : 1;
                CGFloat x = NSMinX(b) + NSWidth(b) * cw * (col + 1);
                d.frame = NSMakeRect(x - 3.5, NSMinY(b), 7, NSHeight(b));
            } else {
                NSInteger row = (tag == 2) ? 0 : 1; // 上分界/下分界
                CGFloat h = NSHeight(b);
                CGFloat y = (row == 0) ? NSMinY(b) + h * (1 - ch) : NSMinY(b) + h * (1 - 2 * ch);
                d.frame = NSMakeRect(NSMinX(b), y - 3.5, NSWidth(b), 7);
            }
            continue;
        }
        BOOL vert = d.vertical;
        // 线性:前 tag+1 个 pane 累计占比
        double total = 0; for (NSNumber *x in _weights) total += x.doubleValue;
        double acc = 0; for (NSInteger i = 0; i <= tag && i < (NSInteger)_weights.count; i++) acc += _weights[i].doubleValue;
        double frac = total > 0 ? acc / total : 0;
        if (vert) {
            CGFloat x = NSMinX(b) + NSWidth(b) * frac;
            d.frame = NSMakeRect(x - 3.5, NSMinY(b), 7, NSHeight(b));
        } else {
            CGFloat y = NSMinY(b) + NSHeight(b) * (1 - frac);
            d.frame = NSMakeRect(NSMinX(b), y - 3.5, NSWidth(b), 7);
        }
    }
}

@end
