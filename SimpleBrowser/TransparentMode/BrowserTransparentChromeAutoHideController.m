#import "BrowserTransparentChromeAutoHideController.h"
#import "BrowserWindowController.h"

static const NSTimeInterval kDefaultHideDelay = 0.1;

@interface BrowserTransparentChromeAutoHideMouseRouter : NSObject
+ (instancetype)sharedRouter;
- (void)registerController:(BrowserTransparentChromeAutoHideController *)controller;
- (void)unregisterController:(BrowserTransparentChromeAutoHideController *)controller;
@end

@interface BrowserTransparentChromeAutoHideController (MouseRouting)
- (void)evaluatePointerAtScreenLocation:(NSPoint)screenLocation;
@end

@implementation BrowserTransparentChromeAutoHideMouseRouter {
    NSHashTable<BrowserTransparentChromeAutoHideController *> *_controllers;
    id _globalMonitor;
    id _localMonitor;
}

+ (instancetype)sharedRouter {
    static BrowserTransparentChromeAutoHideMouseRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrowserTransparentChromeAutoHideMouseRouter alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _controllers = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)registerController:(BrowserTransparentChromeAutoHideController *)controller {
    if (!controller) {
        return;
    }
    @synchronized (self) {
        [_controllers addObject:controller];
        [self ensureMonitorsLocked];
    }
}

- (void)unregisterController:(BrowserTransparentChromeAutoHideController *)controller {
    if (!controller) {
        return;
    }
    @synchronized (self) {
        [_controllers removeObject:controller];
        if (_controllers.count == 0) {
            [self tearDownMonitorsLocked];
        }
    }
}

- (void)ensureMonitorsLocked {
    if (_globalMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged;
    _globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask
                                                            handler:^(NSEvent *event) {
        (void)event;
        [weakSelf dispatchMouseLocation];
    }];
    _localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                          handler:^NSEvent *(NSEvent *event) {
        [weakSelf dispatchMouseLocation];
        return event;
    }];
}

- (void)tearDownMonitorsLocked {
    if (_globalMonitor) {
        [NSEvent removeMonitor:_globalMonitor];
        _globalMonitor = nil;
    }
    if (_localMonitor) {
        [NSEvent removeMonitor:_localMonitor];
        _localMonitor = nil;
    }
}

- (void)dispatchMouseLocation {
    NSPoint location = [NSEvent mouseLocation];
    NSArray<BrowserTransparentChromeAutoHideController *> *controllers = nil;
    @synchronized (self) {
        controllers = [_controllers.allObjects copy];
    }
    for (BrowserTransparentChromeAutoHideController *controller in controllers) {
        [controller evaluatePointerAtScreenLocation:location];
    }
}

@end

@interface BrowserTransparentChromeAutoHideController ()
@property (nonatomic, assign, readwrite) BOOL chromeRevealed;
@property (nonatomic, assign) BOOL lastPointerInside;
@property (nonatomic, assign) BOOL hasLastPointerInside;
@property (nonatomic, assign) BOOL hidePending;
@end

@implementation BrowserTransparentChromeAutoHideController

- (instancetype)init {
    self = [super init];
    if (self) {
        _hideDelay = kDefaultHideDelay;
        _chromeRevealed = YES;
    }
    return self;
}

- (void)dealloc {
    [self cancelPendingHide];
    [[BrowserTransparentChromeAutoHideMouseRouter sharedRouter] unregisterController:self];
}

- (nullable NSWindow *)targetWindow {
    return self.windowController.window;
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) {
        if (enabled) {
            [self reevaluatePointerNow];
        }
        return;
    }
    _enabled = enabled;
    [self cancelPendingHide];
    if (enabled) {
        self.hasLastPointerInside = NO;
        self.chromeRevealed = YES;
        [[BrowserTransparentChromeAutoHideMouseRouter sharedRouter] registerController:self];
        [self reevaluatePointerNow];
    } else {
        [[BrowserTransparentChromeAutoHideMouseRouter sharedRouter] unregisterController:self];
        self.hasLastPointerInside = NO;
        self.hidePending = NO;
        if (!self.chromeRevealed) {
            self.chromeRevealed = YES;
            [self notifyRevealChanged];
        } else {
            self.chromeRevealed = YES;
        }
    }
}

- (void)forceDisableAndReveal {
    [self setEnabled:NO];
}

- (void)reevaluatePointerNow {
    [self evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
}

- (void)cancelPendingHide {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(commitHideAfterDelay)
                                               object:nil];
    self.hidePending = NO;
}

- (void)notifyRevealChanged {
    void (^handler)(void) = self.chromeRevealDidChangeHandler;
    if (!handler) {
        return;
    }
    if ([NSThread isMainThread]) {
        handler();
    } else {
        dispatch_async(dispatch_get_main_queue(), handler);
    }
}

- (void)setChromeRevealedAndNotify:(BOOL)revealed {
    if (self.chromeRevealed == revealed) {
        return;
    }
    self.chromeRevealed = revealed;
    [self notifyRevealChanged];
}

- (void)commitHideAfterDelay {
    self.hidePending = NO;
    if (!self.enabled) {
        return;
    }
    NSWindow *window = [self targetWindow];
    if (!window) {
        return;
    }
    if (NSMouseInRect([NSEvent mouseLocation], window.frame, NO)) {
        return;
    }
    [self setChromeRevealedAndNotify:NO];
}

- (BOOL)isPointerInsideWindowFrame:(NSPoint)screenLocation {
    NSWindow *window = [self targetWindow];
    if (!window) {
        return NO;
    }
    return NSMouseInRect(screenLocation, window.frame, NO);
}

- (void)evaluatePointerAtScreenLocation:(NSPoint)screenLocation {
    if (!self.enabled) {
        return;
    }
    BOOL inside = [self isPointerInsideWindowFrame:screenLocation];
    if (self.hasLastPointerInside && self.lastPointerInside == inside) {
        return;
    }
    self.hasLastPointerInside = YES;
    self.lastPointerInside = inside;

    if (inside) {
        [self cancelPendingHide];
        [self setChromeRevealedAndNotify:YES];
        return;
    }

    // 移出：延迟再藏，避免擦边闪烁
    if (self.hideDelay <= 0.001) {
        [self setChromeRevealedAndNotify:NO];
        return;
    }
    if (self.hidePending) {
        return;
    }
    self.hidePending = YES;
    [self performSelector:@selector(commitHideAfterDelay)
               withObject:nil
               afterDelay:self.hideDelay];
}

@end
