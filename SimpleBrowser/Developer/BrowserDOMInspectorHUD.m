#import "BrowserDOMInspectorHUD.h"
#import "SBTextView.h"
#import <WebKit/WebKit.h>

static const CGFloat kHUDMaxWidth = 480.0;
static const CGFloat kHUDPadding = 10.0;
static const CGFloat kHUDTitleHeight = 20.0;
static const CGFloat kHUDRowHeight = 15.0;
static const CGFloat kHUDIconButton = 22.0;
static const CGFloat kHUDOnionItemH = 18.0;
static const CGFloat kHUDOnionWidth = 92.0;
static const CGFloat kHUDOnionGap = 1.0;

#pragma mark - Helpers

static NSImage *MeoHUDSymbol(NSString *name, CGFloat pointSize) {
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (!img) return nil;
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                            weight:NSFontWeightMedium];
        return [img imageWithSymbolConfiguration:cfg];
    }
    return nil;
}

static void MeoStyleIconButton(NSButton *button, NSString *symbol, NSString *fallback, NSString *tip) {
    button.bordered = NO;
    button.bezelStyle = NSBezelStyleInline;
    button.controlSize = NSControlSizeSmall;
    button.toolTip = tip;
    button.wantsLayer = YES;
    NSImage *img = MeoHUDSymbol(symbol, 12.0);
    if (img) {
        img.template = YES;
        button.image = img;
        button.imagePosition = NSImageOnly;
        button.title = @"";
        if (@available(macOS 10.14, *)) {
            button.contentTintColor = [NSColor whiteColor];
        }
    } else {
        button.image = nil;
        button.imagePosition = NSNoImage;
        button.attributedTitle = [[NSAttributedString alloc]
            initWithString:fallback
                attributes:@{
                    NSForegroundColorAttributeName: [NSColor whiteColor],
                    NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold],
                }];
    }
}

#pragma mark - HUD View

@interface BrowserDOMInspectorHUDView ()
@property (nonatomic, strong) NSButton *selectorCopyButton;
@property (nonatomic, strong) NSButton *dismissButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) SBTextView *bodyTextView;
@property (nonatomic, strong) NSView *onionBar;
@property (nonatomic, strong) NSMutableArray<NSButton *> *onionButtons;
@end

@implementation BrowserDOMInspectorHUDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleText = @"";
        _subtitleText = @"";
        _attributeRows = @[];
        _onionLabels = @[];
        _selectedOnionIndex = NSNotFound;
        _pinnedAppearance = NO;
        _onionButtons = [NSMutableArray array];
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor clearColor].CGColor;
        self.layer.cornerRadius = 8.0;
        self.layer.shadowColor = [NSColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, -2);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.3;
        [self buildInteractiveChrome];
        [self applyInteractionMode];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)buildInteractiveChrome {
    self.selectorCopyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.selectorCopyButton.target = self;
    self.selectorCopyButton.action = @selector(handleCopy:);
    MeoStyleIconButton(self.selectorCopyButton, @"doc.on.doc", @"⎘", @"复制 CSS 选择器");

    self.dismissButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.dismissButton.target = self;
    self.dismissButton.action = @selector(handleClose:);
    MeoStyleIconButton(self.dismissButton, @"xmark", @"✕", @"取消钉住");

    self.bodyTextView = [SBTextView standardTextView];
    self.bodyTextView.editable = NO;
    self.bodyTextView.selectable = YES;
    self.bodyTextView.drawsBackground = NO;
    self.bodyTextView.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    self.bodyTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.bodyTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.documentView = self.bodyTextView;

    self.onionBar = [[NSView alloc] initWithFrame:NSZeroRect];
    self.onionBar.wantsLayer = YES;

    [self addSubview:self.selectorCopyButton];
    [self addSubview:self.dismissButton];
    [self addSubview:self.scrollView];
    [self addSubview:self.onionBar];
}

