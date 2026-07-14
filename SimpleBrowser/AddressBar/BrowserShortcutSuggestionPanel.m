#import "BrowserShortcutSuggestionPanel.h"
#import "BrowserShortcutItem.h"
#import "BrowserFaviconService.h"

@class BrowserShortcutSuggestionRowView;

@interface BrowserShortcutSuggestionPanel (RowActions)
- (void)suggestionRowClicked:(BrowserShortcutSuggestionRowView *)row;
- (void)suggestionRowMiddleClicked:(BrowserShortcutSuggestionRowView *)row;
- (void)suggestionRowHovered:(BrowserShortcutSuggestionRowView *)row;
@end

@interface BrowserFlippedRowsContainer : NSView
@end

@implementation BrowserFlippedRowsContainer

- (BOOL)isFlipped {
    return YES;
}

@end

static const CGFloat kRowHeight = 36.0;
static const CGFloat kPanelCornerRadius = 8.0;
static const CGFloat kPanelMaxVisibleRows = 8.0;
static const CGFloat kIconSize = 20.0;
static const CGFloat kIconCornerRadius = 4.0;

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

static NSString *DisplayHostForShortcut(BrowserShortcutItem *item) {
    NSURL *url = [NSURL URLWithString:item.urlString];
    NSString *host = url.host ?: item.urlString;
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return host;
}

static NSAttributedString *HighlightedString(NSString *text, NSString *query, NSFont *font, NSColor *color) {
    if (text.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text
                                                                               attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
    }];
    if (query.length == 0) {
        return result;
    }

    NSString *lowercaseText = text.lowercaseString;
    NSString *lowercaseQuery = query.lowercaseString;
    NSRange searchRange = NSMakeRange(0, lowercaseText.length);
    while (searchRange.length > 0) {
        NSRange found = [lowercaseText rangeOfString:lowercaseQuery options:0 range:searchRange];
        if (found.location == NSNotFound) {
            break;
        }
        [result addAttribute:NSForegroundColorAttributeName value:[NSColor controlAccentColor] range:found];
        NSFont *boldFont = [NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSFontBoldTrait];
        [result addAttribute:NSFontAttributeName value:boldFont range:found];
        NSUInteger nextLocation = NSMaxRange(found);
        if (nextLocation >= lowercaseText.length) {
            break;
        }
        searchRange = NSMakeRange(nextLocation, lowercaseText.length - nextLocation);
    }
    return result;
}

@interface BrowserShortcutSuggestionIconView : NSView
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSTextField *letterLabel;
@property (nonatomic, copy) NSString *loadToken;
@end

@implementation BrowserShortcutSuggestionIconView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = kIconCornerRadius;
        self.layer.masksToBounds = YES;

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _imageView.hidden = YES;
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_imageView];

        _letterLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _letterLabel.editable = NO;
        _letterLabel.selectable = NO;
        _letterLabel.bezeled = NO;
        _letterLabel.drawsBackground = NO;
        _letterLabel.alignment = NSTextAlignmentCenter;
        _letterLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _letterLabel.textColor = [NSColor whiteColor];
        _letterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_letterLabel];

        [NSLayoutConstraint activateConstraints:@[
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

- (void)configureWithItem:(BrowserShortcutItem *)item {
    self.layer.backgroundColor = ColorFromURLString(item.urlString).CGColor;
    self.letterLabel.stringValue = DisplayLetterForShortcut(item);
    self.imageView.hidden = YES;
    self.letterLabel.hidden = NO;

    // 补全行不主动打第三方瀑布，仅用磁盘缓存 / 已有 iconURL（避免输入时风暴）。
    NSString *token = item.urlString ?: @"";
    self.loadToken = token;
    NSString *preferred = item.iconURLString.length > 0 ? item.iconURLString : nil;

    __weak typeof(self) weakSelf = self;
    [[BrowserFaviconService sharedService] imageForPageURLString:item.urlString
                                                 preferredIconURL:preferred
                                                      triggerFetch:NO
                                                        completion:^(NSImage *image) {
        BrowserShortcutSuggestionIconView *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.loadToken isEqualToString:token] || !image) {
            return;
        }
        strongSelf.imageView.image = image;
        strongSelf.imageView.hidden = NO;
        strongSelf.letterLabel.hidden = YES;
        strongSelf.layer.backgroundColor = NSColor.clearColor.CGColor;
    }];
}

