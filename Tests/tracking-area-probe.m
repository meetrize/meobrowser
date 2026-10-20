#import <Cocoa/Cocoa.h>

/// 验证 NSTrackingArea 在当前系统上的合法选项组合，避免运行时抛异常。
/// 注意：抛出与否与「是否已加入 window 无关」，init 阶段即校验。
static void probe(const char *label, NSTrackingAreaOptions options) {
    @autoreleasepool {
        NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        @try {
            NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:v.bounds
                                                                 options:options
                                                                   owner:v
                                                                userInfo:nil];
            [v addTrackingArea:area];
            printf("OK    %-48s 0x%lx\n", label, (unsigned long)options);
        } @catch (NSException *e) {
            printf("THROW %-48s 0x%lx  -> %s\n", label, (unsigned long)options,
                   e.reason.UTF8String);
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("--- tracking area option probes ---\n");
        probe("InVisibleRect", NSTrackingInVisibleRect);
        probe("MouseEnteredAndExited", NSTrackingMouseEnteredAndExited);
        probe("MouseMoved", NSTrackingMouseMoved);
        probe("MouseEnteredAndExited|InVisibleRect",
              NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect);
        probe("MouseMoved|InVisibleRect",
              NSTrackingMouseMoved | NSTrackingInVisibleRect);
        probe("ActiveAlways|InVisibleRect",
              NSTrackingActiveAlways | NSTrackingInVisibleRect);
        probe("ActiveInActiveApp|InVisibleRect",
              NSTrackingActiveInActiveApp | NSTrackingInVisibleRect);
        probe("MouseEnteredAndExited|MouseMoved",
              NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved);
        probe("EnterExitAndMouseMoved (0x3) with rect",
              NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
              NSTrackingActiveInActiveApp);
        probe("MouseEnteredAndExited|ActiveInActiveApp",
              NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp);
        probe("MouseEnteredAndExited|ActiveAlways",
              NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways);
        probe("MouseEnteredAndExited|InVisibleRect|ActiveAlways",
              NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect |
              NSTrackingActiveAlways);
    }
    return 0;
}