- (void)setPinnedAppearance:(BOOL)pinnedAppearance {
    if (_pinnedAppearance == pinnedAppearance) return;
    _pinnedAppearance = pinnedAppearance;
    [self applyInteractionMode];
}

- (void)setOnionLabels:(NSArray<NSString *> *)onionLabels {
    _onionLabels = [onionLabels copy] ?: @[];
    [self rebuildOnionButtons];
}

- (void)setSelectedOnionIndex:(NSInteger)selectedOnionIndex {
    if (_selectedOnionIndex == selectedOnionIndex) return;
    _selectedOnionIndex = selectedOnionIndex;
    [self refreshOnionSelectionAppearance];
}

- (void)applyInteractionMode {
    BOOL pinned = self.pinnedAppearance;
    self.selectorCopyButton.hidden = NO;
    self.dismissButton.hidden = !pinned;
    self.scrollView.hidden = !pinned;
    self.onionBar.hidden = (self.onionLabels.count == 0);
    if (!pinned) {
        [self.window makeFirstResponder:nil];
    }
    [self layoutChrome];
    [self setNeedsDisplay:YES];
}

- (void)rebuildOnionButtons {
    NSArray<NSView *> *old = [self.onionBar.subviews copy];
    for (NSView *v in old) {
        [v removeFromSuperview];
    }
    [self.onionButtons removeAllObjects];

    NSInteger count = (NSInteger)self.onionLabels.count;
    for (NSInteger i = 0; i < count; i++) {
        NSString *label = self.onionLabels[(NSUInteger)i];
        NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
        btn.bordered = NO;
        btn.bezelStyle = NSBezelStyleInline;
        btn.controlSize = NSControlSizeMini;
        btn.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
        btn.target = self;
        btn.action = @selector(handleOnion:);
        btn.tag = i;
        btn.toolTip = [NSString stringWithFormat:@"查看 <%@> 的属性", label];
        btn.wantsLayer = YES;
        // 非末级前加分隔符感：标题即标签名
        btn.title = label;
        [self.onionBar addSubview:btn];
        [self.onionButtons addObject:btn];

    }
    self.onionBar.hidden = (count == 0);
    [self refreshOnionSelectionAppearance];
    [self layoutChrome];
}

- (void)refreshOnionSelectionAppearance {
    NSInteger sel = self.selectedOnionIndex;
    for (NSButton *btn in self.onionButtons) {
        BOOL on = (btn.tag == sel);
        if (@available(macOS 10.14, *)) {
            btn.contentTintColor = on
                ? [NSColor colorWithCalibratedRed:1.0 green:0.62 blue:0.25 alpha:1.0]
                : [NSColor colorWithCalibratedWhite:0.78 alpha:1.0];
        }
        btn.font = [NSFont monospacedSystemFontOfSize:10
                                               weight:on ? NSFontWeightBold : NSFontWeightMedium];
    }
}

- (void)reloadPinnedContent {
    if (!self.pinnedAppearance) return;
    NSMutableString *text = [NSMutableString string];
    NSString *title = self.titleText.length > 0 ? self.titleText : @"";
    [text appendFormat:@"%@\n", title];
    if (self.subtitleText.length > 0) {
        [text appendFormat:@"%@\n", self.subtitleText];
    }
    if (self.attributeRows.count > 0) {
        [text appendString:@"────────────────\n"];
        for (NSString *row in self.attributeRows) {
            [text appendFormat:@"%@\n", row];
        }
    }
    self.bodyTextView.string = text;
    [self.bodyTextView setSelectedRange:NSMakeRange(0, 0)];
    [self layoutChrome];
}

- (CGFloat)onionColumnWidth {
    return (self.onionLabels.count > 0) ? kHUDOnionWidth : 0;
}

