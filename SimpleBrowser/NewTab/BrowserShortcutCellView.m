#import "BrowserShortcutCellView.h"
#import "BrowserShortcutItem.h"
#import "BrowserLaunchpadAppearance.h"
#import "BrowserLaunchpadView.h"
#import "BrowserShortcutFolderOverlay.h"
#import <QuartzCore/QuartzCore.h>

@interface BrowserLaunchpadView (CellDragSupport)
@property (nonatomic, readonly, getter=isDraggingShortcut) BOOL draggingShortcut;
- (BOOL)launchpadBeginDraggingShortcut:(BrowserShortcutItem *)shortcut
                              fromView:(NSView *)view
                                 event:(NSEvent *)event;
@end

static const CGFloat kIconShadowBlur = 6.0;
static const CGFloat kIconShadowOffsetY = -2.0;
static const CGFloat kIconShadowAlpha = 0.22;
static const CGFloat kHoverScale = 1.05;
static const NSTimeInterval kHoverAnimationDuration = 0.15;

static NSColor *ColorFromURLString(NSString *urlString) {
    NSUInteger hash = urlString.hash;
    CGFloat hue = (CGFloat)(hash % 360) / 360.0;
    return [NSColor colorWithHue:hue saturation:0.45 brightness:0.85 alpha:1.0];
}

static NSString *DisplayLetterForShortcut(BrowserShortcutItem *item) {
    if (item.title.length > 0) {
        return [[item.title substringToIndex:1] uppercaseString];
    }
    NSURL *url = [NSURL URLWithString:item.urlString];
    NSString *host = url.host.length > 0 ? url.host : @"?";
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return [[host substringToIndex:1] uppercaseString];
}

@interface BrowserShortcutIconLoader : NSObject
+ (instancetype)sharedLoader;
- (void)loadImageForURLString:(NSString *)urlString
                   completion:(void (^)(NSImage * _Nullable image))completion;
@end

@interface BrowserShortcutIconLoader ()
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *imageCache;
@end

@implementation BrowserShortcutIconLoader

+ (instancetype)sharedLoader {
    static BrowserShortcutIconLoader *loader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [[BrowserShortcutIconLoader alloc] init];
    });
    return loader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 128;
    }
    return self;
}

- (void)loadImageForURLString:(NSString *)urlString
                   completion:(void (^)(NSImage * _Nullable image))completion {
    if (urlString.length == 0 || !completion) {
        completion(nil);
        return;
    }

    NSImage *cached = [self.imageCache objectForKey:urlString];
    if (cached) {
        completion(cached);
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil);
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        NSImage *image = nil;
        if (!error && data.length > 0) {
            image = [[NSImage alloc] initWithData:data];
        }
        if (image && image.size.width > 0 && image.size.height > 0) {
            [self.imageCache setObject:image forKey:urlString];
        } else {
            image = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    }];
    [task resume];
}

@end

@interface BrowserShortcutIconBackdropView : NSView
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat shadowInset;
@end

@implementation BrowserShortcutIconBackdropView

+ (BOOL)isOpaque {
    return NO;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _cornerRadius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:[BrowserLaunchpadAppearance defaultIconSize]];
        _shadowInset = [BrowserLaunchpadAppearance iconShadowInsetForIconSize:[BrowserLaunchpadAppearance defaultIconSize]];
    }
    return self;
}

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay:YES];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsDisplay:YES];
}

- (void)setShadowInset:(CGFloat)shadowInset {
    _shadowInset = shadowInset;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect iconRect = NSInsetRect(self.bounds, self.shadowInset, self.shadowInset);
    if (iconRect.size.width <= 0 || iconRect.size.height <= 0) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0 alpha:kIconShadowAlpha];
    shadow.shadowOffset = NSMakeSize(0, kIconShadowOffsetY);
    shadow.shadowBlurRadius = kIconShadowBlur;
    [shadow set];

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:iconRect
                                                         xRadius:self.cornerRadius
                                                         yRadius:self.cornerRadius];
    NSColor *fill = self.fillColor ?: NSColor.whiteColor;
    [fill setFill];
    [path fill];

    [context restoreGraphicsState];
}

