#import "BrowserAutoScrollController.h"
#import "BrowserAutoScrollPreferences.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"
#import "BrowserTab.h"

@interface BrowserAutoScrollController ()
@property (nonatomic, strong, nullable) NSTimer *tickTimer;
@property (nonatomic, strong, nullable) id scrollWheelMonitor;
@property (nonatomic, strong, nullable) id mouseMoveLocalMonitor;
@property (nonatomic, strong, nullable) id mouseMoveGlobalMonitor;
@property (nonatomic, assign) NSTimeInterval lastTickTime;
@property (nonatomic, assign) BOOL pausedForPointerInside;
@property (nonatomic, assign) CGFloat pendingScrollPx;
@end

@implementation BrowserAutoScrollController

- (void)dealloc {
    [self tearDownTimerAndMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencesDidChange:)
                                                     name:BrowserAutoScrollPreferencesDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)preferencesDidChange:(NSNotification *)note {
    (void)note;
    if (self.enabled) {
        [self applySpeedFromPreferences];
    }
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) {
        return;
    }
    _enabled = enabled;
    if (enabled) {
        [self startTicking];
    } else {
        self.pausedForPointerInside = NO;
        self.pendingScrollPx = 0;
        [self tearDownTimerAndMonitor];
    }
}

- (void)applySpeedFromPreferences {
    // 速度在每次 tick 读取 preferences，无需额外状态
}

- (void)stopBecauseInterrupted {
    if (!self.enabled) {
        return;
    }
    _enabled = NO;
    self.pausedForPointerInside = NO;
    self.pendingScrollPx = 0;
    [self tearDownTimerAndMonitor];
    if (self.didDisableHandler) {
        self.didDisableHandler();
    }
}

- (void)stopBecauseReachedBottom {
    [self stopBecauseInterrupted];
}

- (nullable WKWebView *)activeWebView {
    BrowserTab *tab = self.windowController.tabController.selectedTab;
    if (!tab || tab.isNewTabPage) {
        return nil;
    }
    return tab.webView;
}

- (nullable NSWindow *)targetWindow {
    return self.windowController.window;
}

- (BOOL)isPointerInsideTargetWindowAtScreenLocation:(NSPoint)screenLocation {
    NSWindow *window = [self targetWindow];
    if (!window || !window.isVisible) {
        return NO;
    }
    return NSPointInRect(screenLocation, window.frame);
}

- (void)evaluatePointerAtScreenLocation:(NSPoint)screenLocation {
    if (!self.enabled) {
        return;
    }
    BOOL inside = [self isPointerInsideTargetWindowAtScreenLocation:screenLocation];
    if (inside == self.pausedForPointerInside) {
        return;
    }
    self.pausedForPointerInside = inside;
    if (inside) {
        // 入窗暂停：清零累积，恢复时从干净状态开始
        self.pendingScrollPx = 0;
    } else {
        // 移出后恢复：重置时间戳，避免一次大步长跳动
        self.pendingScrollPx = 0;
        self.lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    }
}

- (void)startTicking {
    [self tearDownTimerAndMonitor];
    self.lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    self.pendingScrollPx = 0;
    self.pausedForPointerInside = [self isPointerInsideTargetWindowAtScreenLocation:[NSEvent mouseLocation]];

    __weak typeof(self) weakSelf = self;
    self.tickTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                            repeats:YES
                                              block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf tick];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.tickTimer forMode:NSRunLoopCommonModes];

    self.scrollWheelMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                              handler:^NSEvent *(NSEvent *event) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.enabled) {
                return event;
            }
            if (event.window == strongSelf.windowController.window) {
                [strongSelf stopBecauseInterrupted];
            }
            return event;
        }];

    NSEventMask moveMask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged
        | NSEventMaskOtherMouseDragged;
    self.mouseMoveLocalMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:moveMask
                                              handler:^NSEvent *(NSEvent *event) {
            (void)event;
            [weakSelf evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
            return event;
        }];
    // 全局：指针从窗外移入/移出本窗时本进程不一定收到 local mouseMoved
    self.mouseMoveGlobalMonitor =
        [NSEvent addGlobalMonitorForEventsMatchingMask:moveMask
                                               handler:^(NSEvent *event) {
            (void)event;
            [weakSelf evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
        }];
}

- (void)tearDownTimerAndMonitor {
    [self.tickTimer invalidate];
    self.tickTimer = nil;
    if (self.scrollWheelMonitor) {
        [NSEvent removeMonitor:self.scrollWheelMonitor];
        self.scrollWheelMonitor = nil;
    }
    if (self.mouseMoveLocalMonitor) {
        [NSEvent removeMonitor:self.mouseMoveLocalMonitor];
        self.mouseMoveLocalMonitor = nil;
    }
    if (self.mouseMoveGlobalMonitor) {
        [NSEvent removeMonitor:self.mouseMoveGlobalMonitor];
        self.mouseMoveGlobalMonitor = nil;
    }
}

- (void)tick {
    if (!self.enabled || self.pausedForPointerInside) {
        return;
    }
    WKWebView *webView = [self activeWebView];
    if (!webView) {
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval dt = now - self.lastTickTime;
    self.lastTickTime = now;
    if (dt <= 0 || dt > 1.0) {
        dt = 1.0 / 30.0;
    }

    CGFloat speed = [BrowserAutoScrollPreferences speedPxPerSec];
    self.pendingScrollPx += speed * (CGFloat)dt;
    if (self.pendingScrollPx < 1.0) {
        return;
    }
    CGFloat step = floor(self.pendingScrollPx);
    self.pendingScrollPx -= step;

    NSString *script = [NSString stringWithFormat:
                        @"(function(){"
                        @"var e=document.scrollingElement||document.documentElement||document.body;"
                        @"if(!e)return {ok:0};"
                        @"var max=Math.max(0,(e.scrollHeight|0)-(e.clientHeight|0));"
                        @"var before=e.scrollTop||0;"
                        @"if(max<=1)return {ok:1,atBottom:1,max:max};"
                        @"e.scrollTop=before+(%f);"
                        @"var after=e.scrollTop||0;"
                        @"var atBottom=(after>=max-1)||(after<=before+0.5&&before>=max-2);"
                        @"return {ok:1,atBottom:atBottom?1:0,max:max,before:before,after:after};"
                        @"})()",
                        (double)step];

    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.enabled || strongSelf.pausedForPointerInside) {
            return;
        }
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSDictionary *dict = (NSDictionary *)result;
        if ([dict[@"atBottom"] respondsToSelector:@selector(boolValue)] && [dict[@"atBottom"] boolValue]) {
            [strongSelf stopBecauseReachedBottom];
        }
    }];
}

@end
