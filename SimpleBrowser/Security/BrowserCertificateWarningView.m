#import "BrowserCertificateWarningView.h"

@interface BrowserCertificateWarningView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *goBackButton;
@property (nonatomic, strong) NSButton *proceedButton;
@property (nonatomic, copy, readwrite) NSString *hostDisplay;
@end

@implementation BrowserCertificateWarningView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        _hostDisplay = @"";

        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:48
                                                                weight:NSFontWeightRegular
                                                                 scale:NSImageSymbolScaleLarge];
            NSImage *image = [NSImage imageWithSystemSymbolName:@"exclamationmark.shield.fill"
                                       accessibilityDescription:@"警告"];
            iconView.image = [image imageWithSymbolConfiguration:config];
            if (@available(macOS 10.14, *)) {
                iconView.contentTintColor = [NSColor systemRedColor];
            }
        }
        [self addSubview:iconView];

        self.titleLabel = [NSTextField labelWithString:@"你的连接不是私密连接"];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [NSFont boldSystemFontOfSize:22];
        self.titleLabel.textColor = [NSColor labelColor];
        self.titleLabel.alignment = NSTextAlignmentCenter;
        self.titleLabel.maximumNumberOfLines = 2;
        [self addSubview:self.titleLabel];

        self.messageLabel = [NSTextField wrappingLabelWithString:@""];
        self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.messageLabel.font = [NSFont systemFontOfSize:14];
        self.messageLabel.textColor = [NSColor secondaryLabelColor];
        self.messageLabel.alignment = NSTextAlignmentCenter;
        self.messageLabel.preferredMaxLayoutWidth = 480;
        [self addSubview:self.messageLabel];

        self.goBackButton = [NSButton buttonWithTitle:@"返回"
                                               target:self
                                               action:@selector(goBackClicked:)];
        self.goBackButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.goBackButton.keyEquivalent = @"\033";
        [self addSubview:self.goBackButton];

        self.proceedButton = [NSButton buttonWithTitle:@"仍然访问"
                                                target:self
                                                action:@selector(proceedClicked:)];
        self.proceedButton.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 11.0, *)) {
            self.proceedButton.bezelColor = [NSColor systemRedColor];
        }
        [self addSubview:self.proceedButton];

        NSStackView *buttons = [NSStackView stackViewWithViews:@[ self.goBackButton, self.proceedButton ]];
        buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        buttons.spacing = 12;
        buttons.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:buttons];

        [NSLayoutConstraint activateConstraints:@[
            [iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-90],
            [iconView.widthAnchor constraintEqualToConstant:56],
            [iconView.heightAnchor constraintEqualToConstant:56],

            [self.titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:20],
            [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:40],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-40],

            [self.messageLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:12],
            [self.messageLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.messageLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:40],
            [self.messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-40],
            [self.messageLabel.widthAnchor constraintLessThanOrEqualToConstant:520],

            [buttons.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:28],
            [buttons.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
}

- (void)configureWithHost:(NSString *)host {
    self.hostDisplay = host.length > 0 ? [host copy] : @"未知主机";
    self.messageLabel.stringValue =
        [NSString stringWithFormat:
         @"服务器「%@」的证书不受信任。攻击者可能正在试图窃取你的信息（例如密码、消息或信用卡）。",
         self.hostDisplay];
}

- (void)goBackClicked:(id)sender {
    (void)sender;
    [self.delegate certificateWarningViewDidChooseGoBack:self];
}

- (void)proceedClicked:(id)sender {
    (void)sender;
    [self.delegate certificateWarningViewDidChooseProceed:self];
}

@end