@end

@interface BrowserShortcutFolderTileView : NSView
@property (nonatomic, strong) BrowserShortcutIconBackdropView *backdropView;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSTextField *letterLabel;
@property (nonatomic, assign) NSUInteger loadToken;
@end

@implementation BrowserShortcutFolderTileView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _backdropView = [[BrowserShortcutIconBackdropView alloc] initWithFrame:NSZeroRect];
        _backdropView.translatesAutoresizingMaskIntoConstraints = NO;
        _backdropView.shadowInset = 0;
        _backdropView.cornerRadius = 4;
        [self addSubview:_backdropView];

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _imageView.wantsLayer = YES;
        _imageView.layer.masksToBounds = YES;
        _imageView.layer.cornerRadius = 4;
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.hidden = YES;
        [self addSubview:_imageView];

        _letterLabel = [NSTextField labelWithString:@""];
        _letterLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _letterLabel.textColor = NSColor.whiteColor;
        _letterLabel.alignment = NSTextAlignmentCenter;
        _letterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_letterLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_backdropView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_backdropView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_backdropView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_backdropView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_letterLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_letterLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithShortcut:(nullable BrowserShortcutItem *)shortcut {
    self.loadToken += 1;
    NSUInteger token = self.loadToken;
    if (!shortcut) {
        self.hidden = YES;
        self.imageView.image = nil;
        self.letterLabel.stringValue = @"";
        return;
    }

    self.hidden = NO;
    self.imageView.hidden = YES;
    self.letterLabel.hidden = NO;
    self.letterLabel.stringValue = DisplayLetterForShortcut(shortcut);
    self.backdropView.fillColor = ColorFromURLString(shortcut.urlString);

    if (shortcut.iconURLString.length == 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[BrowserShortcutIconLoader sharedLoader] loadImageForURLString:shortcut.iconURLString
                                                          completion:^(NSImage *image) {
        BrowserShortcutFolderTileView *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.loadToken != token || !image) {
            return;
        }
        strongSelf.imageView.image = image;
        strongSelf.imageView.hidden = NO;
        strongSelf.letterLabel.hidden = YES;
        strongSelf.backdropView.fillColor = NSColor.whiteColor;
    }];
}

@end


@interface BrowserShortcutCellContentView : NSView
@property (nonatomic, strong) NSView *iconAnimContainer;
@property (nonatomic, strong) BrowserShortcutIconBackdropView *iconBackdropView;
@property (nonatomic, strong) NSImageView *iconImageView;
@property (nonatomic, strong) NSTextField *letterLabel;
@property (nonatomic, strong) NSView *folderGridView;
@property (nonatomic, strong) NSArray<BrowserShortcutFolderTileView *> *folderTiles;
@property (nonatomic, strong) NSView *mergeRingView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, copy, nullable) BrowserShortcutCellActivateHandler onActivate;
@property (nonatomic, copy, nullable) dispatch_block_t onAddTapped;
@property (nonatomic, strong, nullable) BrowserShortcutItem *shortcut;
@property (nonatomic, copy) NSArray<BrowserShortcutItem *> *folderChildren;
@property (nonatomic, assign, getter=isAddCell) BOOL addCell;
@property (nonatomic, assign, getter=isMergeHighlighted) BOOL mergeHighlighted;
@property (nonatomic, assign) BOOL trackingHover;
@property (nonatomic, assign) NSUInteger iconLoadToken;
@property (nonatomic, assign) NSPoint mouseDownLocation;
@property (nonatomic, strong, nullable) NSEvent *mouseDownEvent;
@property (nonatomic, assign) BOOL didStartDrag;
@property (nonatomic, assign) CGFloat iconSize;
@property (nonatomic, strong) NSLayoutConstraint *cellWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cellHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconContainerWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconContainerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconHeightConstraint;
@end