@end

@interface BrowserShortcutSuggestionRowView : NSView
@property (nonatomic, strong) BrowserShortcutSuggestionIconView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *hostLabel;
@property (nonatomic, assign) NSUInteger rowIndex;
@property (nonatomic, assign, getter=isRowSelected) BOOL rowSelected;
@property (nonatomic, weak) BrowserShortcutSuggestionPanel *panel;
@end

@implementation BrowserShortcutSuggestionRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _iconView = [[BrowserShortcutSuggestionIconView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.bezeled = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.font = [NSFont systemFontOfSize:13];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _hostLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _hostLabel.editable = NO;
        _hostLabel.selectable = NO;
        _hostLabel.bezeled = NO;
        _hostLabel.drawsBackground = NO;
        _hostLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _hostLabel.font = [NSFont systemFontOfSize:11];
        _hostLabel.textColor = [NSColor secondaryLabelColor];
        _hostLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_hostLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:kIconSize],
            [_iconView.heightAnchor constraintEqualToConstant:kIconSize],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_hostLabel.leadingAnchor constant:-8],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-1],
            [_hostLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_hostLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_hostLabel.widthAnchor constraintGreaterThanOrEqualToConstant:80],
        ]];
    }
    return self;
}

- (void)setRowSelected:(BOOL)rowSelected {
    _rowSelected = rowSelected;
    if (rowSelected) {
        self.layer.backgroundColor = [[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.85].CGColor;
        self.layer.cornerRadius = 6.0;
    } else {
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
    }
}

- (void)configureWithItem:(BrowserShortcutItem *)item query:(NSString *)query {
    self.titleLabel.attributedStringValue = HighlightedString(item.title, query, self.titleLabel.font, self.titleLabel.textColor);
    self.hostLabel.attributedStringValue = HighlightedString(DisplayHostForShortcut(item), query, self.hostLabel.font, self.hostLabel.textColor);
    [self.iconView configureWithItem:item];
    self.toolTip = [NSString stringWithFormat:@"%@ — %@", item.title, item.urlString];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", item.title, DisplayHostForShortcut(item)];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                         options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                           owner:self
                                                        userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseDown:(NSEvent *)event {
    if (event.buttonNumber == 2) {
        [self.panel suggestionRowMiddleClicked:self];
        return;
    }
    [self.panel suggestionRowClicked:self];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    [self.panel suggestionRowHovered:self];
}

@end

@interface BrowserShortcutSuggestionPanel ()
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *rowsContainer;
@property (nonatomic, copy) NSArray<BrowserShortcutItem *> *items;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) NSMutableArray<BrowserShortcutSuggestionRowView *> *rowViews;
@end

@implementation BrowserShortcutSuggestionPanel

- (instancetype)init {
    self = [super initWithContentRect:NSZeroRect
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.hasShadow = YES;
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.level = NSPopUpMenuWindowLevel;
        self.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        if (@available(macOS 10.14, *)) {
            self.appearance = NSApp.effectiveAppearance;
        }
        if (@available(macOS 10.12, *)) {
            self.hidesOnDeactivate = NO;
        }

        _effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
        _effectView.material = NSVisualEffectMaterialPopover;
        _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _effectView.state = NSVisualEffectStateActive;
        _effectView.wantsLayer = YES;
        _effectView.layer.cornerRadius = kPanelCornerRadius;
        _effectView.layer.masksToBounds = YES;
        _effectView.translatesAutoresizingMaskIntoConstraints = NO;

        _rowsContainer = [[BrowserFlippedRowsContainer alloc] initWithFrame:NSZeroRect];
        _rowsContainer.translatesAutoresizingMaskIntoConstraints = NO;

        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.drawsBackground = NO;
        _scrollView.borderType = NSNoBorder;
        _scrollView.documentView = _rowsContainer;
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;

        NSView *contentView = [[NSView alloc] initWithFrame:NSZeroRect];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentView = contentView;
        [contentView addSubview:_effectView];
        [_effectView addSubview:_scrollView];

        [NSLayoutConstraint activateConstraints:@[
            [_effectView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [_effectView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [_effectView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [_effectView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [_scrollView.topAnchor constraintEqualToAnchor:_effectView.topAnchor constant:4],
            [_scrollView.leadingAnchor constraintEqualToAnchor:_effectView.leadingAnchor constant:4],
            [_scrollView.trailingAnchor constraintEqualToAnchor:_effectView.trailingAnchor constant:-4],
            [_scrollView.bottomAnchor constraintEqualToAnchor:_effectView.bottomAnchor constant:-4],
        ]];

        _rowViews = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)updateWithItems:(NSArray<BrowserShortcutItem *> *)items
                  query:(NSString *)query
         selectedIndex:(NSUInteger)selectedIndex
            anchorRect:(NSRect)anchorRectOnScreen {
    self.items = items;
    self.query = query;
    self.selectedIndex = selectedIndex;

    for (NSView *subview in self.rowViews) {
        [subview removeFromSuperview];
    }
    [self.rowViews removeAllObjects];

    CGFloat width = NSWidth(anchorRectOnScreen);
    CGFloat contentHeight = items.count * kRowHeight;
    CGFloat visibleHeight = MIN(contentHeight, kPanelMaxVisibleRows * kRowHeight);
    CGFloat panelHeight = visibleHeight + 8.0;

    self.rowsContainer.frame = NSMakeRect(0, 0, width - 8.0, MAX(contentHeight, visibleHeight));

    for (NSUInteger i = 0; i < items.count; i++) {
        NSRect rowFrame = NSMakeRect(0, i * kRowHeight, width - 8.0, kRowHeight);
        BrowserShortcutSuggestionRowView *row = [[BrowserShortcutSuggestionRowView alloc] initWithFrame:rowFrame];
        row.rowIndex = i;
        row.panel = self;
        [row configureWithItem:items[i] query:query];
        row.rowSelected = (i == selectedIndex);
        [self.rowsContainer addSubview:row];
        [self.rowViews addObject:row];
    }

    NSRect panelFrame = NSMakeRect(anchorRectOnScreen.origin.x,
                                   anchorRectOnScreen.origin.y - panelHeight - 4.0,
                                   width,
                                   panelHeight);
    [self setFrame:panelFrame display:YES];
    [self orderFrontRegardless];
}

- (void)dismissPanel {
    [self orderOut:nil];
}

- (void)suggestionRowClicked:(BrowserShortcutSuggestionRowView *)row {
    [self.suggestionDelegate suggestionPanelDidOpenItemAtIndex:row.rowIndex];
}

- (void)suggestionRowMiddleClicked:(BrowserShortcutSuggestionRowView *)row {
    [self.suggestionDelegate suggestionPanelDidOpenItemAtIndexInNewTab:row.rowIndex];
}

- (void)suggestionRowHovered:(BrowserShortcutSuggestionRowView *)row {
    [self.suggestionDelegate suggestionPanelDidHoverItemAtIndex:row.rowIndex];
}

- (void)setHighlightedIndex:(NSUInteger)index {
    self.selectedIndex = index;
    [self updateSelectionHighlight];
}

- (void)updateSelectionHighlight {
    for (BrowserShortcutSuggestionRowView *row in self.rowViews) {
        row.rowSelected = (row.rowIndex == self.selectedIndex);
    }
}

@end
