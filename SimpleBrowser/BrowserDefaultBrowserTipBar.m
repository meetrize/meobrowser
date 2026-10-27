#import "BrowserDefaultBrowserTipBar.h"
#import "BrowsingPreferences.h"

@interface BrowserDefaultBrowserTipBar ()
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign) BOOL dismissedThisSession;
@end

@implementation BrowserDefaultBrowserTipBar

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithCalibratedRed:1.0 green:0.84 blue:0.20 alpha:1.0] CGColor];
        self.hidden = NO;

        self.messageLabel = [NSTextField labelWithString:@"MeoBrowser 不是默认浏览器 — 点击此处设为默认"];
        self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.messageLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        self.messageLabel.textColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
        self.messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.messageLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

        self.closeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeClicked:)];
        self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.closeButton.bezelStyle = NSBezelStyleInline;
        self.closeButton.bordered = NO;
        self.closeButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        self.closeButton.contentTintColor = [NSColor colorWithCalibratedWhite:0.2 alpha:1.0];
        self.closeButton.toolTip = @"关闭提示";

        [self addSubview:self.messageLabel];
        [self addSubview:self.closeButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:32],
            [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [self.messageLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-8],
        ]];
        [self setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationVertical];
        self.toolTip = @"点击将 MeoBrowser 设为默认网页浏览器";

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)appDidBecomeActive:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshVisibility];
    });
}

- (void)refreshVisibility {
    if (self.dismissedThisSession) {
        self.hidden = YES;
        return;
    }
    self.hidden = [BrowsingPreferences isDefaultBrowser];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.closeButton.frame)) {
        [super mouseDown:event];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BrowsingPreferences requestSetAsDefaultBrowserWithCompletion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (error) {
            BOOL cancelled = ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError)
                || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
            if (!cancelled) {
                [BrowsingPreferences openDefaultBrowserSystemSettings];
            }
        }
        [self refreshVisibility];
    }];
}

- (void)closeClicked:(id)sender {
    (void)sender;
    self.dismissedThisSession = YES;
    self.hidden = YES;
}

@end
