#import "BrowserDOMInspectorHUD.h"
#import <WebKit/WebKit.h>

static const CGFloat kHUDMaxWidth = 340.0;
static const CGFloat kHUDPadding = 10.0;
static const CGFloat kHUDTitleHeight = 18.0;
static const CGFloat kHUDRowHeight = 16.0;
static const NSUInteger kHUDMaxAttributeRows = 8;

#pragma mark - HUD View

@implementation BrowserDOMInspectorHUDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleText = @"";
        _subtitleText = @"";
        _attributeRows = @[];
        _copyButtonRect = NSZeroRect;
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor clearColor].CGColor;
        self.layer.cornerRadius = 8.0;
        self.layer.shadowColor = [NSColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, -2);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.3;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

/// 默认整体穿透；仅按钮热区可点。
- (NSView *)hitTest:(NSPoint)point {
    if (NSPointInRect(point, self.copyButtonRect)) return self;
    return nil;
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (self.onCopySelector) self.onCopySelector();
}

+ (NSFont *)titleFont { return [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold]; }
+ (NSFont *)subtitleFont { return [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]; }
+ (NSFont *)rowFont { return [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; }
+ (NSFont *)buttonFont { return [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; }

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);

    // 深色半透明背景
    [[NSColor colorWithCalibratedWhite:0.10 alpha:0.97] setFill];
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8];
    [bg fill];

    // 顶部高亮细线
    [[NSColor colorWithCalibratedRed:0.18 green:0.48 blue:1.0 alpha:1.0] setStroke];
    NSBezierPath *accent = [NSBezierPath bezierPath];
    [accent moveToPoint:NSMakePoint(kHUDPadding, h - 1)];
    [accent lineToPoint:NSMakePoint(w - kHUDPadding, h - 1)];
    accent.lineWidth = 2;
    [accent stroke];

    // 标题行
    CGFloat y = h - kHUDPadding - kHUDTitleHeight + 2;
    NSFont *titleFont = [BrowserDOMInspectorHUDView titleFont];
    NSColor *titleColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
    NSDictionary *titleAttrs = @{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: titleColor};
    NSString *dispTitle = self.titleText ?: @"";
    NSSize titleSize = [dispTitle sizeWithAttributes:titleAttrs];
    CGFloat titleMaxW = w - kHUDPadding * 2 - 50;
    if (titleSize.width > titleMaxW && titleMaxW > 0) {
        // 从中间截断
        NSUInteger keepLeft = (NSUInteger)(titleMaxW / [dispTitle sizeWithAttributes:titleAttrs].width * dispTitle.length / 2);
        if (keepLeft > dispTitle.length - 2) keepLeft = dispTitle.length - 2;
        NSUInteger keepRight = dispTitle.length - keepLeft;
        dispTitle = [[dispTitle substringToIndex:keepLeft]
                     stringByAppendingString:@"\u2026"];
        if (keepRight > 0) {
            dispTitle = [dispTitle stringByAppendingString:[self.titleText substringFromIndex:dispTitle.length - keepLeft - 1 + 1]];
        }
    }
    [dispTitle drawAtPoint:NSMakePoint(kHUDPadding, y) withAttributes:titleAttrs];

    // 复制按钮（右侧）
    NSRect btnRect = self.copyButtonRect;
    if (NSWidth(btnRect) > 0) {
        NSBezierPath *btnBg = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:3 yRadius:3];
        [[NSColor colorWithCalibratedWhite:1 alpha:0.12] setFill];
        [btnBg fill];
        NSString *btnText = @"\u2398"; // ⎘
        NSDictionary *btnAttrs = @{NSFontAttributeName: [BrowserDOMInspectorHUDView buttonFont],
                                   NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.8 alpha:1.0]};
        NSSize btnSize = [btnText sizeWithAttributes:btnAttrs];
        CGFloat btnX = NSMinX(btnRect) + (NSWidth(btnRect) - btnSize.width) / 2;
        CGFloat btnY = NSMinY(btnRect) + (NSHeight(btnRect) - btnSize.height) / 2;
        [btnText drawAtPoint:NSMakePoint(btnX, btnY) withAttributes:btnAttrs];
    }

    // 副标题行（几何信息）
    if (self.subtitleText.length > 0) {
        y -= kHUDRowHeight;
        NSFont *subFont = [BrowserDOMInspectorHUDView subtitleFont];
        NSColor *subColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
        NSDictionary *subAttrs = @{NSFontAttributeName: subFont, NSForegroundColorAttributeName: subColor};
        NSString *sub = self.subtitleText;
        CGFloat subMaxW = w - kHUDPadding * 2;
        while (sub.length > 4 && [sub sizeWithAttributes:subAttrs].width > subMaxW) {
            sub = [sub substringToIndex:sub.length - 1];
        }
        if (sub.length < self.subtitleText.length) sub = [sub stringByAppendingString:@"\u2026"];
        [sub drawAtPoint:NSMakePoint(kHUDPadding, y) withAttributes:subAttrs];
    }

    // 属性行
    NSFont *rowFont = [BrowserDOMInspectorHUDView rowFont];
    NSColor *rowColor = [NSColor colorWithCalibratedWhite:0.72 alpha:1.0];
    NSDictionary *rowAttrs = @{NSFontAttributeName: rowFont, NSForegroundColorAttributeName: rowColor};
    y -= 4;
    for (NSString *row in self.attributeRows) {
        y -= kHUDRowHeight;
        if (y < kHUDPadding) break;
        NSString *disp = row;
        CGFloat maxW = w - kHUDPadding * 2;
        while (disp.length > 4 && [disp sizeWithAttributes:rowAttrs].width > maxW) {
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
    [host addSubview:view positioned:NSWindowAbove relativeTo:nil];
    self.view = view;
    return view;
}

- (void)showSnapshot:(NSDictionary *)snapshot
   geometryInContent:(NSRect)geometry
     webViewInContent:(NSRect)webViewRect
            inWindow:(NSWindow *)window {
    if (!snapshot || !window) {
        [self hide];
        return;
    }
    BrowserDOMInspectorHUDView *view = [self ensureViewForWindow:window];
    [window.contentView addSubview:view positioned:NSWindowAbove relativeTo:nil];

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
    view.attributeRows = rows;

    NSSize size = [self contentSizeForView:view];
    [view setFrameSize:size];
    view.copyButtonRect = NSMakeRect(size.width - 40.0, kHUDPadding, 24.0, 20.0);
    view.frame = [self frameForGeometry:geometry
                          webViewRect:webViewRect
                           contentSize:size
                              inWindow:window];
    view.hidden = NO;
    view.alphaValue = 1.0;
    [view setNeedsDisplay:YES];
    [view displayIfNeeded];
    self.pendingSelector = selector;
}

- (NSSize)contentSizeForView:(BrowserDOMInspectorHUDView *)view {
    NSFont *titleFont = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold];
    NSFont *bodyFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    CGFloat width = [view.titleText sizeWithAttributes:@{NSFontAttributeName: titleFont}].width;
    for (NSString *row in view.attributeRows) {
        width = MAX(width, [row sizeWithAttributes:@{NSFontAttributeName: bodyFont}].width);
    }
    width = MIN(ceil(width) + kHUDPadding * 2 + 46, kHUDMaxWidth);
    CGFloat height = kHUDPadding * 2 + kHUDTitleHeight;
    if (view.subtitleText.length > 0) height += kHUDRowHeight;
    height += view.attributeRows.count * kHUDRowHeight;
    return NSMakeSize(width, height);
}

/// geometry 与 webViewRect 均为 contentView 坐标（下原点）；HUD view 为 flipped（上原点）。
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
    self.pendingSelector = nil;
}

- (void)dealloc {
    [_view removeFromSuperview];
}

@end