- (void)layoutChrome {
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);
    CGFloat btn = kHUDIconButton;

    self.dismissButton.frame = self.pinnedAppearance
        ? NSMakeRect(w - kHUDPadding - btn, kHUDPadding, btn, btn)
        : NSZeroRect;
    self.selectorCopyButton.frame = self.pinnedAppearance
        ? NSMakeRect(w - kHUDPadding - btn * 2 - 6, kHUDPadding, btn, btn)
        : NSMakeRect(w - kHUDPadding - btn, kHUDPadding, btn, btn);

    CGFloat onionW = [self onionColumnWidth];
    CGFloat top = self.pinnedAppearance ? (kHUDPadding + btn + 4) : (kHUDPadding + kHUDTitleHeight +
        (self.subtitleText.length > 0 ? kHUDRowHeight : 0) + 4);
    // 悬停态正文由 drawRect 绘制，洋葱列贴左下；钉住态正文在右侧 scroll。
    if (!self.pinnedAppearance) {
        top = kHUDPadding;
    }
    CGFloat onionH = MAX(0, h - top - kHUDPadding);
    self.onionBar.frame = NSMakeRect(kHUDPadding, top, onionW, onionH);
    [self layoutOnionButtonsInBar];

    if (self.pinnedAppearance) {
        CGFloat bodyTop = kHUDPadding + btn + 6;
        CGFloat bodyX = kHUDPadding + (onionW > 0 ? onionW + 8 : 0);
        CGFloat bodyW = MAX(0, w - bodyX - kHUDPadding);
        CGFloat bodyH = MAX(0, h - bodyTop - kHUDPadding);
        self.scrollView.frame = NSMakeRect(bodyX, bodyTop, bodyW, bodyH);
        self.bodyTextView.minSize = NSMakeSize(0, 0);
        self.bodyTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        NSUInteger lines = MAX(1, [[self.bodyTextView.string componentsSeparatedByCharactersInSet:
                                    [NSCharacterSet newlineCharacterSet]] count]);
        CGFloat textH = MAX(bodyH, lines * (kHUDRowHeight + 1));
        [self.bodyTextView setFrameSize:NSMakeSize(MAX(bodyW - 4, 1), textH)];
    } else {
        self.scrollView.frame = NSZeroRect;
    }
}

- (void)layoutOnionButtonsInBar {
    CGFloat y = 0;
    CGFloat w = NSWidth(self.onionBar.bounds);
    for (NSButton *btn in self.onionButtons) {
        btn.frame = NSMakeRect(0, y, w, kHUDOnionItemH);
        btn.alignment = NSTextAlignmentLeft;
        y += kHUDOnionItemH + kHUDOnionGap;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutChrome];
}

- (void)handleCopy:(id)sender {
    (void)sender;
    if (self.onCopySelector) self.onCopySelector();
    if (!self.pinnedAppearance && self.onRequestInteractiveLock) {
        self.onRequestInteractiveLock();
    }
}

- (void)handleClose:(id)sender {
    (void)sender;
    if (self.onClose) self.onClose();
}

- (void)handleOnion:(id)sender {
    NSButton *btn = (NSButton *)sender;
    if (![btn isKindOfClass:[NSButton class]]) return;
    NSInteger idx = btn.tag;
    if (self.onSelectOnionIndex) self.onSelectOnionIndex(idx);
    if (!self.pinnedAppearance && self.onRequestInteractiveLock) {
        self.onRequestInteractiveLock();
    }
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) return nil;
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(local, self.bounds)) return nil;
    if (self.pinnedAppearance) {
        NSView *hit = [super hitTest:point];
        return hit ?: self;
    }
    // 悬停穿透：复制 + 洋葱导航可点。
    if (!self.selectorCopyButton.hidden &&
        NSPointInRect(local, self.selectorCopyButton.frame)) {
        return [self.selectorCopyButton hitTest:point] ?: self.selectorCopyButton;
    }
    if (!self.onionBar.hidden && NSPointInRect(local, self.onionBar.frame)) {
        NSView *hit = [self.onionBar hitTest:point];
        if (hit && hit != self.onionBar) return hit;
        return nil;
    }
    return nil;
}

