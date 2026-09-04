#import "BrowserTabItemView.h"
#import "BrowserFaviconService.h"
#import "BrowserFaviconUtil.h"
#import "BrowserShortcutIconPalette.h"

const CGFloat BrowserTabItemAbsoluteMinWidth = 32.0;
const CGFloat BrowserTabItemMinimalSelectedWidth = 48.0;
const CGFloat BrowserTabItemCompactMinWidth = 56.0;
const CGFloat BrowserTabItemCompactMaxWidth = 107.0;
const CGFloat BrowserTabItemComfortMinWidth = 108.0;
const CGFloat BrowserTabItemMinWidth = 108.0; // 历史别名，同 ComfortMinWidth
const CGFloat BrowserTabItemMaxWidth = 200.0;
const CGFloat BrowserTabActiveWidthBonus = 24.0;
const CGFloat BrowserTabFaviconSize = 16.0;
const CGFloat BrowserTabFaviconLeadingPad = 6.0;
const CGFloat BrowserTabFaviconTitleGap = 4.0;
/// 固定标签仍显示标题，宽度参与等宽分配时的最小宽与普通标签一致。
const CGFloat BrowserTabPinnedWidth = 108.0;

BrowserTabDisplayMode BrowserTabDisplayModeForWidth(CGFloat width, BOOL isSelected) {
    (void)isSelected; // TS-LRU-1：档位内关闭按钮策略可能区分选中
    if (width >= BrowserTabItemComfortMinWidth - 0.5) {
        return BrowserTabDisplayModeComfortable;
    }
    if (width >= BrowserTabItemCompactMinWidth - 0.5) {
        return BrowserTabDisplayModeCompact;
    }
    return BrowserTabDisplayModeMinimal;
}

static const CGFloat kCloseButtonWidth = 16.0;
static const CGFloat kCloseTrailingPad = 6.0;
static const CGFloat kCloseTitleGap = 4.0;
static const CGFloat kTitleTrailingPad = 8.0;
static const CGFloat kPinAfterFaviconGap = 4.0;
/// 提高阈值 + 时间门控，避免主线程卡顿时微抖把单击判成拖拽。
static const CGFloat kReorderDragThreshold = 10.0;
static const NSTimeInterval kReorderDragMinDuration = 0.15;
/// 单帧位移过大视为卡顿后的「瞬移」队列事件，重定起点而非开拖。
static const CGFloat kReorderDragTeleportReject = 48.0;
/// 需连续多帧超阈值才 commit，吸收主线程恢复后的突发 dragged。
static const NSInteger kReorderDragConfirmSamples = 2;
static const CGFloat kPinIconSize = 12.0;
static const NSTimeInterval kTabHoverTipDelay = 0.65;

static const CGFloat kDefaultTabHeight = 31.0;
static const CGFloat kCloseAlwaysVisibleMinWidth = 120.0;

/// 标题不参与命中，全部由标签本身接收拖拽
@interface BrowserTabTitleLabel : NSTextField
@end

@implementation BrowserTabTitleLabel
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

@interface BrowserTabPinIconView : NSImageView
@end

@implementation BrowserTabPinIconView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

@interface BrowserTabFaviconIconView : NSImageView
@end

@implementation BrowserTabFaviconIconView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}
@end

@interface BrowserTabFaviconLetterBadgeView : NSView
@property (nonatomic, strong) NSTextField *letterLabel;
@end

@implementation BrowserTabFaviconLetterBadgeView
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 3.0;
        if (@available(macOS 10.15, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        _letterLabel = [NSTextField labelWithString:@"?"];
        _letterLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold];
        _letterLabel.alignment = NSTextAlignmentCenter;
        _letterLabel.textColor = [NSColor whiteColor];
        _letterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_letterLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_letterLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_letterLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:0.5],
        ]];
    }
    return self;
}
@end

