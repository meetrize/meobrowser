#import "BrowserTabItemView.h"

static const CGFloat kTabItemWidth = 160.0;
static const CGFloat kDefaultTabHeight = 33.0;

NSColor *BrowserTabActiveFillColor(void) {
    if ([[NSApp effectiveAppearance].name containsString:@"Dark"]) {
        return [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
    }
    return [NSColor whiteColor];
}

@interface BrowserTabItemView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@end

@implementation BrowserTabItemView

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIntrinsicContentSize {
    return [NSSet setWithObjects:@"tabTitle", @"tabSelected", nil];
}

- (NSSize)intrinsicContentSize {
    CGFloat height = self.heightConstraint ? self.heightConstraint.constant : kDefaultTabHeight;
    return NSMakeSize(kTabItemWidth, height);
}

- (void)setTabHeight:(CGFloat)height {
    if (!self.heightConstraint) {
        self.heightConstraint = [self.heightAnchor constraintEqualToConstant:height];
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = height;
    }
    [self invalidateIntrinsicContentSize];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;

        _titleLabel = [NSTextField labelWithString:@"新标签页"];
        _titleLabel.font = [NSFont systemFontOfSize:12];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _closeButton = [NSButton buttonWithTitle:@"×" target:self action:@selector(onClose:)];
        _closeButton.bezelStyle = NSBezelStyleInline;
        _closeButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:kTabItemWidth],

            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:16],
            [_closeButton.heightAnchor constraintEqualToConstant:16],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor constant:-4],
        ]];

        [self updateChromeAppearance];
    }
    return self;
}

- (void)setTabSelected:(BOOL)tabSelected {
    _tabSelected = tabSelected;
    [self updateChromeAppearance];
    [self invalidateIntrinsicContentSize];
}

- (void)setTabTitle:(NSString *)tabTitle {
    _tabTitle = [tabTitle copy];
    NSString *display = tabTitle.length > 0 ? tabTitle : @"新标签页";
    if (display.length > 20) {
        display = [[display substringToIndex:19] stringByAppendingString:@"…"];
    }
    self.titleLabel.stringValue = display;
    [self invalidateIntrinsicContentSize];
}

- (void)updateChromeAppearance {
    BOOL dark = [self effectiveAppearanceIsDark];
    NSColor *active = BrowserTabActiveFillColor();
    NSColor *inactive = dark ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]
                             : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];

    self.layer.backgroundColor = (self.tabSelected ? active : inactive).CGColor;

    if (@available(macOS 10.13, *)) {
        self.layer.cornerRadius = self.tabSelected ? 7.0 : 6.0;
        self.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }

    self.titleLabel.textColor = [NSColor labelColor];
    self.titleLabel.font = [NSFont systemFontOfSize:12
                                             weight:self.tabSelected ? NSFontWeightSemibold : NSFontWeightRegular];
}

- (BOOL)effectiveAppearanceIsDark {
    NSString *name = self.effectiveAppearance.name;
    return [name containsString:@"Dark"];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateChromeAppearance];
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (self.onSelect) {
        self.onSelect();
    }
}

- (void)onClose:(id)sender {
    (void)sender;
    if (self.onClose) {
        self.onClose();
    }
}

@end
