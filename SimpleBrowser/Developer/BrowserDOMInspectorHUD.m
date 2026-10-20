#import "BrowserDOMInspectorHUD.h"
#import "SBTextView.h"
#import <WebKit/WebKit.h>

static const CGFloat kHUDMaxWidth = 360.0;
static const CGFloat kHUDPadding = 10.0;
static const CGFloat kHUDTitleHeight = 22.0;
static const CGFloat kHUDRowHeight = 16.0;
static const CGFloat kHUDButtonSize = 26.0;
static const CGFloat kHUDHoverCopyWidth = 44.0;
static const NSUInteger kHUDMaxAttributeRows = 8;

#pragma mark - HUD View

@interface BrowserDOMInspectorHUDView ()
@property (nonatomic, strong) NSButton *selectorCopyButton;
@property (nonatomic, strong) NSButton *dismissButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) SBTextView *bodyTextView;
@end

@implementation BrowserDOMInspectorHUDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleText = @"";
        _subtitleText = @"";
        _attributeRows = @[];
        _pinnedAppearance = NO;
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
    self.selectorCopyButton = [NSButton buttonWithTitle:@"复制"
                                                  target:self
                                                  action:@selector(handleCopy:)];
    self.selectorCopyButton.bezelStyle = NSBezelStyleRounded;
    self.selectorCopyButton.controlSize = NSControlSizeSmall;
    self.selectorCopyButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.selectorCopyButton.toolTip = @"复制 CSS 选择器";

    self.dismissButton = [NSButton buttonWithTitle:@"关闭"
                                             target:self
                                             action:@selector(handleClose:)];
    self.dismissButton.bezelStyle = NSBezelStyleRounded;
    self.dismissButton.controlSize = NSControlSizeSmall;
    self.dismissButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.dismissButton.toolTip = @"取消钉住";

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

    [self addSubview:self.selectorCopyButton];
    [self addSubview:self.dismissButton];
    [self addSubview:self.scrollView];
}

- (void)setPinnedAppearance:(BOOL)pinnedAppearance {
    if (_pinnedAppearance == pinnedAppearance) return;
    _pinnedAppearance = pinnedAppearance;
    [self applyInteractionMode];
}

- (void)applyInteractionMode {
    BOOL pinned = self.pinnedAppearance;
    // 悬停也显示「复制」，便于点中；关闭与正文仅交互态显示。
    self.selectorCopyButton.hidden = NO;
    self.dismissButton.hidden = !pinned;
    self.scrollView.hidden = !pinned;
    if (!pinned) {
        [self.window makeFirstResponder:nil];
    }
    [self layoutChrome];
    [self setNeedsDisplay:YES];
}

- (void)reloadPinnedContent {
    if (!self.pinnedAppearance) return;
    NSMutableString *text = [NSMutableString string];
    NSString *title = self.titleText.length > 0 ? self.titleText : @"";
    [text appendFormat:@"钉住 · %@\n", title];
    if (self.subtitleText.length > 0) {
        [text appendFormat:@"%@\n", self.subtitleText];
    }
    [text appendString:@"────────────────\n"];
    for (NSString *row in self.attributeRows) {
        [text appendFormat:@"%@\n", row];
    }
    self.bodyTextView.string = text;
    [self.bodyTextView setSelectedRange:NSMakeRange(0, 0)];
    [self layoutChrome];
}

