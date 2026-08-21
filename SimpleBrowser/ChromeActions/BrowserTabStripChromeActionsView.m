#import "BrowserTabStripChromeActionsView.h"
#import "BrowserChromeActionItem.h"

static const CGFloat kChromeActionButtonSize = 22.0;
static const CGFloat kChromeActionSpacing = 2.0;
static const CGFloat kChromeActionSymbolPointSize = 12.0;

@interface BrowserTabStripChromeActionButton : NSButton
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, strong, nullable) BrowserChromeActionItem *actionItem;
@end

@implementation BrowserTabStripChromeActionButton
@end

@interface BrowserTabStripChromeActionsView ()
@property (nonatomic, copy, readwrite) NSArray<BrowserChromeActionItem *> *items;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserTabStripChromeActionButton *> *buttonsByID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *onStateByID;
@end

@implementation BrowserTabStripChromeActionsView

+ (NSArray<BrowserChromeActionItem *> *)defaultItems {
    return @[
        [BrowserChromeActionItem itemWithID:BrowserChromeActionAfkModeID
                                 symbolName:@"eye"
                               onSymbolName:@"eye.slash"
                                    toolTip:@"摸鱼模式"
                                  onToolTip:@"退出摸鱼模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionTransparentModeID
                                 symbolName:@"cube.transparent"
                               onSymbolName:@"cube.transparent"
                                    toolTip:@"透明模式"
                                  onToolTip:@"退出透明模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionCompactModeID
                                 symbolName:@"rectangle.topthird.inset.filled"
                               onSymbolName:@"rectangle.topthird.inset.filled"
                                    toolTip:@"精简模式"
                                  onToolTip:@"退出精简模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionAlwaysOnTopID
                                 symbolName:@"pin"
                               onSymbolName:@"pin.fill"
                                    toolTip:@"窗口置顶"
                                  onToolTip:@"取消置顶"
                                    toggles:YES],
    ];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _buttonsByID = [NSMutableDictionary dictionary];
        _onStateByID = [NSMutableDictionary dictionary];
        _items = @[];

        _stackView = [NSStackView stackViewWithViews:@[]];
        _stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _stackView.spacing = kChromeActionSpacing;
        _stackView.alignment = NSLayoutAttributeCenterY;
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],
        ]];

        [self reloadWithItems:[[self class] defaultItems]];
    }
    return self;
}

- (CGFloat)preferredWidth {
    NSUInteger count = self.items.count;
    if (count == 0) {
        return 0;
    }
    return count * kChromeActionButtonSize + (count - 1) * kChromeActionSpacing;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize([self preferredWidth], kChromeActionButtonSize);
}

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items {
    for (NSView *view in [self.stackView.views copy]) {
        [self.stackView removeView:view];
    }
    [self.buttonsByID removeAllObjects];

    self.items = [items copy] ?: @[];
    for (BrowserChromeActionItem *item in self.items) {
        BOOL on = [self.onStateByID[item.itemID] boolValue];
        BrowserTabStripChromeActionButton *button = [self makeButtonForItem:item on:on];
        self.buttonsByID[item.itemID] = button;
        [self.stackView addArrangedSubview:button];
    }

    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout:YES];
}

- (BrowserTabStripChromeActionButton *)makeButtonForItem:(BrowserChromeActionItem *)item on:(BOOL)on {
    BrowserTabStripChromeActionButton *button = [[BrowserTabStripChromeActionButton alloc] initWithFrame:NSZeroRect];
    button.itemID = item.itemID;
    button.actionItem = item;
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    // 开态由 setOn:forItemID: 管理，避免 NSButtonTypeToggle 与 action 双翻
    button.buttonType = NSButtonTypeMomentaryChange;

    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kChromeActionButtonSize],
        [button.heightAnchor constraintEqualToConstant:kChromeActionButtonSize],
    ]];

    [self applyAppearanceToButton:button item:item on:on];
    return button;
}

- (NSImage *)symbolImageNamed:(NSString *)symbolName {
    if (symbolName.length == 0) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:kChromeActionSymbolPointSize
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (image) {
            return [image imageWithSymbolConfiguration:config];
        }
    }
    return nil;
}

- (void)applyAppearanceToButton:(BrowserTabStripChromeActionButton *)button
                           item:(BrowserChromeActionItem *)item
                             on:(BOOL)on {
    NSString *symbol = (on && item.onSymbolName.length > 0) ? item.onSymbolName : item.symbolName;
    NSImage *image = [self symbolImageNamed:symbol];
    if (image) {
        button.image = image;
        button.title = @"";
    } else {
        button.image = nil;
        button.title = on ? @"●" : @"○";
    }

    NSString *tip = (on && item.onToolTip.length > 0) ? item.onToolTip : item.toolTip;
    button.toolTip = tip;
    button.accessibilityLabel = tip;
    if (@available(macOS 10.10, *)) {
        button.accessibilityValue = on ? @"开" : @"关";
    }

    button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = on ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    }
}

- (nullable NSButton *)buttonForItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return nil;
    }
    return self.buttonsByID[itemID];
}

- (void)setOn:(BOOL)on forItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    self.onStateByID[itemID] = @(on);
    BrowserTabStripChromeActionButton *button = self.buttonsByID[itemID];
    BrowserChromeActionItem *item = button.actionItem;
    if (!button || !item) {
        return;
    }
    [self applyAppearanceToButton:button item:item on:on];
}

- (BOOL)isOnForItemID:(NSString *)itemID {
    if (itemID.length == 0) {
        return NO;
    }
    return [self.onStateByID[itemID] boolValue];
}

@end
