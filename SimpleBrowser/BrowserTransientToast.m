#import "BrowserTransientToast.h"

@implementation BrowserTransientToast

+ (void)showMessage:(NSString *)message
           inWindow:(NSWindow *)window
           duration:(NSTimeInterval)duration {
    if (message.length == 0 || !window) {
        return;
    }
    if (duration <= 0) {
        duration = 2.0;
    }

    NSView *parent = window.contentView;
    if (!parent) {
        return;
    }

    // 移除上一条，避免叠多层
    for (NSView *sub in parent.subviews.copy) {
        if ([sub.identifier isEqualToString:@"meo.transient.toast"]) {
            [sub removeFromSuperview];
        }
    }

    NSView *hud = [[NSView alloc] initWithFrame:NSZeroRect];
    hud.identifier = @"meo.transient.toast";
    hud.wantsLayer = YES;
    hud.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.12 alpha:0.88] CGColor];
    hud.layer.cornerRadius = 10.0;
    hud.translatesAutoresizingMaskIntoConstraints = NO;
    hud.alphaValue = 0.0;

    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = [NSColor whiteColor];
    label.alignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.preferredMaxLayoutWidth = 320;
    [hud addSubview:label];

    [parent addSubview:hud];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:hud.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:hud.bottomAnchor constant:-10],
        [label.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-16],
        [hud.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [hud.topAnchor constraintEqualToAnchor:parent.topAnchor constant:56],
        [hud.widthAnchor constraintLessThanOrEqualToConstant:360],
    ]];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        hud.animator.alphaValue = 1.0;
    } completionHandler:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.25;
                hud.animator.alphaValue = 0.0;
            } completionHandler:^{
                [hud removeFromSuperview];
            }];
        });
    }];
}

@end