- (void)layoutChrome {
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);
    CGFloat btnW = kHUDHoverCopyWidth;
    if (self.pinnedAppearance) {
        self.dismissButton.frame = NSMakeRect(w - kHUDPadding - btnW, kHUDPadding, btnW, kHUDButtonSize);
        self.selectorCopyButton.frame = NSMakeRect(w - kHUDPadding - btnW * 2 - 6, kHUDPadding, btnW, kHUDButtonSize);

        CGFloat bodyTop = kHUDPadding + kHUDButtonSize + 6;
        CGFloat bodyW = MAX(0, w - kHUDPadding * 2);
        CGFloat bodyH = MAX(0, h - bodyTop - kHUDPadding);
        self.scrollView.frame = NSMakeRect(kHUDPadding, bodyTop, bodyW, bodyH);
        self.bodyTextView.minSize = NSMakeSize(0, 0);
        self.bodyTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        NSUInteger lines = MAX(1, [[self.bodyTextView.string componentsSeparatedByCharactersInSet:
                                    [NSCharacterSet newlineCharacterSet]] count]);
        CGFloat textH = MAX(bodyH, lines * (kHUDRowHeight + 2));
        [self.bodyTextView setFrameSize:NSMakeSize(MAX(bodyW - 4, 1), textH)];
    } else {
        self.selectorCopyButton.frame = NSMakeRect(w - kHUDPadding - btnW, kHUDPadding, btnW, kHUDButtonSize);
        self.dismissButton.frame = NSZeroRect;
        self.scrollView.frame = NSZeroRect;
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

/// 悬停：仅「复制」可点；钉住：整块可点。
- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) return nil;
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(local, self.bounds)) return nil;
    if (self.pinnedAppearance) {
        NSView *hit = [super hitTest:point];
        return hit ?: self;
    }
    // 悬停穿透：只把命中交给复制按钮。
    if (!self.selectorCopyButton.hidden &&
        NSPointInRect(local, self.selectorCopyButton.frame)) {
        return [self.selectorCopyButton hitTest:point] ?: self.selectorCopyButton;
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

    // 钉住态正文由 SBTextView 承担。
    if (self.pinnedAppearance) return;

    CGFloat titleMaxW = w - kHUDPadding * 2 - kHUDHoverCopyWidth - 8;
    CGFloat y = h - kHUDPadding - kHUDTitleHeight + 2;
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [BrowserDOMInspectorHUDView titleFont],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
    };
    NSString *dispTitle = self.titleText ?: @"";
    while (dispTitle.length > 4 && [dispTitle sizeWithAttributes:titleAttrs].width > titleMaxW) {
        dispTitle = [dispTitle substringToIndex:dispTitle.length - 1];
    }
    if (dispTitle.length < self.titleText.length) dispTitle = [dispTitle stringByAppendingString:@"\u2026"];
    [dispTitle drawAtPoint:NSMakePoint(kHUDPadding, y) withAttributes:titleAttrs];

    if (self.subtitleText.length > 0) {
        y -= kHUDRowHeight;
        NSDictionary *subAttrs = @{
            NSFontAttributeName: [BrowserDOMInspectorHUDView subtitleFont],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.55 alpha:1.0],
        };
        NSString *sub = self.subtitleText;
        while (sub.length > 4 && [sub sizeWithAttributes:subAttrs].width > titleMaxW) {
            sub = [sub substringToIndex:sub.length - 1];
        }
        if (sub.length < self.subtitleText.length) sub = [sub stringByAppendingString:@"\u2026"];
        [sub drawAtPoint:NSMakePoint(kHUDPadding, y) withAttributes:subAttrs];
    }

    NSDictionary *rowAttrs = @{
        NSFontAttributeName: [BrowserDOMInspectorHUDView rowFont],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.72 alpha:1.0],
    };
    y -= 4;
    for (NSString *row in self.attributeRows) {
        y -= kHUDRowHeight;
        if (y < kHUDPadding) break;
        NSString *disp = row;
        while (disp.length > 4 && [disp sizeWithAttributes:rowAttrs].width > titleMaxW) {
            disp = [disp substringToIndex:disp.length - 1];
        }
        if (disp.length < row.length) disp = [disp stringByAppendingString:@"\u2026"];
        [disp drawAtPoint:NSMakePoint(kHUDPadding, y) withAttributes:rowAttrs];
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
    [host addSubview:view positioned:NSWindowAbove relativeTo:nil];
    self.view = view;
    return view;
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

    NSString *selector = [snapshot[@"selector"] isKindOfClass:[NSString class]] ? snapshot[@"selector"] : @"";
    NSString *tag = [snapshot[@"tagName"] isKindOfClass:[NSString class]] ? snapshot[@"tagName"] : @"";
    NSString *elementID = [snapshot[@"id"] isKindOfClass:[NSString class]] ? snapshot[@"id"] : @"";
    NSString *cls = [snapshot[@"className"] isKindOfClass:[NSString class]] ? snapshot[@"className"] : @"";
    view.titleText = elementID.length > 0 ? [NSString stringWithFormat:@"%@#%@", tag, elementID] : tag;

    NSDictionary *geo = [snapshot[@"geometry"] isKindOfClass:[NSDictionary class]] ? snapshot[@"geometry"] : nil;
    if (geo) {
        view.subtitleText = [NSString stringWithFormat:@"%@×%@ @ (%@, %@)%@",
                             geo[@"width"] ?: @0, geo[@"height"] ?: @0,
                             geo[@"x"] ?: @0, geo[@"y"] ?: @0,
                             [geo[@"inViewport"] boolValue] ? @"" : @" \u00b7 \u89c6\u53e3\u5916"];
    } else {
        view.subtitleText = @"";
    }

    NSArray *attributes = [snapshot[@"attributes"] isKindOfClass:[NSArray class]] ? snapshot[@"attributes"] : @[];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSUInteger shown = 0;
    for (NSDictionary *attr in attributes) {
        if (shown >= kHUDMaxAttributeRows) break;
        NSString *name = [attr[@"name"] isKindOfClass:[NSString class]] ? attr[@"name"] : nil;
        NSString *value = [attr[@"value"] isKindOfClass:[NSString class]] ? attr[@"value"] : @"";
        if (name.length == 0 || [name isEqualToString:@"class"]) continue;
        [rows addObject:[NSString stringWithFormat:@"%@=\"%@\"", name, value]];
        shown++;
    }
    if (cls.length > 0) {
        [rows insertObject:[NSString stringWithFormat:@"class=\"%@\"", cls] atIndex:0];
    }
    if (attributes.count > shown) {
        [rows addObject:[NSString stringWithFormat:@"\u2026 \u53e6\u6709 %lu \u4e2a\u5c5e\u6027",
                          (unsigned long)(attributes.count - shown)]];
    }
    if (selector.length > 0) {
        [rows insertObject:[NSString stringWithFormat:@"selector=%@", selector] atIndex:0];
    }
    view.attributeRows = rows;
    view.pinnedAppearance = pinned;
    self.lastGeometry = geometry;
    self.lastWebViewRect = webViewRect;
    self.pendingSelector = selector;

    NSSize size = [self contentSizeForView:view pinned:pinned];
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
    NSSize size = [self contentSizeForView:view pinned:YES];
    view.frame = [self frameForGeometry:self.lastGeometry
                            webViewRect:self.lastWebViewRect
                             contentSize:size
                                inWindow:window];
    [view reloadPinnedContent];
    [view setNeedsDisplay:YES];
}