@implementation BrowserShortcutCellContentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        self.clipsToBounds = NO;
        self.canDrawSubviewsIntoLayer = NO;
        _iconSize = [BrowserLaunchpadAppearance defaultIconSize];
        _folderChildren = @[];

        _iconAnimContainer = [[NSView alloc] initWithFrame:NSZeroRect];
        _iconAnimContainer.wantsLayer = YES;
        _iconAnimContainer.layer.masksToBounds = NO;
        _iconAnimContainer.clipsToBounds = NO;
        _iconAnimContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconAnimContainer];

        _iconBackdropView = [[BrowserShortcutIconBackdropView alloc] initWithFrame:NSZeroRect];
        _iconBackdropView.fillColor = NSColor.whiteColor;
        _iconBackdropView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconAnimContainer addSubview:_iconBackdropView];

        _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconImageView.wantsLayer = YES;
        _iconImageView.layer.masksToBounds = YES;
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.hidden = YES;
        [_iconAnimContainer addSubview:_iconImageView];

        _letterLabel = [NSTextField labelWithString:@""];
        _letterLabel.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        _letterLabel.textColor = [NSColor whiteColor];
        _letterLabel.alignment = NSTextAlignmentCenter;
        _letterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconAnimContainer addSubview:_letterLabel];

        _folderGridView = [[NSView alloc] initWithFrame:NSZeroRect];
        _folderGridView.translatesAutoresizingMaskIntoConstraints = NO;
        _folderGridView.hidden = YES;
        [_iconAnimContainer addSubview:_folderGridView];

        NSMutableArray<BrowserShortcutFolderTileView *> *tiles = [[NSMutableArray alloc] initWithCapacity:4];
        for (NSInteger i = 0; i < 4; i++) {
            BrowserShortcutFolderTileView *tile = [[BrowserShortcutFolderTileView alloc] initWithFrame:NSZeroRect];
            [_folderGridView addSubview:tile];
            [tiles addObject:tile];
        }
        _folderTiles = [tiles copy];

        _mergeRingView = [[NSView alloc] initWithFrame:NSZeroRect];
        _mergeRingView.wantsLayer = YES;
        _mergeRingView.layer.borderWidth = 2.5;
        _mergeRingView.layer.borderColor = NSColor.controlAccentColor.CGColor;
        _mergeRingView.hidden = YES;
        _mergeRingView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconAnimContainer addSubview:_mergeRingView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.font = [NSFont systemFontOfSize:13];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.alignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:_iconSize];
        CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:_iconSize];
        CGFloat shadowInset = [BrowserLaunchpadAppearance iconShadowInsetForIconSize:_iconSize];
        CGFloat iconContainerSize = _iconSize + shadowInset * 2.0;
        CGFloat cornerRadius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:_iconSize];
        _iconImageView.layer.cornerRadius = cornerRadius;
        _iconBackdropView.cornerRadius = cornerRadius;
        _iconBackdropView.shadowInset = shadowInset;
        _mergeRingView.layer.cornerRadius = cornerRadius + 3.0;

        _cellWidthConstraint = [self.widthAnchor constraintEqualToConstant:cellWidth];
        _cellHeightConstraint = [self.heightAnchor constraintEqualToConstant:cellHeight];
        _iconContainerWidthConstraint = [_iconAnimContainer.widthAnchor constraintEqualToConstant:iconContainerSize];
        _iconContainerHeightConstraint = [_iconAnimContainer.heightAnchor constraintEqualToConstant:iconContainerSize];
        _iconWidthConstraint = [_iconImageView.widthAnchor constraintEqualToConstant:_iconSize];
        _iconHeightConstraint = [_iconImageView.heightAnchor constraintEqualToConstant:_iconSize];

        BrowserShortcutFolderTileView *tile0 = _folderTiles[0];
        BrowserShortcutFolderTileView *tile1 = _folderTiles[1];
        BrowserShortcutFolderTileView *tile2 = _folderTiles[2];
        BrowserShortcutFolderTileView *tile3 = _folderTiles[3];

        [NSLayoutConstraint activateConstraints:@[
            _cellWidthConstraint,
            _cellHeightConstraint,
            _iconContainerWidthConstraint,
            _iconContainerHeightConstraint,
            [_iconAnimContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_iconAnimContainer.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconBackdropView.topAnchor constraintEqualToAnchor:_iconAnimContainer.topAnchor],
            [_iconBackdropView.leadingAnchor constraintEqualToAnchor:_iconAnimContainer.leadingAnchor],
            [_iconBackdropView.trailingAnchor constraintEqualToAnchor:_iconAnimContainer.trailingAnchor],
            [_iconBackdropView.bottomAnchor constraintEqualToAnchor:_iconAnimContainer.bottomAnchor],
            _iconWidthConstraint,
            _iconHeightConstraint,
            [_iconImageView.centerXAnchor constraintEqualToAnchor:_iconAnimContainer.centerXAnchor],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:_iconAnimContainer.centerYAnchor],
            [_letterLabel.centerXAnchor constraintEqualToAnchor:_iconAnimContainer.centerXAnchor],
            [_letterLabel.centerYAnchor constraintEqualToAnchor:_iconAnimContainer.centerYAnchor],
            [_folderGridView.centerXAnchor constraintEqualToAnchor:_iconAnimContainer.centerXAnchor],
            [_folderGridView.centerYAnchor constraintEqualToAnchor:_iconAnimContainer.centerYAnchor],
            [_folderGridView.widthAnchor constraintEqualToAnchor:_iconImageView.widthAnchor multiplier:0.86],
            [_folderGridView.heightAnchor constraintEqualToAnchor:_iconImageView.heightAnchor multiplier:0.86],
            [tile0.topAnchor constraintEqualToAnchor:_folderGridView.topAnchor],
            [tile0.leadingAnchor constraintEqualToAnchor:_folderGridView.leadingAnchor],
            [tile0.widthAnchor constraintEqualToAnchor:_folderGridView.widthAnchor multiplier:0.46],
            [tile0.heightAnchor constraintEqualToAnchor:_folderGridView.heightAnchor multiplier:0.46],
            [tile1.topAnchor constraintEqualToAnchor:_folderGridView.topAnchor],
            [tile1.trailingAnchor constraintEqualToAnchor:_folderGridView.trailingAnchor],
            [tile1.widthAnchor constraintEqualToAnchor:tile0.widthAnchor],
            [tile1.heightAnchor constraintEqualToAnchor:tile0.heightAnchor],
            [tile2.bottomAnchor constraintEqualToAnchor:_folderGridView.bottomAnchor],
            [tile2.leadingAnchor constraintEqualToAnchor:_folderGridView.leadingAnchor],
            [tile2.widthAnchor constraintEqualToAnchor:tile0.widthAnchor],
            [tile2.heightAnchor constraintEqualToAnchor:tile0.heightAnchor],
            [tile3.bottomAnchor constraintEqualToAnchor:_folderGridView.bottomAnchor],
            [tile3.trailingAnchor constraintEqualToAnchor:_folderGridView.trailingAnchor],
            [tile3.widthAnchor constraintEqualToAnchor:tile0.widthAnchor],
            [tile3.heightAnchor constraintEqualToAnchor:tile0.heightAnchor],
            [_mergeRingView.centerXAnchor constraintEqualToAnchor:_iconAnimContainer.centerXAnchor],
            [_mergeRingView.centerYAnchor constraintEqualToAnchor:_iconAnimContainer.centerYAnchor],
            [_mergeRingView.widthAnchor constraintEqualToAnchor:_iconImageView.widthAnchor constant:8],
            [_mergeRingView.heightAnchor constraintEqualToAnchor:_iconImageView.heightAnchor constant:8],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconAnimContainer.bottomAnchor constant:2],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],
        ]];
    }
    return self;
}

