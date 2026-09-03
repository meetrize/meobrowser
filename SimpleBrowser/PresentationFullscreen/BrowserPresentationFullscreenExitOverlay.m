#import "BrowserPresentationFullscreenExitOverlay.h"
#import "BrowserWindowController.h"

/// 顶边热区至少覆盖系统菜单栏高度。
static const CGFloat kMinTopEdgeTriggerHeight = 28.0;
/// 菜单栏下方再留一点空隙，避免贴边。
static const CGFloat kBelowMenuBarGap = 8.0;
/// 与系统菜单栏下滑接近的时长。
static const NSTimeInterval kRevealAnimationDuration = 0.22;
static const NSTimeInterval kHideAnimationDuration = 0.18;
static const NSTimeInterval kDefaultHideDelay = 2.0;

@interface BrowserPresentationFullscreenExitButtonView : NSView
@property (nonatomic, copy, nullable) void (^mouseHoverDidChange)(BOOL hovering);
@property (nonatomic, copy, nullable) void (^clickHandler)(void);
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, assign) BOOL hovering;
@end

@implementation BrowserPresentationFullscreenExitButtonView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        [self applyAppearance];

        _titleLabel = [NSTextField labelWithString:@"退出全屏"];
        _titleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
        _titleLabel.textColor = [NSColor whiteColor];
        _titleLabel.alignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
        ]];

        NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                            options:(NSTrackingMouseEnteredAndExited
                                                                     | NSTrackingActiveAlways
                                                                     | NSTrackingInVisibleRect)
                                                              owner:self
                                                           userInfo:nil];
        [self addTrackingArea:area];
    }
    return self;
}

- (void)applyAppearance {
    CGFloat alpha = self.hovering ? 0.72 : 0.52;
    self.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.08 alpha:alpha] CGColor];
}

- (void)setHovering:(BOOL)hovering {
    if (_hovering == hovering) {
        return;
    }
    _hovering = hovering;
    [self applyAppearance];
    if (self.mouseHoverDidChange) {
        self.mouseHoverDidChange(hovering);
    }
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovering = YES;
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovering = NO;
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (self.clickHandler) {
        self.clickHandler();
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

@end

@interface BrowserPresentationFullscreenExitOverlay ()
@property (nonatomic, strong, nullable) BrowserPresentationFullscreenExitButtonView *buttonView;
@property (nonatomic, strong, nullable) NSLayoutConstraint *buttonTopConstraint;
@property (nonatomic, strong, nullable) id localMonitor;
@property (nonatomic, strong, nullable) id globalMonitor;
@property (nonatomic, assign) BOOL buttonVisible;
@property (nonatomic, assign) BOOL hidePending;
@property (nonatomic, assign) BOOL pointerOverButton;
@end

@implementation BrowserPresentationFullscreenExitOverlay

- (instancetype)init {
    self = [super init];
    if (self) {
        _hideDelay = kDefaultHideDelay;
    }
    return self;
}

- (void)dealloc {
    [self setActive:NO];
}

- (nullable NSWindow *)targetWindow {
    return self.windowController.window;
}

- (nullable NSScreen *)targetScreen {
    return [self targetWindow].screen ?: NSScreen.mainScreen;
}

/// 系统菜单栏占用高度；全屏时 visibleFrame 常不可靠，优先 safeArea，再回退 24pt。
- (CGFloat)menuBarClearanceHeight {
    NSScreen *screen = [self targetScreen];
    if (!screen) {
        return 24.0;
    }
    if (@available(macOS 12.0, *)) {
        CGFloat safeTop = screen.safeAreaInsets.top;
        if (safeTop >= 20.0) {
            return safeTop;
        }
    }
    CGFloat delta = NSMaxY(screen.frame) - NSMaxY(screen.visibleFrame);
    if (delta >= 20.0) {
        return delta;
    }
    return 24.0;
}

- (CGFloat)revealedButtonTopInset {
    return [self menuBarClearanceHeight] + kBelowMenuBarGap;
}

- (CGFloat)topEdgeTriggerHeight {
    return MAX(kMinTopEdgeTriggerHeight, [self menuBarClearanceHeight] + 4.0);
}

- (void)setActive:(BOOL)active {
    if (_active == active) {
        if (active) {
            [self evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
        }
        return;
    }
    _active = active;
    [self cancelPendingHide];
    if (active) {
        [self installMonitors];
        [self ensureButtonInstalled];
        [self evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
    } else {
        [self tearDownMonitors];
        [self hideButtonAnimated:NO];
        [self removeButtonFromSuperview];
        self.pointerOverButton = NO;
    }
}

- (void)installMonitors {
    if (self.localMonitor) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged;
    self.globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask
                                                                handler:^(NSEvent *event) {
        (void)event;
        [weakSelf evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
    }];
    self.localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                              handler:^NSEvent *(NSEvent *event) {
        [weakSelf evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
        return event;
    }];
}

- (void)tearDownMonitors {
    if (self.globalMonitor) {
        [NSEvent removeMonitor:self.globalMonitor];
        self.globalMonitor = nil;
    }
    if (self.localMonitor) {
        [NSEvent removeMonitor:self.localMonitor];
        self.localMonitor = nil;
    }
}

- (void)ensureButtonInstalled {
    NSWindow *window = [self targetWindow];
    NSView *contentView = window.contentView;
    if (!contentView) {
        return;
    }
    if (self.buttonView && self.buttonView.superview == contentView && self.buttonTopConstraint) {
        return;
    }
    if (!self.buttonView) {
        __weak typeof(self) weakSelf = self;
        BrowserPresentationFullscreenExitButtonView *button =
            [[BrowserPresentationFullscreenExitButtonView alloc] initWithFrame:NSZeroRect];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.hidden = YES;
        button.alphaValue = 0.0;
        button.mouseHoverDidChange = ^(BOOL hovering) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.pointerOverButton = hovering;
            [strongSelf evaluatePointerAtScreenLocation:[NSEvent mouseLocation]];
        };
        button.clickHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.windowController togglePresentationFullscreen:nil];
        };
        self.buttonView = button;
    }
    [self.buttonTopConstraint setActive:NO];
    self.buttonTopConstraint = nil;

    [contentView addSubview:self.buttonView positioned:NSWindowAbove relativeTo:nil];
    // 收起态贴顶外；展开态落在菜单栏下方。
    self.buttonTopConstraint = [self.buttonView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                                        constant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.buttonView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        self.buttonTopConstraint,
    ]];
    if (self.buttonView.layer) {
        self.buttonView.layer.zPosition = 1000.0;
    }
}

