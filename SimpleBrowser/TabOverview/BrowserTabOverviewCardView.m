#import "BrowserTabOverviewCardView.h"
#import "BrowserFaviconService.h"
#import "BrowserTabItemView.h"
#import <QuartzCore/QuartzCore.h>

CGFloat BrowserTabOverviewCardHeightForWidth(CGFloat width);

static const CGFloat kCardCornerRadius = 9.0;
static const CGFloat kPreviewAspect = 10.0 / 16.0; // height / width for 16:10
static const CGFloat kFooterHeight = 36.0;

@interface BrowserTabOverviewCardView ()
@property (nonatomic, strong) NSView *previewContainer;
@property (nonatomic, strong) NSImageView *thumbnailView;
@property (nonatomic, strong) NSImageView *placeholderIconView;
@property (nonatomic, strong) NSTextField *placeholderLetterLabel;
@property (nonatomic, strong) NSTextField *hibernatedBadge;
@property (nonatomic, strong) NSImageView *pinBadge;
@property (nonatomic, strong) NSView *footer;
@property (nonatomic, strong) NSImageView *faviconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong, nullable) NSTrackingArea *hoverTracking;
@property (nonatomic, assign) BOOL hovering;
@property (nonatomic, copy, nullable) NSString *boundPageURLString;
@end

@implementation BrowserTabOverviewCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = kCardCornerRadius;
        self.layer.masksToBounds = NO;

        _previewContainer = [[NSView alloc] initWithFrame:NSZeroRect];
        _previewContainer.wantsLayer = YES;
        _previewContainer.layer.cornerRadius = kCardCornerRadius;
        _previewContainer.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        _previewContainer.layer.masksToBounds = YES;
        _previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_previewContainer];

        _thumbnailView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _thumbnailView.imageScaling = NSImageScaleAxesIndependently;
        _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailView.hidden = YES;
        [_previewContainer addSubview:_thumbnailView];

        _placeholderIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderIconView.imageScaling = NSImageScaleProportionallyDown;
        _placeholderIconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_previewContainer addSubview:_placeholderIconView];

        _placeholderLetterLabel = [NSTextField labelWithString:@""];
        _placeholderLetterLabel.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        _placeholderLetterLabel.textColor = [NSColor tertiaryLabelColor];
        _placeholderLetterLabel.alignment = NSTextAlignmentCenter;
        _placeholderLetterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_previewContainer addSubview:_placeholderLetterLabel];

        _hibernatedBadge = [NSTextField labelWithString:@"休眠"];
        _hibernatedBadge.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
        _hibernatedBadge.textColor = [NSColor secondaryLabelColor];
        _hibernatedBadge.drawsBackground = YES;
        _hibernatedBadge.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.35];
        _hibernatedBadge.wantsLayer = YES;
        _hibernatedBadge.layer.cornerRadius = 4.0;
        _hibernatedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _hibernatedBadge.hidden = YES;
        [_previewContainer addSubview:_hibernatedBadge];

        _pinBadge = [[NSImageView alloc] initWithFrame:NSZeroRect];
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *cfg =
                [NSImageSymbolConfiguration configurationWithPointSize:10
                                                                weight:NSFontWeightBold
                                                                 scale:NSImageSymbolScaleSmall];
            NSImage *pin = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:@"固定"];
            _pinBadge.image = [pin imageWithSymbolConfiguration:cfg];
        }
        _pinBadge.contentTintColor = [NSColor whiteColor];
        _pinBadge.wantsLayer = YES;
        _pinBadge.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.45].CGColor;
        _pinBadge.layer.cornerRadius = 4.0;
        _pinBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _pinBadge.hidden = YES;
        [_previewContainer addSubview:_pinBadge];

        _footer = [[NSView alloc] initWithFrame:NSZeroRect];
        _footer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_footer];

        _faviconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _faviconView.imageScaling = NSImageScaleProportionallyDown;
        _faviconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_footer addSubview:_faviconView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_footer addSubview:_titleLabel];

        _closeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeClicked:)];
        _closeButton.bezelStyle = NSBezelStyleInline;
        _closeButton.bordered = NO;
        _closeButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _closeButton.toolTip = @"关闭标签页";
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        _closeButton.hidden = YES;
        if (@available(macOS 10.14, *)) {
            _closeButton.contentTintColor = [NSColor secondaryLabelColor];
        }
        [_footer addSubview:_closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [_previewContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_previewContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_previewContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_footer.topAnchor constraintEqualToAnchor:_previewContainer.bottomAnchor],
            [_footer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_footer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_footer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_footer.heightAnchor constraintEqualToConstant:kFooterHeight],

            [_thumbnailView.topAnchor constraintEqualToAnchor:_previewContainer.topAnchor],
            [_thumbnailView.leadingAnchor constraintEqualToAnchor:_previewContainer.leadingAnchor],
            [_thumbnailView.trailingAnchor constraintEqualToAnchor:_previewContainer.trailingAnchor],
            [_thumbnailView.bottomAnchor constraintEqualToAnchor:_previewContainer.bottomAnchor],

            [_placeholderIconView.centerXAnchor constraintEqualToAnchor:_previewContainer.centerXAnchor],
            [_placeholderIconView.centerYAnchor constraintEqualToAnchor:_previewContainer.centerYAnchor constant:-4],
            [_placeholderIconView.widthAnchor constraintEqualToConstant:36],
            [_placeholderIconView.heightAnchor constraintEqualToConstant:36],

            [_placeholderLetterLabel.centerXAnchor constraintEqualToAnchor:_previewContainer.centerXAnchor],
            [_placeholderLetterLabel.centerYAnchor constraintEqualToAnchor:_previewContainer.centerYAnchor],

            [_hibernatedBadge.trailingAnchor constraintEqualToAnchor:_previewContainer.trailingAnchor constant:-8],
            [_hibernatedBadge.bottomAnchor constraintEqualToAnchor:_previewContainer.bottomAnchor constant:-8],

            [_pinBadge.leadingAnchor constraintEqualToAnchor:_previewContainer.leadingAnchor constant:8],
            [_pinBadge.topAnchor constraintEqualToAnchor:_previewContainer.topAnchor constant:8],
            [_pinBadge.widthAnchor constraintEqualToConstant:18],
            [_pinBadge.heightAnchor constraintEqualToConstant:18],

            [_faviconView.leadingAnchor constraintEqualToAnchor:_footer.leadingAnchor constant:10],
            [_faviconView.centerYAnchor constraintEqualToAnchor:_footer.centerYAnchor],
            [_faviconView.widthAnchor constraintEqualToConstant:14],
            [_faviconView.heightAnchor constraintEqualToConstant:14],

            [_closeButton.trailingAnchor constraintEqualToAnchor:_footer.trailingAnchor constant:-4],
            [_closeButton.centerYAnchor constraintEqualToAnchor:_footer.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:22],
            [_closeButton.heightAnchor constraintEqualToConstant:22],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_faviconView.trailingAnchor constant:6],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_footer.centerYAnchor],
        ]];

        [self applyChromeColors];
        [self updateSelectionChrome];
    }
    return self;
}