+ (NSFont *)titleFont { return [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold]; }
+ (NSFont *)subtitleFont { return [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]; }
+ (NSFont *)rowFont { return [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; }

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);

    [[NSColor colorWithCalibratedWhite:0.10 alpha:0.97] setFill];
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8];
    [bg fill];

    if (self.pinnedAppearance) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.48 blue:0.10 alpha:1.0] setStroke];
    } else {
        [[NSColor colorWithCalibratedRed:0.18 green:0.48 blue:1.0 alpha:1.0] setStroke];
    }
    NSBezierPath *accent = [NSBezierPath bezierPath];
    [accent moveToPoint:NSMakePoint(kHUDPadding, h - 1)];
    [accent lineToPoint:NSMakePoint(w - kHUDPadding, h - 1)];
    accent.lineWidth = 2;
    [accent stroke];

    if (self.pinnedAppearance) return;

    CGFloat onionW = [self onionColumnWidth];
    CGFloat contentX = kHUDPadding + (onionW > 0 ? onionW + 8 : 0);
    CGFloat titleMaxW = w - contentX - kHUDPadding - kHUDIconButton - 4;
    CGFloat y = kHUDPadding + 2;
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [BrowserDOMInspectorHUDView titleFont],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
    };
    NSString *dispTitle = self.titleText ?: @"";
    while (dispTitle.length > 4 && [dispTitle sizeWithAttributes:titleAttrs].width > titleMaxW) {
        dispTitle = [dispTitle substringToIndex:dispTitle.length - 1];
    }
    if (dispTitle.length < self.titleText.length) dispTitle = [dispTitle stringByAppendingString:@"\u2026"];
    [dispTitle drawAtPoint:NSMakePoint(contentX, y) withAttributes:titleAttrs];
    y += kHUDTitleHeight;

    if (self.subtitleText.length > 0) {
        NSDictionary *subAttrs = @{
            NSFontAttributeName: [BrowserDOMInspectorHUDView subtitleFont],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.55 alpha:1.0],
        };
        NSString *sub = self.subtitleText;
        while (sub.length > 4 && [sub sizeWithAttributes:subAttrs].width > titleMaxW) {
            sub = [sub substringToIndex:sub.length - 1];
        }
        if (sub.length < self.subtitleText.length) sub = [sub stringByAppendingString:@"\u2026"];
        [sub drawAtPoint:NSMakePoint(contentX, y) withAttributes:subAttrs];
        y += kHUDRowHeight;
    }

    NSDictionary *rowAttrs = @{
        NSFontAttributeName: [BrowserDOMInspectorHUDView rowFont],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.72 alpha:1.0],
    };
    y += 2;
    CGFloat attrBottom = h - kHUDPadding;
    for (NSString *row in self.attributeRows) {
        if (y + kHUDRowHeight > attrBottom) break;
        NSString *disp = row;
        while (disp.length > 4 && [disp sizeWithAttributes:rowAttrs].width > titleMaxW) {
            disp = [disp substringToIndex:disp.length - 1];
        }
        if (disp.length < row.length) disp = [disp stringByAppendingString:@"\u2026"];
        [disp drawAtPoint:NSMakePoint(contentX, y) withAttributes:rowAttrs];
        y += kHUDRowHeight;
    }
}
@end

#pragma mark - HUD Controller

@interface BrowserDOMInspectorHUD ()
@property (nonatomic, strong, nullable) BrowserDOMInspectorHUDView *view;
@property (nonatomic, weak, nullable) NSWindow *hostWindow;
@property (nonatomic, copy, nullable) NSString *pendingSelector;
@property (nonatomic, assign) NSRect lastGeometry;
@property (nonatomic, assign) NSRect lastWebViewRect;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *ancestors;
@property (nonatomic, assign) NSInteger selectedAncestorIndex;
@property (nonatomic, copy, nullable) NSDictionary *rootSnapshot;
@end

@implementation BrowserDOMInspectorHUD

