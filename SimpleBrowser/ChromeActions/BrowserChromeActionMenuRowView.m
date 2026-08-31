#import "BrowserChromeActionMenuRowView.h"

static const CGFloat kRowHeight = 28.0;
static const CGFloat kRowWidth = 252.0;
static const CGFloat kIconSize = 16.0;
static const CGFloat kPinSize = 22.0;
static const CGFloat kHPad = 10.0;
static const CGFloat kIconTitleGap = 8.0;
static const CGFloat kTitlePinGap = 6.0;
static const CGFloat kActionSymbolPointSize = 12.0;
static const CGFloat kPinSymbolPointSize = 11.0;

@interface BrowserChromeActionMenuRowView ()
@property (nonatomic, strong) NSImageView *iconView;
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
        _symbolName = nil;
        _onSymbolName = nil;
        _titleEnabled = YES;
        _pinnedToToolbar = YES;

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.imageScaling = NSImageScaleProportionallyDown;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 10.14, *)) {
            _iconView.contentTintColor = [NSColor secondaryLabelColor];
        }
        [self addSubview:_iconView];

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
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kHPad],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:kIconSize],
            [_iconView.heightAnchor constraintEqualToConstant:kIconSize],

            [_titleButton.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:kIconTitleGap],
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

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    [self reloadAppearance];
}

- (void)setOnSymbolName:(NSString *)onSymbolName {
    _onSymbolName = [onSymbolName copy];
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

- (nullable NSImage *)symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    if (name.length == 0) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:pointSize
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

    NSString *actionSymbol = (self.checked && self.onSymbolName.length > 0)
        ? self.onSymbolName
        : self.symbolName;
    NSImage *actionImage = [self symbolNamed:actionSymbol pointSize:kActionSymbolPointSize];
    self.iconView.image = actionImage;
    self.iconView.hidden = (actionImage == nil);
    if (@available(macOS 10.14, *)) {
        if (self.checked) {
            self.iconView.contentTintColor = [NSColor controlAccentColor];
        } else if (self.titleEnabled) {
            self.iconView.contentTintColor = [NSColor secondaryLabelColor];
        } else {
            self.iconView.contentTintColor = [NSColor disabledControlTextColor];
        }
    }

    BOOL pinned = self.pinnedToToolbar;
    NSString *pinSymbol = pinned ? @"pin.slash" : @"pin";
    NSImage *pinImage = [self symbolNamed:pinSymbol pointSize:kPinSymbolPointSize];
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