- (void)applyIconSize:(CGFloat)iconSize {
    if (fabs(self.iconSize - iconSize) < 0.5) {
        return;
    }
    self.iconSize = iconSize;
    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:iconSize];
    CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:iconSize];
    CGFloat shadowInset = [BrowserLaunchpadAppearance iconShadowInsetForIconSize:iconSize];
    CGFloat iconContainerSize = iconSize + shadowInset * 2.0;
    CGFloat cornerRadius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:iconSize];
    CGFloat letterFontSize = 28.0 * (iconSize / [BrowserLaunchpadAppearance defaultIconSize]);

    self.cellWidthConstraint.constant = cellWidth;
    self.cellHeightConstraint.constant = cellHeight;
    self.iconContainerWidthConstraint.constant = iconContainerSize;
    self.iconContainerHeightConstraint.constant = iconContainerSize;
    self.iconWidthConstraint.constant = iconSize;
    self.iconHeightConstraint.constant = iconSize;
    self.iconImageView.layer.cornerRadius = cornerRadius;
    self.iconBackdropView.cornerRadius = cornerRadius;
    self.iconBackdropView.shadowInset = shadowInset;
    self.mergeRingView.layer.cornerRadius = cornerRadius + 3.0;
    self.letterLabel.font = [NSFont systemFontOfSize:letterFontSize weight:NSFontWeightSemibold];
    [self setNeedsLayout:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingHover) {
        return;
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:area];
    self.trackingHover = YES;
}