- (BrowserDOMInspectorHUDView *)ensureViewForWindow:(NSWindow *)window {
    NSView *host = window.contentView;
    if (self.view && self.hostWindow == window && self.view.superview == host) {
        return self.view;
    }
    [self.view removeFromSuperview];
    self.view = nil;
    self.hostWindow = window;

    BrowserDOMInspectorHUDView *view = [[BrowserDOMInspectorHUDView alloc]
        initWithFrame:NSMakeRect(0, 0, 200, 60)];
    view.hidden = YES;
    __weak typeof(self) weakSelf = self;
    view.onCopySelector = ^{
        NSString *selector = weakSelf.pendingSelector;
        if (selector.length > 0 && weakSelf.onCopySelector) {
            weakSelf.onCopySelector(selector);
        }
    };
    view.onClose = ^{
        if (weakSelf.onClosePinned) weakSelf.onClosePinned();
    };
    view.onRequestInteractiveLock = ^{
        [weakSelf lockInteractiveWithCurrentSnapshot];
        if (weakSelf.onInteractiveLockFromCopy) weakSelf.onInteractiveLockFromCopy();
    };
    view.onSelectOnionIndex = ^(NSInteger index) {
        [weakSelf selectAncestorAtIndex:index];
    };
    [host addSubview:view positioned:NSWindowAbove relativeTo:nil];
    self.view = view;
    return view;
}

- (NSArray<NSDictionary *> *)normalizedAncestorsFromSnapshot:(NSDictionary *)snapshot {
    NSArray *raw = [snapshot[@"ancestors"] isKindOfClass:[NSArray class]] ? snapshot[@"ancestors"] : nil;
    if (raw.count > 0) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in raw) {
            if ([item isKindOfClass:[NSDictionary class]]) [out addObject:item];
        }
        if (out.count > 0) return out;
    }
    // 无 ancestors 时退化为仅当前节点。
    return @[ snapshot ];
}

- (NSString *)labelForAncestor:(NSDictionary *)node {
    NSString *tag = [node[@"tagName"] isKindOfClass:[NSString class]] ? node[@"tagName"] : @"?";
    NSString *elementID = [node[@"id"] isKindOfClass:[NSString class]] ? node[@"id"] : @"";
    NSString *cls = [node[@"className"] isKindOfClass:[NSString class]] ? node[@"className"] : @"";
    if (elementID.length > 0) {
        return [NSString stringWithFormat:@"%@#%@", tag, elementID];
    }
    if (cls.length > 0) {
        NSString *first = [[cls componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]] firstObject];
        if (first.length > 0) {
            return [NSString stringWithFormat:@"%@.%@", tag, first];
        }
    }
    return tag;
}

