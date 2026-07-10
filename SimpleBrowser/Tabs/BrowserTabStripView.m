#import "BrowserTabStripView.h"
#import "BrowserTab.h"
#import "BrowserTabItemView.h"

const CGFloat BrowserTabStripHeight = 36.0;

static const CGFloat kTrafficLightLeadingInset = 78.0;
static const CGFloat kTabTopInset = 3.0;

@class BrowserTabStripView;

@interface BrowserTabStripView (TitleBarInteraction)
- (void)handleTitleBarDoubleClick;
@end

@interface BrowserTabStripDragAreaView : NSView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripDragAreaView

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

@end

@interface BrowserTabStripStackView : NSStackView
@property (nonatomic, weak) BrowserTabStripView *stripView;
@end

@implementation BrowserTabStripStackView

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self.stripView handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

@end

@interface BrowserTabStripView ()
@property (nonatomic, strong) NSView *backgroundView;
@property (nonatomic, strong) NSView *leadingDragArea;
@property (nonatomic, strong) NSView *trailingDragArea;
@property (nonatomic, strong) NSStackView *tabsStackView;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSMapTable<BrowserTabItemView *, NSUUID *> *tabItemIDs;
@end

@implementation BrowserTabStripView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;

        _tabItemIDs = [NSMapTable weakToStrongObjectsMapTable];

        _backgroundView = [[BrowserTabStripDragAreaView alloc] init];
        _backgroundView.wantsLayer = YES;
        _backgroundView.translatesAutoresizingMaskIntoConstraints = NO;

        _leadingDragArea = [[BrowserTabStripDragAreaView alloc] init];
        _leadingDragArea.translatesAutoresizingMaskIntoConstraints = NO;

        _tabsStackView = [[BrowserTabStripStackView alloc] init];
        _tabsStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _tabsStackView.spacing = 2;
        _tabsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _tabsStackView.alignment = NSLayoutAttributeBottom;
        [_tabsStackView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_tabsStackView setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

        _addTabButton = [self newTabButton];
        _addTabButton.translatesAutoresizingMaskIntoConstraints = NO;

        _trailingDragArea = [[BrowserTabStripDragAreaView alloc] init];
        _trailingDragArea.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_backgroundView];
        [self addSubview:_leadingDragArea];
        [self addSubview:_tabsStackView];
        [self addSubview:_addTabButton];
        [self addSubview:_trailingDragArea];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],

            [_backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_leadingDragArea.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_leadingDragArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_leadingDragArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_leadingDragArea.widthAnchor constraintEqualToConstant:kTrafficLightLeadingInset],

            [_tabsStackView.leadingAnchor constraintEqualToAnchor:_leadingDragArea.trailingAnchor constant:4],
            [_tabsStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_tabsStackView.trailingAnchor constraintEqualToAnchor:_addTabButton.leadingAnchor constant:-6],
            [_tabsStackView.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],

            [_addTabButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_addTabButton.widthAnchor constraintEqualToConstant:24],
            [_addTabButton.heightAnchor constraintEqualToConstant:24],

            [_trailingDragArea.leadingAnchor constraintEqualToAnchor:_addTabButton.trailingAnchor constant:4],
            [_trailingDragArea.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_trailingDragArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_trailingDragArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_trailingDragArea.widthAnchor constraintGreaterThanOrEqualToConstant:16],
        ]];

        ((BrowserTabStripDragAreaView *)_backgroundView).stripView = self;
        ((BrowserTabStripDragAreaView *)_leadingDragArea).stripView = self;
        ((BrowserTabStripDragAreaView *)_trailingDragArea).stripView = self;
        ((BrowserTabStripStackView *)_tabsStackView).stripView = self;

        [self updateStripAppearance];
    }
    return self;
}

- (void)handleTitleBarDoubleClick {
    id<BrowserTabStripViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabStripViewDidDoubleClickTitleBar:)]) {
        [delegate tabStripViewDidDoubleClickTitleBar:self];
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateStripAppearance];
}

- (void)updateStripAppearance {
    BOOL dark = [self effectiveAppearanceIsDark];
    NSColor *strip = dark ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
                          : [NSColor colorWithCalibratedRed:0.87 green:0.88 blue:0.91 alpha:1.0];
    self.backgroundView.layer.backgroundColor = strip.CGColor;
}

- (BOOL)effectiveAppearanceIsDark {
    NSString *name = self.effectiveAppearance.name;
    return [name containsString:@"Dark"];
}

- (NSButton *)newTabButton {
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:14
                                                            weight:NSFontWeightSemibold
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"新建标签页"];
        if (symbol) {
            image = [symbol imageWithSymbolConfiguration:config];
        }
    }

    NSButton *button = image ? [NSButton buttonWithImage:image target:self action:@selector(onNewTab:)]
                             : [NSButton buttonWithTitle:@"+" target:self action:@selector(onNewTab:)];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"新建标签页";
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    return button;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.clickCount == 2) {
        [self handleTitleBarDoubleClick];
        return;
    }
    [super mouseDown:event];
}

- (NSView *)wrapTabItem:(BrowserTabItemView *)item {
    NSView *slot = [[NSView alloc] init];
    slot.translatesAutoresizingMaskIntoConstraints = NO;
    [slot addSubview:item];

    [NSLayoutConstraint activateConstraints:@[
        [slot.widthAnchor constraintEqualToConstant:160],
        [slot.heightAnchor constraintEqualToConstant:BrowserTabStripHeight],
        [item.leadingAnchor constraintEqualToAnchor:slot.leadingAnchor],
        [item.trailingAnchor constraintEqualToAnchor:slot.trailingAnchor],
        [item.topAnchor constraintEqualToAnchor:slot.topAnchor constant:kTabTopInset],
        [item.bottomAnchor constraintEqualToAnchor:slot.bottomAnchor],
    ]];

    return slot;
}

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID {
    for (NSView *view in self.tabsStackView.arrangedSubviews) {
        [self.tabsStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.tabItemIDs removeAllObjects];

    for (BrowserTab *tab in tabs) {
        BOOL selected = [tab.tabID isEqual:selectedTabID];
        BrowserTabItemView *item = [[BrowserTabItemView alloc] initWithFrame:NSZeroRect];
        item.tabTitle = [tab displayTitle];
        item.tabSelected = selected;

        __weak typeof(self) weakSelf = self;
        NSUUID *tabID = tab.tabID;
        item.onSelect = ^{
            [weakSelf.delegate tabStripView:weakSelf didSelectTabID:tabID];
        };
        item.onClose = ^{
            [weakSelf.delegate tabStripView:weakSelf didCloseTabID:tabID];
        };

        [self.tabItemIDs setObject:tab.tabID forKey:item];
        [self.tabsStackView addArrangedSubview:[self wrapTabItem:item]];
    }

    [self.tabsStackView layoutSubtreeIfNeeded];
    [self setNeedsLayout:YES];
}

- (void)onNewTab:(id)sender {
    (void)sender;
    [self.delegate tabStripViewDidRequestNewTab:self];
}

@end
