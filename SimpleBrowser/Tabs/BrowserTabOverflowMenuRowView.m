#import "BrowserTabOverflowMenuRowView.h"
#import "BrowserFaviconService.h"
#import "BrowserFaviconUtil.h"
#import "BrowserShortcutIconPalette.h"

static const CGFloat kRowHeight = 28.0;
static const CGFloat kRowWidth = 280.0;
static const CGFloat kLeadingPad = 10.0;
static const CGFloat kCheckWidth = 14.0;
static const CGFloat kFaviconSize = 16.0;
static const CGFloat kGapAfterCheck = 4.0;
static const CGFloat kGapAfterFavicon = 6.0;

@interface BrowserTabOverflowMenuRowView ()
@property (nonatomic, strong) NSImageView *checkmarkView;
@property (nonatomic, strong) NSImageView *faviconView;
@property (nonatomic, strong) NSView *faviconLetterBadge;
@property (nonatomic, strong) NSTextField *faviconLetterLabel;
@property (nonatomic, strong) NSButton *titleButton;
@property (nonatomic, copy, nullable) NSString *boundHost;
@property (nonatomic, assign) NSUInteger faviconLoadToken;
@end

@implementation BrowserTabOverflowMenuRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSRect frame = frameRect;
    if (NSIsEmptyRect(frame)) {
        frame = NSMakeRect(0, 0, kRowWidth, kRowHeight);
    }
    self = [super initWithFrame:frame];
    if (self) {
        _titleText = @"";

        _checkmarkView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkmarkView.imageScaling = NSImageScaleProportionallyDown;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *cfg =
                [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold];
            NSImage *check = [NSImage imageWithSystemSymbolName:@"checkmark"
                                       accessibilityDescription:@"当前标签页"];
            _checkmarkView.image = check ? [check imageWithSymbolConfiguration:cfg] : nil;
            if (@available(macOS 10.14, *)) {
                _checkmarkView.contentTintColor = [NSColor labelColor];
            }
        }
        [self addSubview:_checkmarkView];

        _faviconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _faviconView.translatesAutoresizingMaskIntoConstraints = NO;
        _faviconView.imageScaling = NSImageScaleProportionallyDown;
        [self addSubview:_faviconView];

        _faviconLetterBadge = [[NSView alloc] initWithFrame:NSZeroRect];
        _faviconLetterBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _faviconLetterBadge.wantsLayer = YES;
        _faviconLetterBadge.layer.cornerRadius = 3.0;
        if (@available(macOS 10.15, *)) {
            _faviconLetterBadge.layer.cornerCurve = kCACornerCurveContinuous;
        }
        _faviconLetterBadge.hidden = YES;
        [self addSubview:_faviconLetterBadge];

        _faviconLetterLabel = [NSTextField labelWithString:@""];
        _faviconLetterLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold];
        _faviconLetterLabel.textColor = [NSColor whiteColor];
        _faviconLetterLabel.alignment = NSTextAlignmentCenter;
        _faviconLetterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_faviconLetterBadge addSubview:_faviconLetterLabel];

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

        [NSLayoutConstraint activateConstraints:@[
            [_checkmarkView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kLeadingPad],
            [_checkmarkView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_checkmarkView.widthAnchor constraintEqualToConstant:kCheckWidth],
            [_checkmarkView.heightAnchor constraintEqualToConstant:kCheckWidth],

            [_faviconView.leadingAnchor constraintEqualToAnchor:_checkmarkView.trailingAnchor constant:kGapAfterCheck],
            [_faviconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_faviconView.widthAnchor constraintEqualToConstant:kFaviconSize],
            [_faviconView.heightAnchor constraintEqualToConstant:kFaviconSize],

            [_faviconLetterBadge.leadingAnchor constraintEqualToAnchor:_faviconView.leadingAnchor],
            [_faviconLetterBadge.trailingAnchor constraintEqualToAnchor:_faviconView.trailingAnchor],
            [_faviconLetterBadge.topAnchor constraintEqualToAnchor:_faviconView.topAnchor],
            [_faviconLetterBadge.bottomAnchor constraintEqualToAnchor:_faviconView.bottomAnchor],

            [_faviconLetterLabel.centerXAnchor constraintEqualToAnchor:_faviconLetterBadge.centerXAnchor],
            [_faviconLetterLabel.centerYAnchor constraintEqualToAnchor:_faviconLetterBadge.centerYAnchor constant:0.5],

            [_titleButton.leadingAnchor constraintEqualToAnchor:_faviconView.trailingAnchor constant:kGapAfterFavicon],
            [_titleButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kLeadingPad],
            [_titleButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.widthAnchor constraintEqualToConstant:kRowWidth],
            [self.heightAnchor constraintEqualToConstant:kRowHeight],
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(faviconDidUpdate:)
                                                     name:BrowserFaviconDidUpdateNotification
                                                   object:nil];

        [self reloadAppearance];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(kRowWidth, kRowHeight);
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self reloadAppearance];
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy] ?: @"";
    [self reloadAppearance];
}