- (void)updateIconFillColor:(NSColor *)color {
    self.iconBackdropView.fillColor = color;
}

- (void)applyLetterFallbackForShortcut:(BrowserShortcutItem *)shortcut {
    self.iconImageView.image = nil;
    self.iconImageView.hidden = YES;
    self.letterLabel.stringValue = DisplayLetterForShortcut(shortcut);
    self.letterLabel.textColor = [NSColor whiteColor];
    self.letterLabel.hidden = NO;
    [self updateIconFillColor:ColorFromURLString(shortcut.urlString)];
}

- (void)applyLoadedIconImage:(NSImage *)image {
    self.iconImageView.image = image;
    self.iconImageView.hidden = NO;
    self.letterLabel.hidden = YES;
    [self updateIconFillColor:NSColor.whiteColor];
}

- (void)loadIconForShortcut:(BrowserShortcutItem *)shortcut {
    self.iconLoadToken += 1;
    NSUInteger token = self.iconLoadToken;
    [self applyLetterFallbackForShortcut:shortcut];
    if (shortcut.iconURLString.length == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[BrowserShortcutIconLoader sharedLoader] loadImageForURLString:shortcut.iconURLString
                                                          completion:^(NSImage *image) {
        BrowserShortcutCellContentView *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.iconLoadToken != token || !image) {
            return;
        }
        [strongSelf applyLoadedIconImage:image];
    }];
}

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut
                     children:(NSArray<BrowserShortcutItem *> *)children {
    self.addCell = NO;
    self.shortcut = shortcut;
    self.folderChildren = children ?: @[];
    self.titleLabel.stringValue = shortcut.title;
    self.titleLabel.hidden = NO;
    self.mergeHighlighted = NO;
    if (shortcut.isFolder) {
        [self configureAsFolderWithChildren:self.folderChildren];
    } else {
        self.folderGridView.hidden = YES;
        [self loadIconForShortcut:shortcut];
    }
}

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut {
    [self configureWithShortcut:shortcut children:@[]];
}

- (void)configureAsFolderWithChildren:(NSArray<BrowserShortcutItem *> *)children {
    self.iconLoadToken += 1;
    self.iconImageView.image = nil;
    self.iconImageView.hidden = YES;
    self.letterLabel.hidden = YES;
    self.folderGridView.hidden = NO;
    [self updateIconFillColor:[NSColor.quaternaryLabelColor colorWithAlphaComponent:0.55]];
    for (NSUInteger i = 0; i < self.folderTiles.count; i++) {
        BrowserShortcutItem *child = (i < children.count) ? children[i] : nil;
        [self.folderTiles[i] configureWithShortcut:child];
    }
}

- (void)configureAsAddCell {
    self.addCell = YES;
    self.shortcut = nil;
    self.folderChildren = @[];
    self.iconLoadToken += 1;
    self.iconImageView.image = nil;
    self.iconImageView.hidden = YES;
    self.folderGridView.hidden = YES;
    self.mergeHighlighted = NO;
    self.letterLabel.stringValue = @"+";
    self.titleLabel.stringValue = @"添加";
    self.letterLabel.hidden = NO;
    self.titleLabel.hidden = NO;
    self.letterLabel.textColor = [NSColor secondaryLabelColor];
    [self updateIconFillColor:NSColor.quaternaryLabelColor];
}

