#import "BrowserShortcutCellView.h"
#import "BrowserShortcutItem.h"
#import "BrowserLaunchpadAppearance.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kIconShadowBlur = 6.0;
static const CGFloat kIconShadowOffsetY = -2.0;
static const CGFloat kIconShadowAlpha = 0.22;
static const CGFloat kHoverScale = 1.05;
static const NSTimeInterval kHoverAnimationDuration = 0.15;
static const NSTimeInterval kLongPressDuration = 0.5;
static NSString * const kWiggleAnimationKey = @"launchpadWiggle";

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

@interface BrowserShortcutCellContentView : NSView
@property (nonatomic, strong) NSView *iconAnimContainer;
@property (nonatomic, strong) BrowserShortcutIconBackdropView *iconBackdropView;
@property (nonatomic, strong) NSImageView *iconImageView;
@property (nonatomic, strong) NSTextField *letterLabel;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, copy, nullable) BrowserShortcutCellActivateHandler onActivate;
@property (nonatomic, copy, nullable) BrowserShortcutCellActionHandler onDelete;
@property (nonatomic, copy, nullable) dispatch_block_t onAddTapped;
@property (nonatomic, copy, nullable) dispatch_block_t onRequestEditMode;
@property (nonatomic, strong, nullable) BrowserShortcutItem *shortcut;
@property (nonatomic, assign, getter=isEditingMode) BOOL editingMode;
@property (nonatomic, assign, getter=isAddCell) BOOL addCell;
@property (nonatomic, assign) BOOL trackingHover;
@property (nonatomic, strong, nullable) NSTimer *longPressTimer;
@property (nonatomic, assign) BOOL longPressTriggered;
@property (nonatomic, assign) NSUInteger iconLoadToken;
@property (nonatomic, assign) CGFloat iconSize;
@property (nonatomic, strong) NSLayoutConstraint *cellWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cellHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconContainerWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconContainerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *deleteTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *deleteLeadingConstraint;
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

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.font = [NSFont systemFontOfSize:13];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.alignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _deleteButton = [NSButton buttonWithTitle:@"×" target:self action:@selector(onDelete:)];
        _deleteButton.bezelStyle = NSBezelStyleInline;
        _deleteButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];
        _deleteButton.hidden = YES;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_deleteButton];

        CGFloat cellWidth = [BrowserLaunchpadAppearance cellWidthForIconSize:_iconSize];
        CGFloat cellHeight = [BrowserLaunchpadAppearance cellHeightForIconSize:_iconSize];
        CGFloat shadowInset = [BrowserLaunchpadAppearance iconShadowInsetForIconSize:_iconSize];
        CGFloat iconContainerSize = _iconSize + shadowInset * 2.0;
        CGFloat cornerRadius = [BrowserLaunchpadAppearance iconCornerRadiusForIconSize:_iconSize];
        _iconImageView.layer.cornerRadius = cornerRadius;
        _iconBackdropView.cornerRadius = cornerRadius;
        _iconBackdropView.shadowInset = shadowInset;

        _cellWidthConstraint = [self.widthAnchor constraintEqualToConstant:cellWidth];
        _cellHeightConstraint = [self.heightAnchor constraintEqualToConstant:cellHeight];
        _iconContainerWidthConstraint = [_iconAnimContainer.widthAnchor constraintEqualToConstant:iconContainerSize];
        _iconContainerHeightConstraint = [_iconAnimContainer.heightAnchor constraintEqualToConstant:iconContainerSize];
        _iconWidthConstraint = [_iconImageView.widthAnchor constraintEqualToConstant:_iconSize];
        _iconHeightConstraint = [_iconImageView.heightAnchor constraintEqualToConstant:_iconSize];
        _deleteTopConstraint = [_deleteButton.topAnchor constraintEqualToAnchor:_iconAnimContainer.topAnchor
                                                                      constant:shadowInset - 4];
        _deleteLeadingConstraint = [_deleteButton.leadingAnchor constraintEqualToAnchor:_iconAnimContainer.leadingAnchor
                                                                               constant:shadowInset - 4];

        [NSLayoutConstraint activateConstraints:@[
            _cellWidthConstraint,
            _cellHeightConstraint,

            _iconContainerWidthConstraint,
            _iconContainerHeightConstraint,
            // 阴影可画出 cell 左右边界，使「左右间距」直接作用在可视图标之间。
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

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconAnimContainer.bottomAnchor constant:2],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],

            _deleteTopConstraint,
            _deleteLeadingConstraint,
            [_deleteButton.widthAnchor constraintEqualToConstant:18],
            [_deleteButton.heightAnchor constraintEqualToConstant:18],
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
    self.deleteTopConstraint.constant = shadowInset - 4;
    self.deleteLeadingConstraint.constant = shadowInset - 4;
    self.iconImageView.layer.cornerRadius = cornerRadius;
    self.iconBackdropView.cornerRadius = cornerRadius;
    self.iconBackdropView.shadowInset = shadowInset;
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
        if (!strongSelf || strongSelf.iconLoadToken != token) {
            return;
        }
        if (image) {
            [strongSelf applyLoadedIconImage:image];
        }
    }];
}

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut {
    self.addCell = NO;
    self.shortcut = shortcut;
    self.titleLabel.stringValue = shortcut.title;
    self.titleLabel.hidden = NO;
    [self loadIconForShortcut:shortcut];
    [self applyEditingChrome];
}