- (NSArray<NSString *> *)attributeRowsForAncestor:(NSDictionary *)node includeSelector:(BOOL)includeSelector {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSString *selector = [node[@"selector"] isKindOfClass:[NSString class]] ? node[@"selector"] : @"";
    NSString *cls = [node[@"className"] isKindOfClass:[NSString class]] ? node[@"className"] : @"";
    NSArray *attributes = [node[@"attributes"] isKindOfClass:[NSArray class]] ? node[@"attributes"] : @[];

    if (includeSelector && selector.length > 0) {
        [rows addObject:[NSString stringWithFormat:@"selector=%@", selector]];
    }
    if (cls.length > 0) {
        [rows addObject:[NSString stringWithFormat:@"class=\"%@\"", cls]];
    }
    for (NSDictionary *attr in attributes) {
        if (![attr isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = [attr[@"name"] isKindOfClass:[NSString class]] ? attr[@"name"] : nil;
        NSString *value = [attr[@"value"] isKindOfClass:[NSString class]] ? attr[@"value"] : @"";
        if (name.length == 0 || [name isEqualToString:@"class"]) continue;
        [rows addObject:[NSString stringWithFormat:@"%@=\"%@\"", name, value]];
    }
    return rows;
}

- (void)applySelectedAncestorToView:(BrowserDOMInspectorHUDView *)view {
    if (self.ancestors.count == 0) return;
    NSInteger idx = self.selectedAncestorIndex;
    if (idx < 0 || idx >= (NSInteger)self.ancestors.count) {
        idx = (NSInteger)self.ancestors.count - 1;
        self.selectedAncestorIndex = idx;
    }
    NSDictionary *node = self.ancestors[(NSUInteger)idx];
    view.titleText = [self labelForAncestor:node];
    view.attributeRows = [self attributeRowsForAncestor:node includeSelector:YES];
    view.selectedOnionIndex = idx;

    NSString *selector = [node[@"selector"] isKindOfClass:[NSString class]] ? node[@"selector"] : @"";
    self.pendingSelector = selector;

    // 几何信息仍用根快照（页面上当前高亮元素）。
    NSDictionary *geo = [self.rootSnapshot[@"geometry"] isKindOfClass:[NSDictionary class]]
        ? self.rootSnapshot[@"geometry"] : nil;
    if (geo) {
        view.subtitleText = [NSString stringWithFormat:@"%@×%@ @ (%@, %@)%@",
                             geo[@"width"] ?: @0, geo[@"height"] ?: @0,
                             geo[@"x"] ?: @0, geo[@"y"] ?: @0,
                             [geo[@"inViewport"] boolValue] ? @"" : @" · 视口外"];
    } else {
        view.subtitleText = @"";
    }
}

- (void)selectAncestorAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.ancestors.count) return;
    self.selectedAncestorIndex = index;
    BrowserDOMInspectorHUDView *view = self.view;
    NSWindow *window = self.hostWindow;
    if (!view || !window) return;
    [self applySelectedAncestorToView:view];
    NSSize size = [self contentSizeForView:view
                                    pinned:view.pinnedAppearance
                                  inWindow:window];
    view.frame = [self frameForGeometry:self.lastGeometry
                            webViewRect:self.lastWebViewRect
                             contentSize:size
                                inWindow:window];
    if (view.pinnedAppearance) {
        [view reloadPinnedContent];
    } else {
        [view layoutChrome];
        [view setNeedsDisplay:YES];
    }
}

- (void)showSnapshot:(NSDictionary *)snapshot
   geometryInContent:(NSRect)geometry
     webViewInContent:(NSRect)webViewRect
            inWindow:(NSWindow *)window
              pinned:(BOOL)pinned {
    if (!snapshot || !window) {
        [self hide];
        return;
    }
    BrowserDOMInspectorHUDView *view = [self ensureViewForWindow:window];
    [window.contentView addSubview:view positioned:NSWindowAbove relativeTo:nil];
    view.layer.zPosition = 20000;

    self.rootSnapshot = snapshot;
    self.ancestors = [self normalizedAncestorsFromSnapshot:snapshot];
    self.selectedAncestorIndex = (NSInteger)self.ancestors.count - 1;

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSDictionary *node in self.ancestors) {
        [labels addObject:[self labelForAncestor:node]];
    }
    view.onionLabels = labels;

    [self applySelectedAncestorToView:view];
    view.pinnedAppearance = pinned;
    self.lastGeometry = geometry;
    self.lastWebViewRect = webViewRect;

    NSSize size = [self contentSizeForView:view pinned:pinned inWindow:window];
    view.frame = [self frameForGeometry:geometry
                            webViewRect:webViewRect
                             contentSize:size
                                inWindow:window];
    if (pinned) {
        [view reloadPinnedContent];
    } else {
        [view layoutChrome];
    }
    view.hidden = NO;
    view.alphaValue = 1.0;
    [view setNeedsDisplay:YES];
}

- (void)lockInteractiveWithCurrentSnapshot {
    BrowserDOMInspectorHUDView *view = self.view;
    NSWindow *window = self.hostWindow;
    if (!view || !window || view.hidden) return;
    if (view.pinnedAppearance) {
        [view reloadPinnedContent];
        return;
    }
    view.pinnedAppearance = YES;
    NSSize size = [self contentSizeForView:view pinned:YES inWindow:window];
    view.frame = [self frameForGeometry:self.lastGeometry
                            webViewRect:self.lastWebViewRect
                             contentSize:size
                                inWindow:window];
    [view reloadPinnedContent];
    [view setNeedsDisplay:YES];
}