+ (BOOL)requiresConstraintBasedLayout {
    return YES;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (void)updateLayer {
    [super updateLayer];
    [self applyChromeColors];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyChromeColors];
    [self updateSelectionChrome];
}

- (void)applyChromeColors {
    BOOL dark = [[NSApp effectiveAppearance].name containsString:@"Dark"];
    NSColor *cardFill = dark
        ? [NSColor colorWithCalibratedWhite:0.22 alpha:1.0]
        : BrowserTabActiveFillColor();
    self.layer.backgroundColor = cardFill.CGColor;
    self.previewContainer.layer.backgroundColor = dark
        ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0].CGColor
        : [NSColor colorWithCalibratedWhite:0.94 alpha:1.0].CGColor;
}

- (void)setCardSelected:(BOOL)cardSelected {
    if (_cardSelected == cardSelected) {
        return;
    }
    _cardSelected = cardSelected;
    [self updateSelectionChrome];
}

- (void)setCardFocused:(BOOL)cardFocused {
    if (_cardFocused == cardFocused) {
        return;
    }
    _cardFocused = cardFocused;
    [self updateSelectionChrome];
}

- (void)updateSelectionChrome {
    if (self.cardSelected || self.cardFocused) {
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = [NSColor controlAccentColor].CGColor;
        self.layer.shadowOpacity = self.cardSelected ? 0.25 : 0.12;
        self.layer.shadowRadius = 6.0;
        self.layer.shadowOffset = CGSizeMake(0, -1);
        self.layer.shadowColor = [NSColor blackColor].CGColor;
    } else {
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
    }
}

