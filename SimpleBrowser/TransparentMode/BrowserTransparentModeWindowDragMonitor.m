#import "BrowserTransparentModeWindowDragMonitor.h"
#import "BrowserWindowController.h"

typedef NS_ENUM(NSInteger, BrowserTransparentRightDragPhase) {
    BrowserTransparentRightDragPhaseIdle = 0,
    BrowserTransparentRightDragPhaseArmed,
    BrowserTransparentRightDragPhaseDragging,
};

/// 略大于触控板/鼠标抖动，避免「点右键」被误判成拖拽。
static const CGFloat kTransparentRightDragThreshold = 16.0;

@interface BrowserTransparentModeWindowDragMonitor ()
@property (nonatomic, strong, nullable) id localMonitor;
@property (nonatomic, assign) BrowserTransparentRightDragPhase phase;
@property (nonatomic, assign) NSPoint downScreenPoint;
@property (nonatomic, assign) NSPoint lastScreenPoint;
@property (nonatomic, assign) BOOL didMoveWindow;
@property (nonatomic, assign, readwrite) BOOL shouldSuppressContextMenu;
@end

@implementation BrowserTransparentModeWindowDragMonitor

- (void)dealloc {
    [self uninstall];
}

- (void)install {
    if (self.localMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    // 故意不监视 RightMouseDown/Up 的消费：监视 Down 即使用 return event
    // 也会导致 WKWebView 右键菜单经常无法弹出。只看 Dragged；Up 仅用于复位状态且始终放行。
    NSEventMask mask = NSEventMaskRightMouseDragged | NSEventMaskRightMouseUp;
    self.localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                              handler:^NSEvent * _Nullable(NSEvent *event) {
        return [weakSelf handleEvent:event];
    }];
}

- (void)uninstall {
    if (self.localMonitor) {
        [NSEvent removeMonitor:self.localMonitor];
        self.localMonitor = nil;
    }
    [self resetGestureState];
}

- (void)resetGestureState {
    self.phase = BrowserTransparentRightDragPhaseIdle;
    self.didMoveWindow = NO;
    self.shouldSuppressContextMenu = NO;
}

- (nullable NSEvent *)handleEvent:(NSEvent *)event {
    BrowserWindowController *wc = self.windowController;
    NSWindow *window = wc.window;
    if (!wc || !window || !wc.isTransparentModeEnabled) {
        return event;
    }
    if (event.window != window) {
        return event;
    }
    if (window.styleMask & NSWindowStyleMaskFullScreen) {
        return event;
    }

    switch (event.type) {
        case NSEventTypeRightMouseDragged:
            return [self handleRightMouseDragged:event inWindow:window];
        case NSEventTypeRightMouseUp:
            return [self handleRightMouseUp:event];
        default:
            return event;
    }
}

- (NSPoint)screenPointFromEvent:(NSEvent *)event inWindow:(NSWindow *)window {
    NSPoint locationInWindow = event.locationInWindow;
    NSRect rect = NSMakeRect(locationInWindow.x, locationInWindow.y, 0, 0);
    return [window convertRectToScreen:rect].origin;
}

- (BOOL)eventHitsContentArea:(NSEvent *)event inWindow:(NSWindow *)window {
    BrowserWindowController *wc = self.windowController;
    NSView *hitView = wc.webView;
    if (!hitView) {
        hitView = window.contentView;
    }
    if (!hitView) {
        return NO;
    }
    NSPoint locationInWindow = event.locationInWindow;
    NSPoint local = [hitView convertPoint:locationInWindow fromView:nil];
    return [hitView mouse:local inRect:hitView.bounds];
}

- (BOOL)isRightMouseButtonPressed {
    // bit1 = right button（与 NSEventPressedMouseButtons 一致）
    return ([NSEvent pressedMouseButtons] & (1 << 1)) != 0;
}

- (void)moveWindow:(NSWindow *)window byScreenDeltaX:(CGFloat)dx deltaY:(CGFloat)dy {
    if (dx == 0 && dy == 0) {
        return;
    }
    NSRect frame = window.frame;
    frame.origin.x += dx;
    frame.origin.y += dy;
    [window setFrame:frame display:YES];
    self.didMoveWindow = YES;
    self.shouldSuppressContextMenu = YES;
}

- (nullable NSEvent *)handleRightMouseDragged:(NSEvent *)event inWindow:(NSWindow *)window {
    if (![self isRightMouseButtonPressed]) {
        return event;
    }
    if (![self eventHitsContentArea:event inWindow:window] &&
        self.phase == BrowserTransparentRightDragPhaseIdle) {
        return event;
    }

    NSPoint screen = [self screenPointFromEvent:event inWindow:window];

    if (self.phase == BrowserTransparentRightDragPhaseIdle) {
        // 用首次 Dragged 作为起点（不拦截 Down，保证右键菜单正常）
        self.downScreenPoint = screen;
        self.lastScreenPoint = screen;
        self.didMoveWindow = NO;
        self.shouldSuppressContextMenu = NO;
        self.phase = BrowserTransparentRightDragPhaseArmed;
        return event;
    }

    if (self.phase == BrowserTransparentRightDragPhaseArmed) {
        CGFloat dx = screen.x - self.downScreenPoint.x;
        CGFloat dy = screen.y - self.downScreenPoint.y;
        if (hypot(dx, dy) < kTransparentRightDragThreshold) {
            return event;
        }
        self.phase = BrowserTransparentRightDragPhaseDragging;
        [self moveWindow:window byScreenDeltaX:dx deltaY:dy];
        self.lastScreenPoint = screen;
        return nil;
    }

    CGFloat dx = screen.x - self.lastScreenPoint.x;
    CGFloat dy = screen.y - self.lastScreenPoint.y;
    self.lastScreenPoint = screen;
    [self moveWindow:window byScreenDeltaX:dx deltaY:dy];
    return nil;
}

- (nullable NSEvent *)handleRightMouseUp:(NSEvent *)event {
    BOOL suppressMenu = self.didMoveWindow;
    self.phase = BrowserTransparentRightDragPhaseIdle;
    self.didMoveWindow = NO;

    if (suppressMenu) {
        self.shouldSuppressContextMenu = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (strongSelf.phase == BrowserTransparentRightDragPhaseIdle) {
                strongSelf.shouldSuppressContextMenu = NO;
            }
        });
    } else {
        self.shouldSuppressContextMenu = NO;
    }

    // 始终放行 Up，让 WebKit 能弹出右键菜单（拖拽场景由 willOpenMenu 取消）
    return event;
}

@end