NSColor *BrowserTabActiveFillColor(void) {
    if ([[NSApp effectiveAppearance].name containsString:@"Dark"]) {
        return [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
    }
    return [NSColor whiteColor];
}

/// 标题栏 accessory 内系统 toolTip 基本不弹出；用共享浮层模拟 Chrome 悬停提示。
@interface BrowserTabHoverTipWindow : NSObject
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, weak) NSView *anchorView;
@property (nonatomic, copy, nullable) NSString *pendingText;
@property (nonatomic, strong, nullable) NSTimer *delayTimer;
+ (instancetype)shared;
- (void)scheduleText:(NSString *)text fromView:(NSView *)view;
- (void)cancelForView:(nullable NSView *)view;
- (void)hide;
@end

@implementation BrowserTabHoverTipWindow

+ (instancetype)shared {
    static BrowserTabHoverTipWindow *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrowserTabHoverTipWindow alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10)
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:YES];
        _panel.opaque = NO;
        _panel.backgroundColor = [NSColor clearColor];
        _panel.hasShadow = YES;
        _panel.level = NSFloatingWindowLevel;
        _panel.ignoresMouseEvents = YES;
        _panel.hidesOnDeactivate = YES;
        _panel.releasedWhenClosed = NO;

        NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
        root.wantsLayer = YES;
        root.layer.cornerRadius = 6.0;
        if (@available(macOS 10.15, *)) {
            root.layer.cornerCurve = kCACornerCurveContinuous;
        }

        _label = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _label.editable = NO;
        _label.selectable = NO;
        _label.bordered = NO;
        _label.drawsBackground = NO;
        _label.font = [NSFont systemFontOfSize:11];
        _label.maximumNumberOfLines = 6;
        _label.lineBreakMode = NSLineBreakByWordWrapping;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8],
            [_label.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-8],
            [_label.topAnchor constraintEqualToAnchor:root.topAnchor constant:6],
            [_label.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6],
        ]];
        _panel.contentView = root;
    }
    return self;
}

- (void)applyAppearance {
    BOOL dark = NO;
    NSAppearance *appearance = self.anchorView.effectiveAppearance ?: NSApp.effectiveAppearance;
    if ([appearance.name containsString:@"Dark"]) {
        dark = YES;
    }
    NSView *root = self.panel.contentView;
    if (dark) {
        root.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.18 alpha:0.96] CGColor];
        self.label.textColor = [NSColor whiteColor];
    } else {
        root.layer.backgroundColor = [[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.88 alpha:0.98] CGColor];
        self.label.textColor = [NSColor blackColor];
    }
    self.panel.appearance = appearance;
}

- (void)scheduleText:(NSString *)text fromView:(NSView *)view {
    if (text.length == 0 || view == nil || view.window == nil) {
        if (self.anchorView == view) {
            [self hide];
            self.anchorView = nil;
            self.pendingText = nil;
        }
        return;
    }

    // 同一锚点、同一文案：已显示或已在倒计时则不重置，避免 mouseMoved 抖掉 tip。
    if (self.anchorView == view && [self.pendingText isEqualToString:text]) {
        if (self.panel.isVisible || self.delayTimer != nil) {
            return;
        }
    }

    // 文案变化但 tip 已显示：立即更新内容。
    if (self.anchorView == view && self.panel.isVisible && self.delayTimer == nil) {
        self.pendingText = [text copy];
        [self displayText:text fromView:view];
        return;
    }

    [self cancelTimer];
    self.anchorView = view;
    self.pendingText = [text copy];
    __weak typeof(self) weakSelf = self;
    __weak NSView *weakView = view;
    NSString *payload = [text copy];
    self.delayTimer = [NSTimer timerWithTimeInterval:kTabHoverTipDelay
                                             repeats:NO
                                               block:^(NSTimer *timer) {
                                                   (void)timer;
                                                   [weakSelf displayText:payload fromView:weakView];
                                               }];
    [[NSRunLoop mainRunLoop] addTimer:self.delayTimer forMode:NSRunLoopCommonModes];
}

