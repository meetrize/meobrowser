#import "BrowserAfkModeController.h"
#import "BrowserWindowController.h"

@interface BrowserAfkModeController (MouseRouting)
- (void)evaluatePointerAtScreenLocation:(NSPoint)screenLocation;
@end

@interface BrowserAfkModeMouseRouter : NSObject
+ (instancetype)sharedRouter;
- (void)registerController:(BrowserAfkModeController *)controller;
- (void)unregisterController:(BrowserAfkModeController *)controller;
@end

@implementation BrowserAfkModeMouseRouter {
    NSHashTable<BrowserAfkModeController *> *_controllers;
    id _globalMonitor;
    id _localMonitor;
}

+ (instancetype)sharedRouter {
    static BrowserAfkModeMouseRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrowserAfkModeMouseRouter alloc] init];
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

- (void)registerController:(BrowserAfkModeController *)controller {
    if (!controller) {
        return;
    }
    @synchronized (self) {
        [_controllers addObject:controller];
        [self ensureMonitorsLocked];
    }
}

- (void)unregisterController:(BrowserAfkModeController *)controller {
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
    // global 不含本进程事件；本窗内移动也需覆盖
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
    NSArray<BrowserAfkModeController *> *controllers = nil;
    @synchronized (self) {
        controllers = [_controllers.allObjects copy];
    }
    for (BrowserAfkModeController *controller in controllers) {
        [controller evaluatePointerAtScreenLocation:location];
    }
}

@end

@interface BrowserAfkModeController ()
@property (nonatomic, assign, readwrite, getter=isConcealed) BOOL concealed;
@property (nonatomic, assign) BOOL hasAlphaSnapshot;
@property (nonatomic, assign) CGFloat snappedAlphaValue;
@property (nonatomic, assign) BOOL lastPointerInside;
@property (nonatomic, assign) BOOL hasLastPointerInside;
@end

@implementation BrowserAfkModeController

- (void)dealloc {
    [[BrowserAfkModeMouseRouter sharedRouter] unregisterController:self];
}

- (nullable NSWindow *)targetWindow {
    return self.windowController.window;
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) {
        if (enabled) {
            [self evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
        }
        return;
    }
    _enabled = enabled;
    if (enabled) {
        self.hasLastPointerInside = NO;
        [[BrowserAfkModeMouseRouter sharedRouter] registerController:self];
        [self evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
    } else {
        [[BrowserAfkModeMouseRouter sharedRouter] unregisterController:self];
        [self revealIfNeeded];
        self.hasLastPointerInside = NO;
        self.hasAlphaSnapshot = NO;
    }
}

- (void)forceDisableAndReveal {
    if (!self.enabled && !self.concealed) {
        return;
    }
    [self setEnabled:NO];
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
        [self revealIfNeeded];
    } else {
        [self concealIfNeeded];
    }
}

- (void)concealIfNeeded {
    if (self.concealed) {
        return;
    }
    NSWindow *window = [self targetWindow];
    if (!window) {
        return;
    }
    if (!self.hasAlphaSnapshot) {
        self.snappedAlphaValue = window.alphaValue;
        if (self.snappedAlphaValue < 0.01) {
            self.snappedAlphaValue = 1.0;
        }
        self.hasAlphaSnapshot = YES;
    }
    window.alphaValue = 0.0;
    self.concealed = YES;
}

- (void)revealIfNeeded {
    if (!self.concealed) {
        return;
    }
    NSWindow *window = [self targetWindow];
    if (window) {
        CGFloat alpha = self.hasAlphaSnapshot ? self.snappedAlphaValue : 1.0;
        window.alphaValue = alpha;
    }
    self.concealed = NO;
}

@end
