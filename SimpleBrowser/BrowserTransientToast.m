#import "BrowserTransientToast.h"

static NSString * const BrowserTransientToastID = @"meo.transient.toast";
static NSString * const BrowserPersistentToastID = @"meo.transient.toast.persistent";

@implementation BrowserTransientToast

+ (void)removeToastsWithIdentifier:(NSString *)identifier inParent:(NSView *)parent {
    for (NSView *sub in parent.subviews.copy) {
        if ([sub.identifier isEqualToString:identifier]) {
            [sub removeFromSuperview];
        }
    }
}

+ (NSView *)makeHUDWithMessage:(NSString *)message identifier:(NSString *)identifier {
    NSView *hud = [[NSView alloc] initWithFrame:NSZeroRect];
    hud.identifier = identifier;
    hud.wantsLayer = YES;
    hud.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.12 alpha:0.88] CGColor];
    hud.layer.cornerRadius = 10.0;
    hud.translatesAutoresizingMaskIntoConstraints = NO;
    hud.alphaValue = 0.0;

    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [hud addSubview:row];

    if ([identifier isEqualToString:BrowserPersistentToastID]) {
        NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        spinner.style = NSProgressIndicatorStyleSpinning;
        spinner.controlSize = NSControlSizeSmall;
        spinner.displayedWhenStopped = NO;
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [spinner startAnimation:nil];
        [row addArrangedSubview:spinner];
        [NSLayoutConstraint activateConstraints:@[
            [spinner.widthAnchor constraintEqualToConstant:14],
            [spinner.heightAnchor constraintEqualToConstant:14],
        ]];
    }

    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = [NSColor whiteColor];
    label.alignment = NSTextAlignmentLeft;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.preferredMaxLayoutWidth = 300;
    [row addArrangedSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:hud.topAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:hud.bottomAnchor constant:-10],
        [row.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-16],
    ]];
    return hud;
}

+ (void)presentHUD:(NSView *)hud inParent:(NSView *)parent {
    [parent addSubview:hud];
    [NSLayoutConstraint activateConstraints:@[
        [hud.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [hud.topAnchor constraintEqualToAnchor:parent.topAnchor constant:56],
        [hud.widthAnchor constraintLessThanOrEqualToConstant:380],
    ]];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        hud.animator.alphaValue = 1.0;
    } completionHandler:nil];
}

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

    // 短提示不影响常驻进度条；只替换其他短提示。
    [self removeToastsWithIdentifier:BrowserTransientToastID inParent:parent];

    NSView *hud = [self makeHUDWithMessage:message identifier:BrowserTransientToastID];
    [self presentHUD:hud inParent:parent];

    __weak NSView *weakHUD = hud;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSView *strongHUD = weakHUD;
        if (strongHUD == nil || strongHUD.superview == nil) {
            return;
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            strongHUD.animator.alphaValue = 0.0;
        } completionHandler:^{
            [strongHUD removeFromSuperview];
        }];
    });
}

+ (void)showPersistentMessage:(NSString *)message inWindow:(NSWindow *)window {
    if (message.length == 0 || !window) {
        return;
    }
    NSView *parent = window.contentView;
    if (!parent) {
        return;
    }
    [self removeToastsWithIdentifier:BrowserPersistentToastID inParent:parent];
    NSView *hud = [self makeHUDWithMessage:message identifier:BrowserPersistentToastID];
    [self presentHUD:hud inParent:parent];
}

+ (void)dismissPersistentMessageInWindow:(NSWindow *)window {
    NSView *parent = window.contentView;
    if (!parent) {
        return;
    }
    for (NSView *sub in parent.subviews.copy) {
        if (![sub.identifier isEqualToString:BrowserPersistentToastID]) {
            continue;
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            sub.animator.alphaValue = 0.0;
        } completionHandler:^{
            [sub removeFromSuperview];
        }];
    }
}

@end