- (void)setMergeHighlighted:(BOOL)mergeHighlighted {
    _mergeHighlighted = mergeHighlighted;
    self.mergeRingView.hidden = !mergeHighlighted;
    if (mergeHighlighted) {
        self.mergeRingView.layer.borderColor = NSColor.controlAccentColor.CGColor;
    }
}

- (void)setHoverScale:(CGFloat)scale animated:(BOOL)animated {
    void (^apply)(void) = ^{
        self.layer.transform = CATransform3DMakeScale(scale, scale, 1.0);
    };
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = kHoverAnimationDuration;
            apply();
        } completionHandler:nil];
    } else {
        apply();
    }
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    [self setHoverScale:kHoverScale animated:YES];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    [self setHoverScale:1.0 animated:YES];
}

- (nullable BrowserLaunchpadView *)enclosingLaunchpadView {
    NSView *view = self.superview;
    while (view) {
        if ([view isKindOfClass:[BrowserLaunchpadView class]]) {
            return (BrowserLaunchpadView *)view;
        }
        view = view.superview;
    }
    return nil;
}

- (nullable BrowserShortcutFolderOverlay *)enclosingFolderOverlay {
    NSView *view = self.superview;
    while (view) {
        if ([view isKindOfClass:[BrowserShortcutFolderOverlay class]]) {
            return (BrowserShortcutFolderOverlay *)view;
        }
        view = view.superview;
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    if (self.addCell) {
        [super mouseDown:event];
        return;
    }
    self.mouseDownLocation = event.locationInWindow;
    self.mouseDownEvent = event;
    self.didStartDrag = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.addCell || self.didStartDrag || !self.shortcut) {
        return;
    }
    NSPoint loc = event.locationInWindow;
    CGFloat dx = loc.x - self.mouseDownLocation.x;
    CGFloat dy = loc.y - self.mouseDownLocation.y;
    if ((dx * dx + dy * dy) < 16.0) {
        return;
    }
    NSEvent *dragEvent = self.mouseDownEvent ?: event;
    // 夹内优先：拖到面板外可移回顶层；勿走主网格（overlay 打开时主网格会拒绝拖拽）。
    BrowserShortcutFolderOverlay *overlay = [self enclosingFolderOverlay];
    if (overlay && [overlay beginDraggingChild:self.shortcut fromView:self event:dragEvent]) {
        self.didStartDrag = YES;
        return;
    }
    BrowserLaunchpadView *host = [self enclosingLaunchpadView];
    if (host && [host launchpadBeginDraggingShortcut:self.shortcut fromView:self event:dragEvent]) {
        self.didStartDrag = YES;
    }
}

- (void)mouseUp:(NSEvent *)event {
    self.mouseDownEvent = nil;
    if (self.addCell) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (NSPointInRect(point, self.bounds) && self.onAddTapped) {
            self.onAddTapped();
        }
        return;
    }

    if (self.didStartDrag) {
        self.didStartDrag = NO;
        return;
    }

    BrowserLaunchpadView *launchpad = [self enclosingLaunchpadView];
    if (launchpad.isDraggingShortcut) {
        return;
    }

    NSPoint up = event.locationInWindow;
    CGFloat dx = up.x - self.mouseDownLocation.x;
    CGFloat dy = up.y - self.mouseDownLocation.y;
    BOOL wasClick = (dx * dx + dy * dy) < 16.0;
    if (!wasClick || !self.shortcut || !self.onActivate) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) {
        return;
    }
    if (self.shortcut.isFolder && event.buttonNumber == 2) {
        return;
    }
    BOOL openInNewTab = (event.buttonNumber == 2);
    self.onActivate(self.shortcut, openInNewTab);
}

@end

@interface BrowserShortcutCellView ()
@property (nonatomic, strong) BrowserShortcutCellContentView *shortcutContentView;
@end

