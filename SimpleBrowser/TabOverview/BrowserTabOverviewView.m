#import "BrowserTabOverviewView.h"
#import "BrowserTabOverviewCardView.h"
#import "BrowserTabItemView.h"
#import "SBTextField.h"

static const CGFloat kTopBarHeight = 48.0;
static const CGFloat kGridInset = 24.0;
static const CGFloat kCardSpacing = 18.0;
static const CGFloat kMaxCardWidth = 320.0;

@interface BrowserTabOverviewGridDocumentView : NSView
@property (nonatomic, weak) BrowserTabOverviewView *owner;
@end

@implementation BrowserTabOverviewGridDocumentView
- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSView *sub in self.subviews) {
        if (!sub.hidden && NSPointInRect(p, sub.frame)) {
            return;
        }
    }
    [self.owner.delegate tabOverviewViewDidClickBackground:self.owner];
}
@end

@interface BrowserTabOverviewView () <NSTextFieldDelegate>
@property (nonatomic, strong) NSView *topBar;
@property (nonatomic, strong, readwrite) NSTextField *titleLabel;
@property (nonatomic, strong, readwrite) SBTextField *searchField;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong, readwrite) NSScrollView *scrollView;
@property (nonatomic, strong, readwrite) NSView *gridDocumentView;
@property (nonatomic, strong, readwrite) NSTextField *emptyLabel;
@property (nonatomic, strong) NSMutableArray<BrowserTabOverviewCardView *> *mutableCards;
@property (nonatomic, assign) NSUInteger tabCount;
@end

@implementation BrowserTabOverviewView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _mutableCards = [NSMutableArray array];

        _topBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _topBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_topBar];

        _titleLabel = [NSTextField labelWithString:@"标签概览"];
        _titleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_topBar addSubview:_titleLabel];

        _searchField = [SBTextField standardField];
        _searchField.placeholderString = @"搜索标签";
        _searchField.delegate = self;
        _searchField.translatesAutoresizingMaskIntoConstraints = NO;
        [_topBar addSubview:_searchField];

        _addTabButton = [NSButton buttonWithTitle:@"＋" target:self action:@selector(newTabClicked:)];
        _addTabButton.bezelStyle = NSBezelStyleInline;
        _addTabButton.bordered = NO;
        _addTabButton.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
        _addTabButton.toolTip = @"新建标签页";
        _addTabButton.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 10.14, *)) {
            _addTabButton.contentTintColor = [NSColor secondaryLabelColor];
        }
        [_topBar addSubview:_addTabButton];

        _closeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeClicked:)];
        _closeButton.bezelStyle = NSBezelStyleInline;
        _closeButton.bordered = NO;
        _closeButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        _closeButton.toolTip = @"关闭概览";
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 10.14, *)) {
            _closeButton.contentTintColor = [NSColor secondaryLabelColor];
        }
        [_topBar addSubview:_closeButton];

        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = NO;
        _scrollView.autohidesScrollers = YES;
        _scrollView.borderType = NSNoBorder;
        _scrollView.drawsBackground = NO;
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_scrollView];

        _gridDocumentView = [[BrowserTabOverviewGridDocumentView alloc] initWithFrame:NSZeroRect];
        _gridDocumentView.wantsLayer = YES;
        ((BrowserTabOverviewGridDocumentView *)_gridDocumentView).owner = self;
        _scrollView.documentView = _gridDocumentView;

        _emptyLabel = [NSTextField labelWithString:@"无匹配标签"];
        _emptyLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        _emptyLabel.textColor = [NSColor secondaryLabelColor];
        _emptyLabel.alignment = NSTextAlignmentCenter;
        _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _emptyLabel.hidden = YES;
        [self addSubview:_emptyLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_topBar.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_topBar.heightAnchor constraintEqualToConstant:kTopBarHeight],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_topBar.leadingAnchor constant:24],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],

            [_closeButton.trailingAnchor constraintEqualToAnchor:_topBar.trailingAnchor constant:-16],
            [_closeButton.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:28],
            [_closeButton.heightAnchor constraintEqualToConstant:28],

            [_addTabButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4],
            [_addTabButton.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
            [_addTabButton.widthAnchor constraintEqualToConstant:28],
            [_addTabButton.heightAnchor constraintEqualToConstant:28],

            [_searchField.trailingAnchor constraintEqualToAnchor:_addTabButton.leadingAnchor constant:-12],
            [_searchField.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
            [_searchField.widthAnchor constraintEqualToConstant:220],
            [_searchField.heightAnchor constraintEqualToConstant:28],
            [_searchField.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:16],

            [_scrollView.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:12],
        ]];

        [self applyBackground];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyBackground];
}

