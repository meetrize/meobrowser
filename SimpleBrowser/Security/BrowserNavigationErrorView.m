#import "BrowserNavigationErrorView.h"

@interface BrowserNavigationErrorView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *goBackButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSStackView *buttonsStack;
@end

@implementation BrowserNavigationErrorView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:48
                                                                weight:NSFontWeightRegular
                                                                 scale:NSImageSymbolScaleLarge];
            NSImage *image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                       accessibilityDescription:@"错误"];
            iconView.image = [image imageWithSymbolConfiguration:config];
            if (@available(macOS 10.14, *)) {
                iconView.contentTintColor = [NSColor systemOrangeColor];
            }
        }
        [self addSubview:iconView];

        self.titleLabel = [NSTextField labelWithString:@"无法加载页面"];
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
        self.goBackButton.hidden = YES;

        self.reloadButton = [NSButton buttonWithTitle:@"重新加载"
                                               target:self
                                               action:@selector(reloadClicked:)];
        self.reloadButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.reloadButton.keyEquivalent = @"\r";

        self.buttonsStack = [NSStackView stackViewWithViews:@[ self.goBackButton, self.reloadButton ]];
        self.buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        self.buttonsStack.spacing = 12;
        self.buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.buttonsStack];

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

            [self.buttonsStack.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:28],
            [self.buttonsStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
}

- (void)configureWithTitle:(NSString *)title
                   message:(NSString *)message
                showGoBack:(BOOL)showGoBack {
    self.titleLabel.stringValue = title.length > 0 ? title : @"无法加载页面";
    self.messageLabel.stringValue = message.length > 0 ? message : @"发生未知错误。";
    self.goBackButton.hidden = !showGoBack;
}

- (void)goBackClicked:(id)sender {
    (void)sender;
    [self.delegate navigationErrorViewDidChooseGoBack:self];
}

- (void)reloadClicked:(id)sender {
    (void)sender;
    [self.delegate navigationErrorViewDidChooseReload:self];
}

@end