- (void)removeButtonFromSuperview {
    [self.buttonTopConstraint setActive:NO];
    self.buttonTopConstraint = nil;
    [self.buttonView removeFromSuperview];
    self.buttonView = nil;
    self.buttonVisible = NO;
}

- (BOOL)isPointerInTopEdgeZone:(NSPoint)screenLocation {
    NSWindow *window = [self targetWindow];
    if (!window) {
        return NO;
    }
    NSScreen *screen = [self targetScreen];
    if (!screen) {
        return NO;
    }
    NSRect screenFrame = screen.frame;
    if (screenLocation.x < NSMinX(screenFrame) || screenLocation.x > NSMaxX(screenFrame)) {
        return NO;
    }
    return screenLocation.y >= (NSMaxY(screenFrame) - [self topEdgeTriggerHeight]);
}

- (BOOL)isPointerOverButton:(NSPoint)screenLocation {
    if (!self.buttonView || self.buttonView.hidden || !self.buttonView.window) {
        return NO;
    }
    NSRect buttonScreenFrame = [self.buttonView convertRect:self.buttonView.bounds toView:nil];
    buttonScreenFrame = [self.buttonView.window convertRectToScreen:buttonScreenFrame];
    return NSMouseInRect(screenLocation, buttonScreenFrame, NO);
}

- (void)evaluatePointerAtScreenLocation:(NSPoint)screenLocation {
    if (!self.active) {
        return;
    }
    BOOL keepVisible = [self isPointerInTopEdgeZone:screenLocation]
        || self.pointerOverButton
        || [self isPointerOverButton:screenLocation];
    if (keepVisible) {
        [self cancelPendingHide];
        [self showButtonAnimated:YES];
        return;
    }
    if (!self.buttonVisible) {
        return;
    }
    [self scheduleHideAfterDelay];
}

- (void)cancelPendingHide {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(commitHideAfterDelay)
                                               object:nil];
    self.hidePending = NO;
}

- (void)scheduleHideAfterDelay {
    if (self.hidePending) {
        return;
    }
    self.hidePending = YES;
    [self performSelector:@selector(commitHideAfterDelay)
               withObject:nil
               afterDelay:self.hideDelay];
}

- (void)commitHideAfterDelay {
    self.hidePending = NO;
    if (!self.active) {
        return;
    }
    NSPoint location = [NSEvent mouseLocation];
    if ([self isPointerInTopEdgeZone:location]
        || self.pointerOverButton
        || [self isPointerOverButton:location]) {
        return;
    }
    [self hideButtonAnimated:YES];
}

- (void)showButtonAnimated:(BOOL)animated {
    [self ensureButtonInstalled];
    if (!self.buttonView || !self.buttonTopConstraint) {
        return;
    }
    CGFloat revealedTop = [self revealedButtonTopInset];
    BOOL alreadyRevealed = self.buttonVisible
        && !self.buttonView.hidden
        && self.buttonView.alphaValue >= 0.99
        && fabs(self.buttonTopConstraint.constant - revealedTop) < 0.5;
    if (alreadyRevealed) {
        return;
    }

    self.buttonVisible = YES;
    self.buttonView.hidden = NO;

    if (!animated) {
        self.buttonTopConstraint.constant = revealedTop;
        self.buttonView.alphaValue = 1.0;
        return;
    }

    // 从贴近顶边滑到菜单栏下方，近似跟随系统栏下滑。
    if (self.buttonView.alphaValue < 0.05) {
        self.buttonTopConstraint.constant = 0.0;
        self.buttonView.alphaValue = 0.0;
        [self.buttonView.superview layoutSubtreeIfNeeded];
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = kRevealAnimationDuration;
        context.allowsImplicitAnimation = YES;
        self.buttonTopConstraint.animator.constant = revealedTop;
        self.buttonView.animator.alphaValue = 1.0;
    } completionHandler:nil];
}

- (void)hideButtonAnimated:(BOOL)animated {
    [self cancelPendingHide];
    self.buttonVisible = NO;
    self.pointerOverButton = NO;
    if (!self.buttonView) {
        return;
    }
    if (!animated) {
        self.buttonTopConstraint.constant = 0.0;
        self.buttonView.alphaValue = 0.0;
        self.buttonView.hidden = YES;
        self.buttonView.hovering = NO;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = kHideAnimationDuration;
        context.allowsImplicitAnimation = YES;
        self.buttonTopConstraint.animator.constant = 0.0;
        self.buttonView.animator.alphaValue = 0.0;
    } completionHandler:^{
        if (!self.buttonVisible) {
            self.buttonView.hidden = YES;
            self.buttonView.hovering = NO;
        }
    }];
}

@end