- (void)configureAsAddCell {
    self.addCell = YES;
    self.shortcut = nil;
    self.iconLoadToken += 1;
    self.iconImageView.image = nil;
    self.iconImageView.hidden = YES;
    self.letterLabel.stringValue = @"+";
    self.titleLabel.stringValue = @"添加";
    self.letterLabel.hidden = NO;
    self.titleLabel.hidden = NO;
    self.letterLabel.textColor = [NSColor secondaryLabelColor];
    [self updateIconFillColor:NSColor.quaternaryLabelColor];
    [self applyEditingChrome];
}

- (void)setEditingMode:(BOOL)editingMode {
    _editingMode = editingMode;
    [self applyEditingChrome];
}

- (void)applyEditingChrome {
    self.deleteButton.hidden = !(self.editingMode && !self.addCell);
    if (self.editingMode) {
        [self setHoverScale:1.0 animated:NO];
        [self startWiggle];
    } else {
        [self stopWiggle];
    }
}

- (void)startWiggle {
    if (self.addCell) {
        return;
    }
    if ([self.iconAnimContainer.layer animationForKey:kWiggleAnimationKey]) {
        return;
    }
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.values = @[@(-0.03), @(0.03), @(-0.03)];
    animation.duration = 0.16;
    animation.repeatCount = HUGE_VALF;
    animation.autoreverses = YES;
    [self.iconAnimContainer.layer addAnimation:animation forKey:kWiggleAnimationKey];
}

- (void)stopWiggle {
    [self.iconAnimContainer.layer removeAnimationForKey:kWiggleAnimationKey];
}

- (void)setHoverScale:(CGFloat)scale animated:(BOOL)animated {
    if (self.editingMode) {
        scale = 1.0;
    }
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
    if (!self.editingMode) {
        [self setHoverScale:kHoverScale animated:YES];
    }
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    [self setHoverScale:1.0 animated:YES];
}

- (void)dealloc {
    [self cancelLongPressTimer];
}

- (void)cancelLongPressTimer {
    [self.longPressTimer invalidate];
    self.longPressTimer = nil;
}