- (NSSize)contentSizeForView:(BrowserDOMInspectorHUDView *)view
                      pinned:(BOOL)pinned
                    inWindow:(NSWindow *)window {
    NSFont *titleFont = [BrowserDOMInspectorHUDView titleFont];
    NSFont *bodyFont = [BrowserDOMInspectorHUDView rowFont];

    CGFloat contentW = [(view.titleText ?: @"") sizeWithAttributes:@{NSFontAttributeName: titleFont}].width;
    for (NSString *row in view.attributeRows) {
        contentW = MAX(contentW, [row sizeWithAttributes:@{NSFontAttributeName: bodyFont}].width);
    }

    CGFloat onionW = (view.onionLabels.count > 0) ? kHUDOnionWidth : 0;
    CGFloat trailing = pinned ? (kHUDIconButton * 2 + 20.0) : (kHUDIconButton + 16.0);
    CGFloat width = ceil(contentW) + kHUDPadding * 2 + trailing + (onionW > 0 ? onionW + 8 : 0);
    width = MIN(MAX(width, pinned ? 320.0 : 240.0), kHUDMaxWidth);

    CGFloat attrH = kHUDPadding * 2 + kHUDTitleHeight;
    if (view.subtitleText.length > 0) attrH += kHUDRowHeight;
    attrH += 4 + view.attributeRows.count * kHUDRowHeight;
    if (pinned) attrH += kHUDIconButton + 8;

    CGFloat onionH = kHUDPadding * 2 + view.onionLabels.count * (kHUDOnionItemH + kHUDOnionGap);
    CGFloat height = MAX(attrH, onionH);

    CGFloat maxH = NSHeight(self.lastWebViewRect);
    if (maxH < 80) maxH = NSHeight(window.contentView.bounds) * 0.7;
    maxH = MAX(140.0, maxH - 24.0);
    if (height > maxH) height = maxH;
    if (pinned) height = MAX(height, 140.0);

    return NSMakeSize(width, height);
}

- (NSRect)frameForGeometry:(NSRect)geometry
              webViewRect:(NSRect)webViewRect
               contentSize:(NSSize)size
                  inWindow:(NSWindow *)window {
    NSRect content = window.contentView.bounds;
    CGFloat minX = webViewRect.size.width > 0 ? NSMinX(webViewRect) : 0;
    CGFloat minY = webViewRect.size.height > 0 ? NSMinY(webViewRect) : 0;
    CGFloat maxX = webViewRect.size.width > 0 ? NSMaxX(webViewRect) : NSMaxX(content);
    CGFloat maxY = webViewRect.size.height > 0 ? NSMaxY(webViewRect) : NSMaxY(content);
    if (maxX - minX < size.width) { minX = NSMinX(content); maxX = NSMaxX(content); }
    if (maxY - minY < size.height) { minY = NSMinY(content); maxY = NSMaxY(content); }

    NSRect target = geometry;
    CGFloat x = NSMinX(target);
    CGFloat yTop = maxY - NSMaxY(target);
    static const CGFloat gap = 14.0;
    CGFloat y = yTop + gap;
    if (y + size.height > maxY - minY) {
        y = yTop - gap - size.height;
    }
    if (y < minY) y = minY;
    if (x < minX) x = minX;
    if (x + size.width > maxX) x = maxX - size.width;
    return NSMakeRect(x, NSHeight(content) - (y - minY) - size.height,
                      size.width, size.height);
}

- (void)hide {
    self.view.hidden = YES;
    self.view.pinnedAppearance = NO;
    self.pendingSelector = nil;
    self.ancestors = nil;
    self.rootSnapshot = nil;
    self.selectedAncestorIndex = NSNotFound;
}

- (void)dealloc {
    [_view removeFromSuperview];
}

@end