- (void)displayText:(NSString *)text fromView:(NSView *)view {
    if (view == nil || view != self.anchorView || view.window == nil || text.length == 0) {
        return;
    }
    NSPoint windowPoint = [view.window mouseLocationOutsideOfEventStream];
    NSPoint local = [view convertPoint:windowPoint fromView:nil];
    if (![view mouse:local inRect:view.bounds]) {
        [self hide];
        return;
    }

    self.label.stringValue = text;
    self.label.preferredMaxLayoutWidth = 420.0;
    [self applyAppearance];
    [self.label invalidateIntrinsicContentSize];
    NSSize labelSize = [self.label sizeThatFits:NSMakeSize(420.0, CGFLOAT_MAX)];
    CGFloat width = MIN(436.0, MAX(80.0, ceil(labelSize.width) + 16.0));
    CGFloat height = ceil(labelSize.height) + 12.0;
    [self.panel setContentSize:NSMakeSize(width, height)];

    NSRect viewRect = [view convertRect:view.bounds toView:nil];
    NSRect screenRect = [view.window convertRectToScreen:viewRect];
    CGFloat tipX = NSMidX(screenRect) - width * 0.5;
    CGFloat tipY = NSMinY(screenRect) - height - 6.0;
    NSScreen *screen = view.window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    if (tipX < NSMinX(visible) + 4) {
        tipX = NSMinX(visible) + 4;
    }
    if (tipX + width > NSMaxX(visible) - 4) {
        tipX = NSMaxX(visible) - width - 4;
    }
    if (tipY < NSMinY(visible) + 4) {
        tipY = NSMaxY(screenRect) + 6.0;
    }
    [self.panel setFrameOrigin:NSMakePoint(tipX, tipY)];
    NSWindow *parent = view.window;
    if (parent) {
        NSInteger minLevel = (NSInteger)parent.level + 1;
        if ((NSInteger)self.panel.level < minLevel) {
            self.panel.level = (NSWindowLevel)minLevel;
        }
    }
    [self.panel orderFront:nil];
}

- (void)cancelTimer {
    [self.delayTimer invalidate];
    self.delayTimer = nil;
}

- (void)cancelForView:(NSView *)view {
    if (view != nil && self.anchorView != view) {
        return;
    }
    [self cancelTimer];
    [self hide];
    self.anchorView = nil;
    self.pendingText = nil;
}

- (void)hide {
    [self cancelTimer];
    [self.panel orderOut:nil];
}

@end

@interface BrowserTabItemView ()
@property (nonatomic, strong) NSImageView *faviconImageView;
@property (nonatomic, strong) BrowserTabFaviconLetterBadgeView *faviconLetterBadge;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSImageView *pinIconView;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToClose;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToEdge;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingToFavicon;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingToPin;
@property (nonatomic, strong) NSLayoutConstraint *pinLeadingToFavicon;
@property (nonatomic, copy, nullable) NSString *boundHost;
@property (nonatomic, assign) NSUInteger faviconLoadToken;
@property (nonatomic, assign) CGFloat appliedWidth;
@property (nonatomic, assign) BrowserTabDisplayMode tabDisplayMode;
@property (nonatomic, assign) BOOL pointerInside;
@end

@implementation BrowserTabItemView

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIntrinsicContentSize {
    return [NSSet setWithObjects:@"tabTitle", @"tabSelected", @"tabPinned", nil];
}

- (NSSize)intrinsicContentSize {
    CGFloat height = self.heightConstraint ? self.heightConstraint.constant : kDefaultTabHeight;
    return NSMakeSize(BrowserTabItemMinWidth, height);
}

