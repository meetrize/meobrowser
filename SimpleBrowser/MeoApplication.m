#import "MeoApplication.h"
#import "BrowserUserActivityMonitor.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation MeoApplication

+ (void)activateFrontWindowOnlyPreferring:(NSWindow *)window {
    NSWindow *target = window;
    if (!target) {
        target = NSApp.keyWindow ?: NSApp.mainWindow;
    }
    if (!target) {
        for (NSWindow *candidate in NSApp.orderedWindows) {
            if (candidate.isVisible && !candidate.isMiniaturized && candidate.canBecomeKeyWindow) {
                target = candidate;
                break;
            }
        }
    }
    if (target) {
        // 只调整本进程内窗口序，勿用 makeKeyAndOrderFront（会按「全部窗口」激活）。
        [target orderFront:nil];
    }

    ProcessSerialNumber psn = {0, kCurrentProcess};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SetFrontProcessWithOptions(&psn,
                               kSetFrontProcessFrontWindowOnly | kSetFrontProcessCausedByUser);
#pragma clang diagnostic pop

    if (target && target.canBecomeKeyWindow) {
        [target makeKeyWindow];
    }
}

- (void)sendEvent:(NSEvent *)event {
    NSEventType type = event.type;
    // 用户真实输入 → 延长「活跃期」，期间不做预算休眠。
    switch (type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
        case NSEventTypeKeyDown:
        case NSEventTypeScrollWheel:
        case NSEventTypeMagnify:
        case NSEventTypeSmartMagnify:
        case NSEventTypeSwipe:
        case NSEventTypePressure:
            [[BrowserUserActivityMonitor sharedMonitor] noteUserInput];
            break;
        default:
            break;
    }

    if (!self.active &&
        (type == NSEventTypeLeftMouseDown ||
         type == NSEventTypeRightMouseDown ||
         type == NSEventTypeOtherMouseDown)) {
        NSWindow *window = event.window;
        if (!window && event.windowNumber != 0) {
            window = [self windowWithWindowNumber:event.windowNumber];
        }
        // 点到可见窗时：仅前置该窗再激活，避免其余浏览器窗一并抬起。
        if (window && window.isVisible && !window.isMiniaturized) {
            [MeoApplication activateFrontWindowOnlyPreferring:window];
        }
    }
    [super sendEvent:event];
}

@end