- (void)setPageURLString:(NSString *)pageURLString {
    NSString *normalized = pageURLString ?: @"";
    if ((_pageURLString == nil && normalized.length == 0)
        || [_pageURLString isEqualToString:normalized]) {
        return;
    }
    _pageURLString = normalized.length > 0 ? [normalized copy] : nil;
    _boundHost = BrowserFaviconHostFromURLString(normalized);
    [self reloadFaviconAppearance];
    [self requestFaviconIfNeeded];
}

- (void)reloadAppearance {
    self.checkmarkView.hidden = !self.checked;
    self.titleButton.title = self.titleText.length > 0 ? self.titleText : @"新标签页";
    self.titleButton.enabled = YES;
}

- (void)applyLoadedFaviconImage:(NSImage *)image {
    if (image) {
        self.faviconView.image = image;
        self.faviconView.hidden = NO;
        self.faviconLetterBadge.hidden = YES;
        return;
    }
    [self reloadFaviconAppearance];
}

- (void)reloadFaviconAppearance {
    NSString *urlString = self.pageURLString ?: @"";
    if (urlString.length == 0) {
        self.faviconView.image = BrowserFaviconMakeDefaultGlobeImage();
        self.faviconView.hidden = NO;
        self.faviconLetterBadge.hidden = YES;
        return;
    }

    NSString *host = self.boundHost ?: BrowserFaviconHostFromURLString(urlString);
    NSImage *cached = host.length > 0 ? [[BrowserFaviconService sharedService] cachedImageForHost:host] : nil;
    if (cached) {
        [self applyLoadedFaviconImage:cached];
        return;
    }

    self.faviconView.image = nil;
    self.faviconView.hidden = YES;
    NSString *letter = [BrowserShortcutIconPalette defaultLetterForTitle:self.titleText urlString:urlString];
    NSInteger colorIndex = [BrowserShortcutIconPalette defaultIndexForURLString:urlString];
    self.faviconLetterBadge.layer.backgroundColor = [BrowserShortcutIconPalette colorAtIndex:colorIndex].CGColor;
    self.faviconLetterLabel.stringValue = letter.length > 0 ? letter : @"?";
    self.faviconLetterBadge.hidden = NO;
}

- (void)requestFaviconIfNeeded {
    NSString *urlString = self.pageURLString ?: @"";
    if (urlString.length == 0) {
        return;
    }
    self.faviconLoadToken += 1;
    NSUInteger token = self.faviconLoadToken;
    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] imageForPageURLString:urlString
                                                 preferredIconURL:nil
                                                      triggerFetch:YES
                                                        completion:^(NSImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.faviconLoadToken) {
            return;
        }
        if (image) {
            [strongSelf applyLoadedFaviconImage:image];
        }
    }];
}

- (void)faviconDidUpdate:(NSNotification *)notification {
    NSString *host = notification.userInfo[BrowserFaviconHostUserInfoKey];
    if (![host isKindOfClass:[NSString class]]) {
        host = nil;
    }
    if (host.length == 0 || self.boundHost.length == 0 || ![host isEqualToString:self.boundHost]) {
        return;
    }
    NSImage *image = [[BrowserFaviconService sharedService] cachedImageForHost:host];
    if (image) {
        [self applyLoadedFaviconImage:image];
    }
}

- (void)titleClicked:(id)sender {
    (void)sender;
    if (self.onSelect) {
        self.onSelect();
    }
}

@end