@implementation BrowserShortcutCellView

+ (nullable NSView *)dragProxyViewFromContentView:(NSView *)contentView {
    if (![contentView isKindOfClass:[BrowserShortcutCellContentView class]]) {
        return nil;
    }
    return [(BrowserShortcutCellContentView *)contentView iconAnimContainer];
}

+ (nullable NSImage *)draggingProxyImageFromContentView:(NSView *)contentView
                                                  alpha:(CGFloat)alpha {
    NSView *proxy = [self dragProxyViewFromContentView:contentView];
    if (!proxy) {
        return nil;
    }
    NSRect bounds = proxy.bounds;
    if (bounds.size.width < 1.0 || bounds.size.height < 1.0) {
        return nil;
    }
    NSBitmapImageRep *rep = [proxy bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep) {
        return nil;
    }
    [proxy cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *opaque = [[NSImage alloc] initWithSize:bounds.size];
    [opaque addRepresentation:rep];

    CGFloat clamped = MAX(0.15, MIN(alpha, 1.0));
    if (clamped >= 0.999) {
        return opaque;
    }
    NSImage *ghost = [[NSImage alloc] initWithSize:bounds.size];
    [ghost lockFocus];
    [opaque drawInRect:NSMakeRect(0, 0, bounds.size.width, bounds.size.height)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:clamped
        respectFlipped:YES
                 hints:nil];
    [ghost unlockFocus];
    return ghost;
}

+ (NSRect)draggingProxyFrameFromContentView:(NSView *)contentView
                                     inView:(NSView *)targetView {
    NSView *proxy = [self dragProxyViewFromContentView:contentView];
    if (!proxy || !targetView) {
        return NSZeroRect;
    }
    return [proxy convertRect:proxy.bounds toView:targetView];
}

- (void)loadView {
    CGFloat iconSize = [BrowserLaunchpadAppearance current].iconSize;
    CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:iconSize];
    CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:iconSize];
    self.shortcutContentView = [[BrowserShortcutCellContentView alloc] initWithFrame:NSMakeRect(0, 0, cellWidth, cellHeight)];
    self.shortcutContentView.clipsToBounds = NO;
    [self.shortcutContentView applyIconSize:iconSize];
    self.view = self.shortcutContentView;
}

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut {
    [self configureWithShortcut:shortcut children:@[]];
}

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut
                     children:(NSArray<BrowserShortcutItem *> *)children {
    self.shortcut = shortcut;
    [self.shortcutContentView applyIconSize:[BrowserLaunchpadAppearance current].iconSize];
    [self.shortcutContentView configureWithShortcut:shortcut children:children];
    [self bindHandlers];
}

- (void)configureAsAddCell {
    self.shortcut = nil;
    [self.shortcutContentView applyIconSize:[BrowserLaunchpadAppearance current].iconSize];
    [self.shortcutContentView configureAsAddCell];
    [self bindHandlers];
}

- (void)applyIconSize:(CGFloat)iconSize {
    [self.shortcutContentView applyIconSize:iconSize];
}

- (void)setMergeHighlighted:(BOOL)mergeHighlighted {
    _mergeHighlighted = mergeHighlighted;
    self.shortcutContentView.mergeHighlighted = mergeHighlighted;
}

- (void)bindHandlers {
    __weak typeof(self) weakSelf = self;
    self.shortcutContentView.onActivate = ^(BrowserShortcutItem *item, BOOL openInNewTab) {
        if (weakSelf.onActivate) {
            weakSelf.onActivate(item, openInNewTab);
        }
    };
    self.shortcutContentView.onAddTapped = ^{
        if (weakSelf.onAddTapped) {
            weakSelf.onAddTapped();
        }
    };
}

- (void)setOnActivate:(BrowserShortcutCellActivateHandler)onActivate {
    _onActivate = [onActivate copy];
    [self bindHandlers];
}

- (void)setOnAddTapped:(dispatch_block_t)onAddTapped {
    _onAddTapped = [onAddTapped copy];
    [self bindHandlers];
}

@end