- (void)setTabHeight:(CGFloat)height {
    if (!self.heightConstraint) {
        self.heightConstraint = [self.heightAnchor constraintEqualToConstant:height];
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = height;
    }
    [self invalidateIntrinsicContentSize];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        _appliedWidth = BrowserTabItemMaxWidth;
        _tabDisplayMode = BrowserTabDisplayModeComfortable;
        _tabTitle = @"";

        _faviconImageView = [[BrowserTabFaviconIconView alloc] initWithFrame:NSZeroRect];
        _faviconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _faviconImageView.imageScaling = NSImageScaleProportionallyDown;
        _faviconImageView.hidden = YES;
        [self addSubview:_faviconImageView];

        _faviconLetterBadge = [[BrowserTabFaviconLetterBadgeView alloc] initWithFrame:NSZeroRect];
        _faviconLetterBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _faviconLetterBadge.hidden = YES;
        [self addSubview:_faviconLetterBadge];

        _titleLabel = [BrowserTabTitleLabel labelWithString:@"新标签页"];
        _titleLabel.font = [NSFont systemFontOfSize:12];
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.usesSingleLineMode = YES;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.refusesFirstResponder = YES;
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_titleLabel];

        _pinIconView = [[BrowserTabPinIconView alloc] initWithFrame:NSZeroRect];
        _pinIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _pinIconView.imageScaling = NSImageScaleProportionallyDown;
        _pinIconView.hidden = YES;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:10
                                                                weight:NSFontWeightMedium
                                                                 scale:NSImageSymbolScaleMedium];
            NSImage *symbol = [NSImage imageWithSystemSymbolName:@"pin.fill"
                                        accessibilityDescription:@"固定标签页"];
            _pinIconView.image = symbol ? [symbol imageWithSymbolConfiguration:config] : nil;
            if (@available(macOS 10.14, *)) {
                _pinIconView.contentTintColor = [NSColor secondaryLabelColor];
            }
        }
        [self addSubview:_pinIconView];

        _closeButton = [NSButton buttonWithTitle:@"×" target:self action:@selector(onClose:)];
        _closeButton.bezelStyle = NSBezelStyleInline;
        _closeButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeButton setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_closeButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_closeButton];

        _titleTrailingToClose = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor
                                                                                     constant:-kCloseTitleGap];
        _titleTrailingToEdge = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                    constant:-kTitleTrailingPad];
        _pinLeadingToFavicon = [_pinIconView.leadingAnchor constraintEqualToAnchor:_faviconImageView.trailingAnchor
                                                                          constant:kPinAfterFaviconGap];
        _titleLeadingToFavicon = [_titleLabel.leadingAnchor constraintEqualToAnchor:_faviconImageView.trailingAnchor
                                                                           constant:BrowserTabFaviconTitleGap];
        _titleLeadingToPin = [_titleLabel.leadingAnchor constraintEqualToAnchor:_pinIconView.trailingAnchor
                                                                       constant:kPinAfterFaviconGap];

        [NSLayoutConstraint activateConstraints:@[
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kCloseTrailingPad],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:kCloseButtonWidth],
            [_closeButton.heightAnchor constraintEqualToConstant:kCloseButtonWidth],

            [_faviconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                            constant:BrowserTabFaviconLeadingPad],
            [_faviconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_faviconImageView.widthAnchor constraintEqualToConstant:BrowserTabFaviconSize],
            [_faviconImageView.heightAnchor constraintEqualToConstant:BrowserTabFaviconSize],

            [_faviconLetterBadge.leadingAnchor constraintEqualToAnchor:_faviconImageView.leadingAnchor],
            [_faviconLetterBadge.trailingAnchor constraintEqualToAnchor:_faviconImageView.trailingAnchor],
            [_faviconLetterBadge.topAnchor constraintEqualToAnchor:_faviconImageView.topAnchor],
            [_faviconLetterBadge.bottomAnchor constraintEqualToAnchor:_faviconImageView.bottomAnchor],

            _pinLeadingToFavicon,
            [_pinIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pinIconView.widthAnchor constraintEqualToConstant:kPinIconSize],
            [_pinIconView.heightAnchor constraintEqualToConstant:kPinIconSize],

            _titleLeadingToFavicon,
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _titleTrailingToClose,
        ]];
        _titleLeadingToPin.active = NO;

        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self updateChromeAppearance];
        [self updateFaviconAppearance];
        [self updateDisplayModeLayout];
        [self updateCloseButtonVisibility];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(faviconDidUpdate:)
                                                     name:BrowserFaviconDidUpdateNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTabSelected:(BOOL)tabSelected {
    _tabSelected = tabSelected;
    [self updateChromeAppearance];
    [self updateCloseButtonVisibility];
    [self invalidateIntrinsicContentSize];
}