- (void)applyBackground {
    BOOL dark = [[NSApp effectiveAppearance].name containsString:@"Dark"];
    NSColor *fill = dark
        ? [NSColor colorWithCalibratedWhite:0.14 alpha:0.97]
        : [BrowserTabActiveFillColor() colorWithAlphaComponent:0.97];
    self.layer.backgroundColor = fill.CGColor;
}

- (void)setTabCount:(NSUInteger)count {
    _tabCount = count;
    self.titleLabel.stringValue = [NSString stringWithFormat:@"标签概览 · %lu 个", (unsigned long)count];
}

- (void)setEmptyVisible:(BOOL)visible {
    self.emptyLabel.hidden = !visible;
    self.scrollView.hidden = visible;
}

- (void)focusSearchField {
    [self.window makeFirstResponder:self.searchField];
}

- (NSArray<BrowserTabOverviewCardView *> *)cardViews {
    return [self.mutableCards copy];
}

- (void)setCardViews:(NSArray<BrowserTabOverviewCardView *> *)cards {
    for (NSView *sub in [self.mutableCards copy]) {
        [sub removeFromSuperview];
    }
    [self.mutableCards removeAllObjects];
    [self.mutableCards addObjectsFromArray:cards ?: @[]];
    for (BrowserTabOverviewCardView *card in self.mutableCards) {
        card.translatesAutoresizingMaskIntoConstraints = YES;
        [self.gridDocumentView addSubview:card];
    }
    [self relayoutGrid];
}

- (NSUInteger)columnCountForWidth:(CGFloat)width {
    if (width < 720) {
        return 2;
    }
    if (width < 1100) {
        return 3;
    }
    if (width < 1600) {
        return 4;
    }
    return 5;
}

- (void)relayoutGrid {
    NSRect visible = self.scrollView.contentView.bounds;
    CGFloat contentWidth = MAX(visible.size.width, 200);
    NSUInteger columns = [self columnCountForWidth:contentWidth];
    CGFloat available = contentWidth - kGridInset * 2 - kCardSpacing * (columns - 1);
    CGFloat cardWidth = MIN(kMaxCardWidth, floor(available / columns));
    CGFloat cardHeight = BrowserTabOverviewCardHeightForWidth(cardWidth);
    CGFloat usedWidth = columns * cardWidth + (columns - 1) * kCardSpacing;
    CGFloat originX = kGridInset + MAX(0, (contentWidth - kGridInset * 2 - usedWidth) / 2.0);

    NSUInteger count = self.mutableCards.count;
    NSUInteger rows = count == 0 ? 0 : (count + columns - 1) / columns;
    CGFloat docHeight = kGridInset * 2 + rows * cardHeight + (rows > 0 ? (rows - 1) * kCardSpacing : 0);
    docHeight = MAX(docHeight, visible.size.height);

    // AppKit flipped document: y increases upward; place from top.
    self.gridDocumentView.frame = NSMakeRect(0, 0, contentWidth, docHeight);

    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger row = i / columns;
        NSUInteger col = i % columns;
        CGFloat x = originX + col * (cardWidth + kCardSpacing);
        CGFloat yFromTop = kGridInset + row * (cardHeight + kCardSpacing);
        CGFloat y = docHeight - yFromTop - cardHeight;
        self.mutableCards[i].frame = NSMakeRect(x, y, cardWidth, cardHeight);
    }
}

- (void)layout {
    [super layout];
    [self relayoutGrid];
}

- (void)closeClicked:(id)sender {
    (void)sender;
    [self.delegate tabOverviewViewDidRequestClose:self];
}

- (void)newTabClicked:(id)sender {
    (void)sender;
    [self.delegate tabOverviewViewDidRequestNewTab:self];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    (void)obj;
    [self.delegate tabOverviewView:self searchQueryDidChange:self.searchField.stringValue ?: @""];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.topBar.frame)) {
        return;
    }
    // Only treat as background if not on a card (cards are in scroll document coords).
    NSPoint inScroll = [self.scrollView convertPoint:event.locationInWindow fromView:nil];
    NSPoint inDoc = [self.gridDocumentView convertPoint:inScroll fromView:self.scrollView];
    for (BrowserTabOverviewCardView *card in self.mutableCards) {
        if (NSPointInRect(inDoc, card.frame)) {
            return;
        }
    }
    [self.delegate tabOverviewViewDidClickBackground:self];
}

@end