- (NSSize)contentSizeForView:(BrowserDOMInspectorHUDView *)view pinned:(BOOL)pinned {
    NSFont *titleFont = [BrowserDOMInspectorHUDView titleFont];
    NSFont *bodyFont = [BrowserDOMInspectorHUDView rowFont];
    NSString *titleForWidth = pinned
        ? [@"钉住 · " stringByAppendingString:(view.titleText ?: @"")]
        : (view.titleText ?: @"");
    CGFloat width = [titleForWidth sizeWithAttributes:@{NSFontAttributeName: titleFont}].width;
    for (NSString *row in view.attributeRows) {
        width = MAX(width, [row sizeWithAttributes:@{NSFontAttributeName: bodyFont}].width);
    }
    CGFloat trailing = pinned ? 110.0 : (kHUDHoverCopyWidth + 16.0);
    width = MIN(MAX(ceil(width) + kHUDPadding * 2 + trailing, pinned ? 260.0 : 180.0), kHUDMaxWidth);
    CGFloat height = kHUDPadding * 2 + kHUDTitleHeight;
    if (view.subtitleText.length > 0) height += kHUDRowHeight;
    height += view.attributeRows.count * kHUDRowHeight;
    if (pinned) {
        height = MAX(height + 20.0, 140.0);
    }
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
}

- (void)dealloc {
    [_view removeFromSuperview];
}

@end