- (void)setPinned:(BOOL)pinned {
    _pinned = pinned;
    self.pinBadge.hidden = !pinned;
}

- (void)setHibernated:(BOOL)hibernated {
    _hibernated = hibernated;
    self.hibernatedBadge.hidden = !hibernated;
    self.previewContainer.alphaValue = hibernated ? 0.78 : 1.0;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTracking) {
        [self removeTrackingArea:self.hoverTracking];
    }
    NSTrackingAreaOptions opts = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
    self.hoverTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                      options:opts
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:self.hoverTracking];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovering = YES;
    self.closeButton.hidden = NO;
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovering = NO;
    self.closeButton.hidden = YES;
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.closeButton.frame) && !self.closeButton.hidden) {
        return;
    }
    if (self.onSelect) {
        self.onSelect();
    }
}

- (void)closeClicked:(id)sender {
    (void)sender;
    if (self.onClose) {
        self.onClose();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    if (self.contextMenuProvider) {
        return self.contextMenuProvider();
    }
    return nil;
}

- (void)configureWithTitle:(NSString *)title
                 faviconURL:(NSURL *)pageURL
              thumbnailImage:(NSImage *)thumbnail {
    self.titleLabel.stringValue = title.length > 0 ? title : @"新标签页";
    self.boundPageURLString = pageURL.absoluteString;

    if (thumbnail) {
        [self setThumbnailImage:thumbnail];
    } else {
        [self setThumbnailImage:nil];
        [self applyPlaceholderForTitle:self.titleLabel.stringValue pageURL:pageURL];
    }

    if (self.newTabPage) {
        self.faviconView.image = nil;
        if (@available(macOS 11.0, *)) {
            NSImage *globe = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];
            self.faviconView.image = globe;
            self.faviconView.contentTintColor = [NSColor secondaryLabelColor];
        }
        return;
    }

    NSString *urlString = pageURL.absoluteString ?: @"";
    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] imageForPageURLString:urlString
                                                 preferredIconURL:nil
                                                      triggerFetch:YES
                                                        completion:^(NSImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (![strongSelf.boundPageURLString isEqualToString:urlString] && urlString.length > 0) {
            return;
        }
        if (image) {
            strongSelf.faviconView.image = image;
            if (!strongSelf.thumbnailView.image) {
                strongSelf.placeholderIconView.image = image;
                strongSelf.placeholderIconView.hidden = NO;
                strongSelf.placeholderLetterLabel.hidden = YES;
            }
        } else {
            strongSelf.faviconView.image = nil;
        }
    }];
}

- (void)setThumbnailImage:(NSImage *)image {
    if (image) {
        self.thumbnailView.image = image;
        self.thumbnailView.hidden = NO;
        self.placeholderIconView.hidden = YES;
        self.placeholderLetterLabel.hidden = YES;
    } else {
        self.thumbnailView.image = nil;
        self.thumbnailView.hidden = YES;
    }
}

- (void)applyPlaceholderForTitle:(NSString *)title pageURL:(NSURL *)pageURL {
    self.thumbnailView.hidden = YES;
    self.thumbnailView.image = nil;

    if (self.newTabPage) {
        self.placeholderLetterLabel.hidden = YES;
        self.placeholderIconView.hidden = NO;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *cfg =
                [NSImageSymbolConfiguration configurationWithPointSize:28
                                                                weight:NSFontWeightMedium
                                                                 scale:NSImageSymbolScaleMedium];
            NSImage *icon = [NSImage imageWithSystemSymbolName:@"square.grid.2x2" accessibilityDescription:nil];
            self.placeholderIconView.image = [icon imageWithSymbolConfiguration:cfg];
            self.placeholderIconView.contentTintColor = [NSColor tertiaryLabelColor];
        }
        return;
    }

    NSString *host = pageURL.host;
    NSString *seed = host.length > 0 ? host : title;
    unichar letter = seed.length > 0 ? [[seed uppercaseString] characterAtIndex:0] : '?';
    self.placeholderLetterLabel.stringValue = [NSString stringWithCharacters:&letter length:1];
    self.placeholderLetterLabel.hidden = NO;
    self.placeholderIconView.hidden = YES;
    self.placeholderIconView.image = nil;
}

@end

CGFloat BrowserTabOverviewCardHeightForWidth(CGFloat width) {
    return width * kPreviewAspect + kFooterHeight;
}