- (void)mouseDown:(NSEvent *)event {
    if (self.editingMode || self.addCell || event.type != NSEventTypeLeftMouseDown) {
        [super mouseDown:event];
        return;
    }

    self.longPressTriggered = NO;
    [self cancelLongPressTimer];
    __weak typeof(self) weakSelf = self;
    self.longPressTimer = [NSTimer scheduledTimerWithTimeInterval:kLongPressDuration
                                                          repeats:NO
                                                            block:^(NSTimer *timer) {
        (void)timer;
        BrowserShortcutCellContentView *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.editingMode || strongSelf.addCell) {
            return;
        }
        strongSelf.longPressTriggered = YES;
        [strongSelf cancelLongPressTimer];
        if (strongSelf.onRequestEditMode) {
            strongSelf.onRequestEditMode();
        }
    }];
}

- (void)mouseDragged:(NSEvent *)event {
    [self cancelLongPressTimer];
    [super mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self cancelLongPressTimer];
    if (self.longPressTriggered) {
        self.longPressTriggered = NO;
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) {
        return;
    }

    if (self.addCell) {
        if (self.onAddTapped) {
            self.onAddTapped();
        }
        return;
    }

    if (self.editingMode) {
        return;
    }

    if (!self.shortcut || !self.onActivate) {
        return;
    }
    BOOL openInNewTab = (event.buttonNumber == 2);
    self.onActivate(self.shortcut, openInNewTab);
}

- (void)onDelete:(id)sender {
    (void)sender;
    if (self.shortcut && self.onDelete) {
        self.onDelete(self.shortcut);
    }
}

@end

@interface BrowserShortcutCellView ()
@property (nonatomic, strong) BrowserShortcutCellContentView *shortcutContentView;
@end

@implementation BrowserShortcutCellView

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
    self.addCell = NO;
    self.shortcut = shortcut;
    [self.shortcutContentView applyIconSize:[BrowserLaunchpadAppearance current].iconSize];
    [self.shortcutContentView configureWithShortcut:shortcut];
    [self bindHandlers];
}

- (void)configureAsAddCell {
    self.addCell = YES;
    self.shortcut = nil;
    [self.shortcutContentView applyIconSize:[BrowserLaunchpadAppearance current].iconSize];
    [self.shortcutContentView configureAsAddCell];
    [self bindHandlers];
}

- (void)applyIconSize:(CGFloat)iconSize {
    [self.shortcutContentView applyIconSize:iconSize];
}

- (void)setEditingMode:(BOOL)editingMode {
    _editingMode = editingMode;
    self.shortcutContentView.editingMode = editingMode;
}

- (void)bindHandlers {
    __weak typeof(self) weakSelf = self;
    self.shortcutContentView.onActivate = ^(BrowserShortcutItem *item, BOOL openInNewTab) {
        if (weakSelf.onActivate) {
            weakSelf.onActivate(item, openInNewTab);
        }
    };
    self.shortcutContentView.onDelete = ^(BrowserShortcutItem *item) {
        if (weakSelf.onDelete) {
            weakSelf.onDelete(item);
        }
    };
    self.shortcutContentView.onAddTapped = ^{
        if (weakSelf.onAddTapped) {
            weakSelf.onAddTapped();
        }
    };
    self.shortcutContentView.onRequestEditMode = ^{
        if (weakSelf.onRequestEditMode) {
            weakSelf.onRequestEditMode();
        }
    };
}

- (void)setOnActivate:(BrowserShortcutCellActivateHandler)onActivate {
    _onActivate = [onActivate copy];
    [self bindHandlers];
}

- (void)setOnDelete:(BrowserShortcutCellActionHandler)onDelete {
    _onDelete = [onDelete copy];
    [self bindHandlers];
}

- (void)setOnAddTapped:(dispatch_block_t)onAddTapped {
    _onAddTapped = [onAddTapped copy];
    [self bindHandlers];
}

- (void)setOnRequestEditMode:(dispatch_block_t)onRequestEditMode {
    _onRequestEditMode = [onRequestEditMode copy];
    [self bindHandlers];
}

@end
