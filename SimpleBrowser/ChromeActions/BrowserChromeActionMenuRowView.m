#import "BrowserChromeActionMenuRowView.h"

static const CGFloat kRowHeight = 28.0;
static const CGFloat kRowWidth = 240.0;
static const CGFloat kPinSize = 22.0;
static const CGFloat kHPad = 10.0;
static const CGFloat kTitlePinGap = 6.0;
static const CGFloat kSymbolPointSize = 11.0;

@interface BrowserChromeActionMenuRowView ()
@property (nonatomic, strong) NSButton *titleButton;
@property (nonatomic, strong) NSButton *pinButton;
@end

@implementation BrowserChromeActionMenuRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSRect frame = frameRect;
    if (NSIsEmptyRect(frame)) {
        frame = NSMakeRect(0, 0, kRowWidth, kRowHeight);
    }
    self = [super initWithFrame:frame];
    if (self) {
        _itemID = @"";
        _titleText = @"";
        _titleEnabled = YES;
        _pinnedToToolbar = YES;

        _titleButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        _titleButton.bezelStyle = NSBezelStyleInline;
        _titleButton.bordered = NO;
        _titleButton.alignment = NSTextAlignmentLeft;
        _titleButton.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleButton.translatesAutoresizingMaskIntoConstraints = NO;
        _titleButton.target = self;
        _titleButton.action = @selector(titleClicked:);
        if (@available(macOS 10.14, *)) {
            _titleButton.contentTintColor = [NSColor labelColor];
        }
        [self addSubview:_titleButton];

        _pinButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        _pinButton.bezelStyle = NSBezelStyleInline;
        _pinButton.bordered = NO;
        _pinButton.imagePosition = NSImageOnly;
        _pinButton.imageScaling = NSImageScaleProportionallyDown;
        _pinButton.translatesAutoresizingMaskIntoConstraints = NO;
        _pinButton.target = self;
        _pinButton.action = @selector(pinClicked:);
        [self addSubview:_pinButton];

        [NSLayoutConstraint activateConstraints:@[
            [_titleButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kHPad],
            [_titleButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleButton.trailingAnchor constraintEqualToAnchor:_pinButton.leadingAnchor constant:-kTitlePinGap],

            [_pinButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kHPad],
            [_pinButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pinButton.widthAnchor constraintEqualToConstant:kPinSize],
            [_pinButton.heightAnchor constraintEqualToConstant:kPinSize],

            [self.widthAnchor constraintEqualToConstant:kRowWidth],
            [self.heightAnchor constraintEqualToConstant:kRowHeight],
        ]];

        [self reloadAppearance];
    }
    return self;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(kRowWidth, kRowHeight);
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy] ?: @"";
    [self reloadAppearance];
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self reloadAppearance];
}

- (void)setPinnedToToolbar:(BOOL)pinnedToToolbar {
    _pinnedToToolbar = pinnedToToolbar;
    [self reloadAppearance];
}

- (void)setTitleEnabled:(BOOL)titleEnabled {
    _titleEnabled = titleEnabled;
    [self reloadAppearance];
}

- (nullable NSImage *)symbolNamed:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:kSymbolPointSize
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return image ? [image imageWithSymbolConfiguration:config] : nil;
    }
    return nil;
}

- (void)reloadAppearance {
    NSString *prefix = self.checked ? @"✓  " : @"    ";
    self.titleButton.title = [prefix stringByAppendingString:(self.titleText ?: @"")];
    self.titleButton.enabled = self.titleEnabled;
    self.titleButton.toolTip = self.titleText;
    self.titleButton.accessibilityLabel = self.titleText;

    BOOL pinned = self.pinnedToToolbar;
    NSString *pinSymbol = pinned ? @"pin.slash" : @"pin";
    NSImage *pinImage = [self symbolNamed:pinSymbol];
    if (pinImage) {
        self.pinButton.image = pinImage;
        self.pinButton.title = @"";
    } else {
        self.pinButton.image = nil;
        self.pinButton.title = pinned ? @"⊗" : @"⊙";
    }
    self.pinButton.toolTip = pinned ? @"从工具栏移除" : @"固定到工具栏";
    self.pinButton.accessibilityLabel = self.pinButton.toolTip;
    if (@available(macOS 10.14, *)) {
        self.pinButton.contentTintColor = [NSColor secondaryLabelColor];
        self.titleButton.contentTintColor = self.titleEnabled ? [NSColor labelColor] : [NSColor disabledControlTextColor];
    }
}

- (void)titleClicked:(id)sender {
    (void)sender;
    if (!self.titleEnabled) {
        return;
    }
    if (self.onTitleClick && self.itemID.length > 0) {
        self.onTitleClick(self.itemID);
    }
}

- (void)pinClicked:(id)sender {
    (void)sender;
    if (self.onPinClick && self.itemID.length > 0) {
        self.onPinClick(self.itemID);
    }
}

@end