- (void)setTabPinned:(BOOL)tabPinned {
    if (_tabPinned == tabPinned) {
        return;
    }
    _tabPinned = tabPinned;
    [self updateDisplayModeLayout];
    [self updateCloseButtonVisibility];
    [self invalidateIntrinsicContentSize];
}

- (void)setTabTitle:(NSString *)tabTitle {
    NSString *normalized = tabTitle ?: @"";
    if ([_tabTitle isEqualToString:normalized]) {
        return;
    }
    _tabTitle = [normalized copy];
    self.titleLabel.stringValue = normalized.length > 0 ? normalized : @"新标签页";
    [self updateFaviconAppearance];
    [self invalidateIntrinsicContentSize];
}

- (void)setPageURLString:(NSString *)pageURLString {
    NSString *normalized = pageURLString ?: @"";
    if ((_pageURLString == nil && normalized.length == 0)
        || [_pageURLString isEqualToString:normalized]) {
        return;
    }
    _pageURLString = normalized.length > 0 ? [normalized copy] : nil;
    self.boundHost = BrowserFaviconHostFromURLString(normalized);
    [self updateFaviconAppearance];
    [self requestFaviconIfNeeded];
}

- (void)applyLoadedFaviconImage:(NSImage *)image {
    if (image) {
        self.faviconImageView.image = image;
        self.faviconImageView.hidden = NO;
        self.faviconLetterBadge.hidden = YES;
        return;
    }
    [self updateFaviconAppearance];
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

- (void)setTabToolTip:(NSString *)tabToolTip {
    NSString *normalized = tabToolTip.length > 0 ? [tabToolTip copy] : nil;
    if ((_tabToolTip == nil && normalized == nil) || [_tabToolTip isEqualToString:normalized]) {
        return;
    }
    _tabToolTip = normalized;
    if (self.pointerInside) {
        [self scheduleHoverTipIfNeeded];
    }
}

- (void)applyAvailableWidth:(CGFloat)width {
    BrowserTabDisplayMode mode = BrowserTabDisplayModeForWidth(width, self.tabSelected);
    if (fabs(self.appliedWidth - width) < 0.5 && self.tabDisplayMode == mode) {
        return;
    }
    self.appliedWidth = width;
    self.tabDisplayMode = mode;
    [self updateDisplayModeLayout];
    [self updateCloseButtonVisibility];
}

- (BOOL)showsPinIcon {
    return self.tabPinned && self.pinIconView.image != nil;
}

- (void)updateDisplayModeLayout {
    BOOL showTitle = self.tabDisplayMode != BrowserTabDisplayModeMinimal;
    BOOL showPin = [self showsPinIcon] && showTitle;

    self.titleLabel.hidden = !showTitle;
    self.pinIconView.hidden = !showPin;
    self.pinLeadingToFavicon.active = showPin;

    self.titleLeadingToPin.active = showPin;
    self.titleLeadingToFavicon.active = showTitle && !showPin;
}

- (void)updateFaviconAppearance {
    NSString *urlString = self.pageURLString ?: @"";
    if (urlString.length == 0) {
        self.faviconImageView.image = BrowserFaviconMakeDefaultGlobeImage();
        self.faviconImageView.hidden = NO;
        self.faviconLetterBadge.hidden = YES;
        return;
    }

    NSString *host = self.boundHost ?: BrowserFaviconHostFromURLString(urlString);
    if (host.length > 0) {
        NSImage *cached = [[BrowserFaviconService sharedService] cachedImageForHost:host];
        if (cached) {
            [self applyLoadedFaviconImage:cached];
            return;
        }
    }

    self.faviconImageView.image = nil;
    self.faviconImageView.hidden = YES;

    NSString *letter = [BrowserShortcutIconPalette defaultLetterForTitle:self.tabTitle
                                                               urlString:urlString];
    NSInteger colorIndex = [BrowserShortcutIconPalette defaultIndexForURLString:urlString];
    self.faviconLetterBadge.layer.backgroundColor = [BrowserShortcutIconPalette colorAtIndex:colorIndex].CGColor;
    self.faviconLetterBadge.letterLabel.stringValue = letter.length > 0 ? letter : @"?";
    self.faviconLetterBadge.hidden = NO;
}

- (void)updateCloseButtonVisibility {
    if (self.tabPinned) {
        self.closeButton.hidden = YES;
        self.titleTrailingToClose.active = NO;
        self.titleTrailingToEdge.active = YES;
        return;
    }

    BOOL alwaysShow = NO;
    switch (self.tabDisplayMode) {
        case BrowserTabDisplayModeComfortable:
            alwaysShow = self.tabSelected || self.appliedWidth >= kCloseAlwaysVisibleMinWidth;
            break;
        case BrowserTabDisplayModeCompact:
            alwaysShow = self.tabSelected;
            break;
        case BrowserTabDisplayModeMinimal:
            alwaysShow = NO;
            break;
    }

    BOOL visible = alwaysShow || self.pointerInside;
    self.closeButton.hidden = !visible;
    self.titleTrailingToClose.active = visible && self.tabDisplayMode != BrowserTabDisplayModeMinimal;
    self.titleTrailingToEdge.active = !visible || self.tabDisplayMode == BrowserTabDisplayModeMinimal;
}

- (void)updateChromeAppearance {
    BOOL dark = [self effectiveAppearanceIsDark];
    NSColor *active = BrowserTabActiveFillColor();
    NSColor *inactive = dark ? [NSColor colorWithCalibratedWhite:0.13 alpha:1.0]
                             : [NSColor colorWithCalibratedWhite:0.82 alpha:1.0];

    self.layer.backgroundColor = (self.tabSelected ? active : inactive).CGColor;

    if (@available(macOS 10.13, *)) {
        self.layer.cornerRadius = self.tabSelected ? 11.0 : 10.0;
        self.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        if (@available(macOS 10.15, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }

    self.titleLabel.textColor = [NSColor labelColor];
    self.titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    if (@available(macOS 10.14, *)) {
        self.pinIconView.contentTintColor = self.tabSelected ? [NSColor labelColor]
                                                             : [NSColor secondaryLabelColor];
    }
}

- (BOOL)effectiveAppearanceIsDark {
    NSString *name = self.effectiveAppearance.name;
    return [name containsString:@"Dark"];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateChromeAppearance];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self.trackingAreas copy]) {
        [self removeTrackingArea:area];
    }
    // 需要 MouseMoved：在标题区与关闭按钮之间移动时切换 tip 文案。
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
        | NSTrackingMouseMoved
        | NSTrackingActiveInKeyWindow
        | NSTrackingInVisibleRect;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (nullable NSString *)hoverTipTextForCurrentPointer {
    if (!self.window) {
        return nil;
    }
    NSPoint windowPoint = [self.window mouseLocationOutsideOfEventStream];
    NSPoint local = [self convertPoint:windowPoint fromView:nil];
    if (![self mouse:local inRect:self.bounds]) {
        return nil;
    }
    if (!self.closeButton.hidden) {
        NSPoint inClose = [self.closeButton convertPoint:local fromView:self];
        if ([self.closeButton mouse:inClose inRect:self.closeButton.bounds]) {
            return @"关闭标签页";
        }
    }
    return self.tabToolTip;
}

- (void)scheduleHoverTipIfNeeded {
    NSString *text = [self hoverTipTextForCurrentPointer];
    if (text.length == 0) {
        [[BrowserTabHoverTipWindow shared] cancelForView:self];
        return;
    }
    [[BrowserTabHoverTipWindow shared] scheduleText:text fromView:self];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.pointerInside = YES;
    [self updateCloseButtonVisibility];
    [self scheduleHoverTipIfNeeded];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.pointerInside = NO;
    [self updateCloseButtonVisibility];
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
}

- (void)mouseMoved:(NSEvent *)event {
    (void)event;
    if (self.pointerInside) {
        [self scheduleHoverTipIfNeeded];
    }
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (BOOL)isOpaque {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) {
        return nil;
    }
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (![self mouse:local inRect:self.bounds]) {
        return nil;
    }
    if (!self.closeButton.hidden) {
        NSPoint inClose = [self.closeButton convertPoint:local fromView:self];
        if ([self.closeButton mouse:inClose inRect:self.closeButton.bounds]) {
            return self.closeButton;
        }
    }
    return self;
}

- (void)mouseDown:(NSEvent *)event {
    [[BrowserTabHoverTipWindow shared] cancelForView:self];

    if (event.type == NSEventTypeLeftMouseDown && event.clickCount >= 2) {
        if (!self.tabPinned && self.onClose) {
            self.onClose();
        }
        return;
    }

    // 选中与拖拽解耦：先进入 tracking 排空延迟事件，再在 mouseUp / drag-commit 时选中。
    // 旧路径在 mouseDown 同步 onSelect→refreshTabsUI，主线程一卡就把单击判成拖拽。
    if (self.onSelectGestureBegan) {
        self.onSelectGestureBegan();
    }

    NSWindow *window = self.window;
    if (!window) {
        if (self.onSelect) {
            self.onSelect();
        }
        return;
    }

    NSPoint start = event.locationInWindow;
    NSTimeInterval mouseDownTime = event.timestamp;
    BOOL dragging = NO;
    NSInteger confirmSamples = 0;
    NSEventMask mask = NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;

    while (YES) {
        NSEvent *next = [window nextEventMatchingMask:mask
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (!next) {
            break;
        }

        if (next.type == NSEventTypeLeftMouseDragged) {
            CGFloat deltaX = next.locationInWindow.x - start.x;
            CGFloat deltaY = next.locationInWindow.y - start.y;
            CGFloat distance = hypot(deltaX, deltaY);
            if (!dragging) {
                NSTimeInterval held = next.timestamp - mouseDownTime;
                if (distance >= kReorderDragTeleportReject) {
                    // 卡顿恢复后队列里的瞬移：重定原点，不累计确认帧。
                    start = next.locationInWindow;
                    mouseDownTime = next.timestamp;
                    confirmSamples = 0;
                    continue;
                }
                if (distance < kReorderDragThreshold || held < kReorderDragMinDuration) {
                    confirmSamples = 0;
                    continue;
                }
                confirmSamples += 1;
                if (confirmSamples < kReorderDragConfirmSamples) {
                    continue;
                }
                dragging = YES;
                // 真正开拖后再选中，避免选中阻塞干扰手势判别。
                if (self.onSelect) {
                    self.onSelect();
                }
                if (self.onReorderDragBegan) {
                    self.onReorderDragBegan(next.locationInWindow);
                }
            }
            if (self.onReorderDragMoved) {
                self.onReorderDragMoved(next.locationInWindow);
            }
            continue;
        }

        // mouseUp
        if (dragging) {
            if (self.onReorderDragEnded) {
                self.onReorderDragEnded(next.locationInWindow);
            }
        } else if (self.onSelect) {
            self.onSelect();
        }
        break;
    }
}

- (void)onClose:(id)sender {
    (void)sender;
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
    if (self.tabPinned) {
        return;
    }
    BOOL optionHeld = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    if (optionHeld && self.onCloseTabsToTheRight) {
        self.onCloseTabsToTheRight();
        return;
    }
    if (self.onClose) {
        self.onClose();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    [[BrowserTabHoverTipWindow shared] cancelForView:self];
    if (self.contextMenuProvider) {
        return self.contextMenuProvider();
    }
    return nil;
}

@end
