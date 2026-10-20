#import "BrowserDOMInspectorHUD.h"
#import "SBTextView.h"
#import <WebKit/WebKit.h>

static const CGFloat kHUDMaxWidth = 960.0;
static const CGFloat kHUDPadding = 10.0;
static const CGFloat kHUDTitleHeight = 20.0;
static const CGFloat kHUDRowHeight = 15.0;
static const CGFloat kHUDIconButton = 22.0;
static const CGFloat kHUDOnionItemH = 18.0;
static const CGFloat kHUDOnionWidth = 92.0;
static const CGFloat kHUDOnionGap = 1.0;
static const CGFloat kHUDResizeEdge = 6.0;
static const CGFloat kHUDMinResizeWidth = 280.0;
static const CGFloat kHUDMinResizeHeight = 120.0;
static const NSUInteger kHUDHTMLCollapsedMaxLines = 3;

typedef NS_OPTIONS(NSUInteger, MeoHUDResizeMask) {
    MeoHUDResizeNone = 0,
    MeoHUDResizeMinX = 1 << 0, // 左
    MeoHUDResizeMaxX = 1 << 1, // 右
    MeoHUDResizeMinY = 1 << 2, // 下（superview 坐标）
    MeoHUDResizeMaxY = 1 << 3, // 上（superview 坐标）
};
static NSString * const kMeoCopySegmentAttr = @"MeoDOMInspectorCopySegment";
static NSString * const kMeoExpandHTMLAttr = @"MeoDOMInspectorExpandHTML";
static NSString * const kMeoCollapseHTMLAttr = @"MeoDOMInspectorCollapseHTML";
static NSString * const kMeoHTMLEllipsis = @"…";
/// 展开态 HTML 上方的收起控件文案（与省略号同为行内可点链）。
static NSString * const kMeoHTMLCollapseLabel = @"▲ 收起";

#pragma mark - Segment Text View

@interface MeoDOMInspectorSegmentTextView : SBTextView
@property (nonatomic, copy, nullable) void (^onSegmentCopied)(NSString *segment);
@property (nonatomic, copy, nullable) void (^onExpandHTML)(void);
@property (nonatomic, copy, nullable) void (^onCollapseHTML)(void);
@end

@implementation MeoDOMInspectorSegmentTextView

- (void)mouseDown:(NSEvent *)event {
    NSLayoutManager *lm = self.layoutManager;
    NSTextContainer *tc = self.textContainer;
    if (!lm || !tc || self.string.length == 0) {
        [super mouseDown:event];
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    p.x -= self.textContainerOrigin.x;
    p.y -= self.textContainerOrigin.y;
    NSUInteger glyphIndex = [lm glyphIndexForPoint:p inTextContainer:tc
                           fractionOfDistanceThroughGlyph:NULL];
    NSUInteger charIndex = [lm characterIndexForGlyphAtIndex:glyphIndex];
    if (charIndex >= self.string.length) {
        [super mouseDown:event];
        return;
    }
    NSRange eff = NSMakeRange(0, 0);
    if ([self.textStorage attribute:kMeoExpandHTMLAttr atIndex:charIndex effectiveRange:&eff]) {
        if (self.onExpandHTML) self.onExpandHTML();
        return;
    }
    if ([self.textStorage attribute:kMeoCollapseHTMLAttr atIndex:charIndex effectiveRange:&eff]) {
        if (self.onCollapseHTML) self.onCollapseHTML();
        return;
    }
    NSString *segment = [self.textStorage attribute:kMeoCopySegmentAttr
                                            atIndex:charIndex
                                     effectiveRange:&eff];
    if (![segment isKindOfClass:[NSString class]] || segment.length == 0) {
        [super mouseDown:event];
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:segment forType:NSPasteboardTypeString];

    // 短暂高亮反馈
    NSRange flash = eff;
    [self.textStorage addAttribute:NSBackgroundColorAttributeName
                             value:[NSColor colorWithCalibratedRed:0.25 green:0.55 blue:1.0 alpha:0.35]
                             range:flash];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (NSMaxRange(flash) <= self.textStorage.length) {
            [self.textStorage removeAttribute:NSBackgroundColorAttributeName range:flash];
        }
    });
    if (self.onSegmentCopied) self.onSegmentCopied(segment);
}

- (void)addHandCursorForAttribute:(NSString *)attrName
                          storage:(NSTextStorage *)storage
                    layoutManager:(NSLayoutManager *)lm
                    textContainer:(NSTextContainer *)tc {
    NSUInteger idx = 0;
    while (idx < storage.length) {
        NSRange eff = NSMakeRange(0, 0);
        id val = [storage attribute:attrName atIndex:idx effectiveRange:&eff];
        if (val) {
            NSRect rect = [lm boundingRectForGlyphRange:[lm glyphRangeForCharacterRange:eff
                                                                   actualCharacterRange:NULL]
                                        inTextContainer:tc];
            rect.origin.x += self.textContainerOrigin.x;
            rect.origin.y += self.textContainerOrigin.y;
            [self addCursorRect:rect cursor:[NSCursor pointingHandCursor]];
            idx = NSMaxRange(eff);
        } else {
            idx = (eff.length > 0) ? NSMaxRange(eff) : idx + 1;
        }
    }
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (self.string.length == 0) return;
    NSTextStorage *storage = self.textStorage;
    NSLayoutManager *lm = self.layoutManager;
    NSTextContainer *tc = self.textContainer;
    if (!lm || !tc) return;
    [self addHandCursorForAttribute:kMeoExpandHTMLAttr storage:storage layoutManager:lm textContainer:tc];
    [self addHandCursorForAttribute:kMeoCollapseHTMLAttr storage:storage layoutManager:lm textContainer:tc];
    NSUInteger idx = 0;
    while (idx < storage.length) {
        NSRange eff = NSMakeRange(0, 0);
        id seg = [storage attribute:kMeoCopySegmentAttr atIndex:idx effectiveRange:&eff];
        if ([seg isKindOfClass:[NSString class]] && [(NSString *)seg length] > 0) {
            NSRect rect = [lm boundingRectForGlyphRange:[lm glyphRangeForCharacterRange:eff
                                                                   actualCharacterRange:NULL]
                                        inTextContainer:tc];
            rect.origin.x += self.textContainerOrigin.x;
            rect.origin.y += self.textContainerOrigin.y;
            [self addCursorRect:rect cursor:[NSCursor pointingHandCursor]];
            idx = NSMaxRange(eff);
        } else {
            idx = (eff.length > 0) ? NSMaxRange(eff) : idx + 1;
        }
    }
}

@end

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
@property (nonatomic, strong) MeoDOMInspectorSegmentTextView *bodyTextView;
@property (nonatomic, strong) NSView *onionBar;
@property (nonatomic, strong) NSMutableArray<NSButton *> *onionButtons;
@property (nonatomic, assign) BOOL draggingBubble;
@property (nonatomic, assign) NSPoint dragMouseInSuperview;
@property (nonatomic, assign) NSPoint dragFrameOrigin;
@property (nonatomic, assign) MeoHUDResizeMask resizingMask;
@property (nonatomic, assign) NSRect resizeStartFrame;
@property (nonatomic, assign) NSPoint resizeStartMouseInSuperview;
- (NSRect)clampedFrame:(NSRect)frame inSuperview:(NSView *)superview;
- (CGFloat)dragChromeHeight;
- (MeoHUDResizeMask)resizeMaskAtPoint:(NSPoint)local;
@end

@implementation BrowserDOMInspectorHUDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleText = @"";
        _subtitleText = @"";
        _htmlPreview = @"";
        _htmlPreviewExpanded = NO;
        _attributeRows = @[];
        _onionLabels = @[];
        _selectedOnionIndex = NSNotFound;
        _pinnedAppearance = NO;
        _userRepositioned = NO;
        _userResized = NO;
        _resizingMask = MeoHUDResizeNone;
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

    self.bodyTextView = [[MeoDOMInspectorSegmentTextView alloc] initWithFrame:NSZeroRect];
    self.bodyTextView.editable = NO;
    self.bodyTextView.selectable = YES;
    self.bodyTextView.drawsBackground = NO;
    self.bodyTextView.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    self.bodyTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.bodyTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak typeof(self) weakSelf = self;
    self.bodyTextView.onSegmentCopied = ^(NSString *segment) {
        if (weakSelf.onCopiedSegment) weakSelf.onCopiedSegment(segment);
    };
    void (^toggleHTMLExpanded)(BOOL) = ^(BOOL expanded) {
        if (weakSelf.htmlPreviewExpanded == expanded) return;
        weakSelf.htmlPreviewExpanded = expanded;
        [weakSelf reloadPinnedContent];
        if (weakSelf.onContentSizeMayChange) weakSelf.onContentSizeMayChange();
        // 折叠后滚回顶部，避免仍停在展开时的滚动位置。
        if (!expanded) {
            [weakSelf.scrollView.contentView scrollToPoint:NSZeroPoint];
            [weakSelf.scrollView reflectScrolledClipView:weakSelf.scrollView.contentView];
        }
    };
    self.bodyTextView.onExpandHTML = ^{
        toggleHTMLExpanded(YES);
    };
    self.bodyTextView.onCollapseHTML = ^{
        toggleHTMLExpanded(NO);
    };

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
        self.userRepositioned = NO;
        self.draggingBubble = NO;
    }
    [self layoutChrome];
    [self.window invalidateCursorRectsForView:self];
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

- (NSDictionary *)attrsWithFont:(NSFont *)font color:(NSColor *)color {
    return @{
        NSFontAttributeName: font ?: [BrowserDOMInspectorHUDView rowFont],
        NSForegroundColorAttributeName: color,
    };
}

/// 将 `name="value"` / `selector=…` 拆成带颜色的富文本。
- (NSAttributedString *)attributedAttributeRow:(NSString *)row {
    NSFont *font = [BrowserDOMInspectorHUDView rowFont];
    NSColor *nameColor = [NSColor colorWithCalibratedRed:0.45 green:0.78 blue:1.00 alpha:1.0];
    NSColor *eqColor = [NSColor colorWithCalibratedWhite:0.50 alpha:1.0];
    NSColor *quoteColor = [NSColor colorWithCalibratedRed:0.70 green:0.70 blue:0.45 alpha:1.0];
    NSColor *valueColor = [NSColor colorWithCalibratedRed:0.55 green:0.90 blue:0.55 alpha:1.0];
    NSColor *plainColor = [NSColor colorWithCalibratedWhite:0.80 alpha:1.0];

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (row.length == 0) {
        return out;
    }
    NSRange eq = [row rangeOfString:@"="];
    if (eq.location == NSNotFound) {
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:row attributes:[self attrsWithFont:font color:plainColor]]];
        return out;
    }
    NSString *name = [row substringToIndex:eq.location];
    NSString *rest = [row substringFromIndex:eq.location + 1];
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:name attributes:[self attrsWithFont:font color:nameColor]]];
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"=" attributes:[self attrsWithFont:font color:eqColor]]];

    if (rest.length >= 2 && [rest hasPrefix:@"\""] && [rest hasSuffix:@"\""]) {
        NSString *inner = [rest substringWithRange:NSMakeRange(1, rest.length - 2)];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"\"" attributes:[self attrsWithFont:font color:quoteColor]]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:inner attributes:[self attrsWithFont:font color:valueColor]]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"\"" attributes:[self attrsWithFont:font color:quoteColor]]];
    } else {
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:rest attributes:[self attrsWithFont:font color:valueColor]]];
    }
    return out;
}

- (void)markCopySegmentIn:(NSMutableAttributedString *)text
                     range:(NSRange)absRange
                   payload:(NSString *)payload {
    if (absRange.length == 0 || payload.length == 0) return;
    [text addAttribute:kMeoCopySegmentAttr value:payload range:absRange];
    [text addAttribute:NSUnderlineStyleAttributeName
                 value:@(NSUnderlineStyleSingle | NSUnderlineStylePatternDot)
                 range:absRange];
    [text addAttribute:NSUnderlineColorAttributeName
                 value:[NSColor colorWithCalibratedWhite:1.0 alpha:0.28]
                 range:absRange];
    [text addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:absRange];
}

/// 按 = / "" / [] 切段，段内文字可点击复制（分隔符本身不点）。
- (void)annotateCopySegmentsIn:(NSMutableAttributedString *)text range:(NSRange)range {
    if (range.length == 0 || NSMaxRange(range) > text.length) return;
    NSString *s = [text.string substringWithRange:range];
    NSUInteger i = 0;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    void (^mark)(NSUInteger, NSUInteger) = ^(NSUInteger locInS, NSUInteger len) {
        if (len == 0) return;
        NSString *seg = [s substringWithRange:NSMakeRange(locInS, len)];
        // 去掉段首尾空白
        NSUInteger trimStart = 0;
        while (trimStart < len && [ws characterIsMember:[seg characterAtIndex:trimStart]]) trimStart++;
        NSUInteger trimEnd = len;
        while (trimEnd > trimStart && [ws characterIsMember:[seg characterAtIndex:trimEnd - 1]]) trimEnd--;
        if (trimEnd <= trimStart) return;
        NSRange abs = NSMakeRange(range.location + locInS + trimStart, trimEnd - trimStart);
        NSString *payload = [s substringWithRange:NSMakeRange(locInS + trimStart, trimEnd - trimStart)];
        [self markCopySegmentIn:text range:abs payload:payload];
    };

    while (i < s.length) {
        unichar c = [s characterAtIndex:i];
        if ([ws characterIsMember:c] || c == '=' || c == ']') {
            i++;
            continue;
        }
        if (c == '"') {
            // 引号内继续按 = / [] 拆段，如 name="row[mediatype]" → name / row / mediatype
            NSUInteger start = i + 1;
            NSUInteger end = start;
            while (end < s.length && [s characterAtIndex:end] != '"') end++;
            if (end > start) {
                [self annotateCopySegmentsIn:text
                                       range:NSMakeRange(range.location + start, end - start)];
            }
            i = (end < s.length) ? end + 1 : end;
            continue;
        }
        if (c == '[') {
            // 方括号内若还有嵌套结构，同样递归拆分
            NSUInteger start = i + 1;
            NSUInteger end = start;
            NSInteger depth = 1;
            while (end < s.length && depth > 0) {
                unichar x = [s characterAtIndex:end];
                if (x == '[') depth++;
                else if (x == ']') {
                    depth--;
                    if (depth == 0) break;
                }
                end++;
            }
            if (end > start) {
                BOOL hasInnerDelim = NO;
                for (NSUInteger k = start; k < end; k++) {
                    unichar x = [s characterAtIndex:k];
                    if (x == '=' || x == '"' || x == '[') { hasInnerDelim = YES; break; }
                }
                if (hasInnerDelim) {
                    [self annotateCopySegmentsIn:text
                                           range:NSMakeRange(range.location + start, end - start)];
                } else {
                    mark(start, end - start);
                }
            }
            i = (end < s.length && [s characterAtIndex:end] == ']') ? end + 1 : end;
            continue;
        }
        // 普通段：直到 = " [ 或换行
        NSUInteger start = i;
        while (i < s.length) {
            unichar x = [s characterAtIndex:i];
            if (x == '=' || x == '"' || x == '[' || x == '\n' || x == '\r') break;
            i++;
        }
        mark(start, i - start);
    }
}

/// HTML 预览按标签结构切段：
/// `<div class="th-inner">任务名称(mtasksname)</div>`
/// → div / class / th-inner / 任务名称 / mtasksname / div
- (void)annotateHTMLCopySegmentsIn:(NSMutableAttributedString *)text range:(NSRange)range {
    if (range.length == 0 || NSMaxRange(range) > text.length) return;
    NSString *s = [text.string substringWithRange:range];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    // 文本节点内再拆：空白与 ()[]{}<>/"'=
    NSCharacterSet *textDelims = [NSCharacterSet characterSetWithCharactersInString:@"()[]{}<>/\"'="];

    void (^mark)(NSUInteger, NSUInteger) = ^(NSUInteger locInS, NSUInteger len) {
        if (len == 0) return;
        NSUInteger trimStart = 0;
        NSUInteger trimEnd = len;
        while (trimStart < trimEnd &&
               [ws characterIsMember:[s characterAtIndex:locInS + trimStart]]) {
            trimStart++;
        }
        while (trimEnd > trimStart &&
               [ws characterIsMember:[s characterAtIndex:locInS + trimEnd - 1]]) {
            trimEnd--;
        }
        if (trimEnd <= trimStart) return;
        NSRange abs = NSMakeRange(range.location + locInS + trimStart, trimEnd - trimStart);
        NSString *payload = [s substringWithRange:NSMakeRange(locInS + trimStart, trimEnd - trimStart)];
        [self markCopySegmentIn:text range:abs payload:payload];
    };

    void (^markTextRuns)(NSUInteger, NSUInteger) = ^(NSUInteger locInS, NSUInteger len) {
        NSUInteger j = locInS;
        NSUInteger end = locInS + len;
        while (j < end) {
            unichar c = [s characterAtIndex:j];
            if ([ws characterIsMember:c] || [textDelims characterIsMember:c]) {
                j++;
                continue;
            }
            NSUInteger start = j;
            while (j < end) {
                unichar x = [s characterAtIndex:j];
                if ([ws characterIsMember:x] || [textDelims characterIsMember:x]) break;
                j++;
            }
            mark(start, j - start);
        }
    };

    NSUInteger i = 0;
    while (i < s.length) {
        unichar c = [s characterAtIndex:i];
        if (c == '<') {
            // 跳过注释 / DOCTYPE
            if (i + 3 < s.length &&
                [s characterAtIndex:i + 1] == '!' &&
                [s characterAtIndex:i + 2] == '-' &&
                [s characterAtIndex:i + 3] == '-') {
                NSRange close = [s rangeOfString:@"-->" options:0
                                           range:NSMakeRange(i + 4, s.length - (i + 4))];
                i = (close.location != NSNotFound) ? NSMaxRange(close) : s.length;
                continue;
            }
            i++; // '<'
            // 可选 '/'
            if (i < s.length && [s characterAtIndex:i] == '/') i++;
            // 标签名
            NSUInteger nameStart = i;
            while (i < s.length) {
                unichar x = [s characterAtIndex:i];
                if ([ws characterIsMember:x] || x == '>' || x == '/') break;
                i++;
            }
            mark(nameStart, i - nameStart);
            // 属性区直到 '>'
            while (i < s.length) {
                unichar x = [s characterAtIndex:i];
                if (x == '>') {
                    i++;
                    break;
                }
                if (x == '/') {
                    i++;
                    continue;
                }
                if ([ws characterIsMember:x] || x == '=') {
                    i++;
                    continue;
                }
                if (x == '"' || x == '\'') {
                    unichar quote = x;
                    i++;
                    NSUInteger vStart = i;
                    while (i < s.length && [s characterAtIndex:i] != quote) i++;
                    // 引号内按空白拆（class 多值）；再对每段按 ()[] 等拆
                    NSUInteger v = vStart;
                    NSUInteger vEnd = i;
                    while (v < vEnd) {
                        unichar y = [s characterAtIndex:v];
                        if ([ws characterIsMember:y]) {
                            v++;
                            continue;
                        }
                        NSUInteger t0 = v;
                        while (v < vEnd && ![ws characterIsMember:[s characterAtIndex:v]]) v++;
                        markTextRuns(t0, v - t0);
                    }
                    if (i < s.length) i++; // closing quote
                    continue;
                }
                // 属性名或无引号值
                NSUInteger aStart = i;
                while (i < s.length) {
                    unichar y = [s characterAtIndex:i];
                    if ([ws characterIsMember:y] || y == '=' || y == '>' || y == '/' ||
                        y == '"' || y == '\'') {
                        break;
                    }
                    i++;
                }
                mark(aStart, i - aStart);
            }
            continue;
        }
        // 文本节点：直到下一个 '<'
        NSUInteger tStart = i;
        while (i < s.length && [s characterAtIndex:i] != '<') i++;
        markTextRuns(tStart, i - tStart);
    }
}

/// 在给定宽度下，HTML 是否超过 maxLines 行。
- (BOOL)html:(NSString *)html exceedsLines:(NSUInteger)maxLines width:(CGFloat)width font:(NSFont *)font {
    if (html.length == 0 || width < 8) return NO;
    NSDictionary *attrs = @{NSFontAttributeName: font};
    NSRect rect = [html boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:attrs];
    CGFloat lineH = MAX(font.boundingRectForFont.size.height, kHUDRowHeight);
    return ceil(rect.size.height) > (CGFloat)maxLines * lineH + 0.5;
}

/// 折叠为最多 maxLines 行；若需截断则末尾带 `…`（由调用方单独标注点击展开）。
- (NSString *)collapsedHTML:(NSString *)html
                  maxLines:(NSUInteger)maxLines
                     width:(CGFloat)width
                      font:(NSFont *)font
                needsEllipsis:(BOOL *)needsEllipsisOut {
    if (needsEllipsisOut) *needsEllipsisOut = NO;
    if (html.length == 0) return @"";
    if (![self html:html exceedsLines:maxLines width:width font:font]) {
        return html;
    }
    NSDictionary *attrs = @{NSFontAttributeName: font};
    CGFloat lineH = MAX(font.boundingRectForFont.size.height, kHUDRowHeight);
    CGFloat maxH = (CGFloat)maxLines * lineH + 0.5;
    NSUInteger lo = 0, hi = html.length, best = 0;
    while (lo <= hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        NSString *cand = [[html substringToIndex:mid] stringByAppendingString:kMeoHTMLEllipsis];
        NSRect rect = [cand boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:attrs];
        if (rect.size.height <= maxH) {
            best = mid;
            lo = mid + 1;
        } else if (mid == 0) {
            break;
        } else {
            hi = mid - 1;
        }
    }
    if (needsEllipsisOut) *needsEllipsisOut = YES;
    return [[html substringToIndex:best] stringByAppendingString:kMeoHTMLEllipsis];
}

- (CGFloat)htmlPreviewContentWidth {
    CGFloat onionW = [self onionColumnWidth];
    CGFloat w = NSWidth(self.bounds);
    if (w < 40) w = kHUDMaxWidth;
    CGFloat bodyX = kHUDPadding + (onionW > 0 ? onionW + 8 : 0);
    return MAX(80.0, w - bodyX - kHUDPadding - 8.0);
}

- (void)reloadPinnedContent {
    if (!self.pinnedAppearance) return;
    NSFont *titleFont = [BrowserDOMInspectorHUDView titleFont];
    NSFont *subFont = [BrowserDOMInspectorHUDView subtitleFont];
    NSFont *rowFont = [BrowserDOMInspectorHUDView rowFont];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];

    NSString *title = self.titleText.length > 0 ? self.titleText : @"";
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:[title stringByAppendingString:@"\n"]
            attributes:[self attrsWithFont:titleFont
                                     color:[NSColor colorWithCalibratedWhite:0.95 alpha:1.0]]]];
    if (self.subtitleText.length > 0) {
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:[self.subtitleText stringByAppendingString:@"\n"]
                attributes:[self attrsWithFont:subFont
                                         color:[NSColor colorWithCalibratedWhite:0.55 alpha:1.0]]]];
    }
    if (self.htmlPreview.length > 0) {
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"────────────────\n"
                attributes:[self attrsWithFont:subFont
                                         color:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]]]];
        NSColor *htmlColor = [NSColor colorWithCalibratedRed:0.95 green:0.82 blue:0.55 alpha:1.0];
        NSColor *linkColor = [NSColor colorWithCalibratedRed:0.45 green:0.78 blue:1.00 alpha:1.0];
        CGFloat htmlW = [self htmlPreviewContentWidth];
        // 展开态：HTML 上方放「▲ 收起」，与折叠态末尾「…」形成一对对称操作。
        if (self.htmlPreviewExpanded) {
            NSUInteger collapseLoc = text.length;
            [text appendAttributedString:[[NSAttributedString alloc]
                initWithString:[kMeoHTMLCollapseLabel stringByAppendingString:@"\n"]
                    attributes:[self attrsWithFont:subFont color:linkColor]]];
            NSRange collapseRange = NSMakeRange(collapseLoc, kMeoHTMLCollapseLabel.length);
            [text addAttribute:kMeoCollapseHTMLAttr value:@YES range:collapseRange];
            [text addAttribute:NSUnderlineStyleAttributeName
                         value:@(NSUnderlineStyleSingle)
                         range:collapseRange];
            [text addAttribute:NSCursorAttributeName
                         value:[NSCursor pointingHandCursor]
                         range:collapseRange];
            NSUInteger htmlStart = text.length;
            [text appendAttributedString:[[NSAttributedString alloc]
                initWithString:[self.htmlPreview stringByAppendingString:@"\n"]
                    attributes:[self attrsWithFont:rowFont color:htmlColor]]];
            [self annotateHTMLCopySegmentsIn:text
                                       range:NSMakeRange(htmlStart, self.htmlPreview.length)];
        } else {
            BOOL showEllipsis = NO;
            NSString *displayHTML = [self collapsedHTML:self.htmlPreview
                                               maxLines:kHUDHTMLCollapsedMaxLines
                                                  width:htmlW
                                                   font:rowFont
                                          needsEllipsis:&showEllipsis];
            NSUInteger htmlStart = text.length;
            if (showEllipsis && [displayHTML hasSuffix:kMeoHTMLEllipsis]) {
                NSString *prefix = [displayHTML substringToIndex:displayHTML.length - kMeoHTMLEllipsis.length];
                [text appendAttributedString:[[NSAttributedString alloc]
                    initWithString:prefix
                        attributes:[self attrsWithFont:rowFont color:htmlColor]]];
                NSUInteger ellipsisLoc = text.length;
                [text appendAttributedString:[[NSAttributedString alloc]
                    initWithString:kMeoHTMLEllipsis
                        attributes:[self attrsWithFont:rowFont color:linkColor]]];
                NSRange ellipsisRange = NSMakeRange(ellipsisLoc, kMeoHTMLEllipsis.length);
                [text addAttribute:kMeoExpandHTMLAttr value:@YES range:ellipsisRange];
                [text addAttribute:NSUnderlineStyleAttributeName
                             value:@(NSUnderlineStyleSingle)
                             range:ellipsisRange];
                [text addAttribute:NSCursorAttributeName
                             value:[NSCursor pointingHandCursor]
                             range:ellipsisRange];
                if (prefix.length > 0) {
                    [self annotateHTMLCopySegmentsIn:text
                                               range:NSMakeRange(htmlStart, prefix.length)];
                }
            } else {
                [text appendAttributedString:[[NSAttributedString alloc]
                    initWithString:displayHTML
                        attributes:[self attrsWithFont:rowFont color:htmlColor]]];
                [self annotateHTMLCopySegmentsIn:text
                                           range:NSMakeRange(htmlStart, displayHTML.length)];
            }
            [text appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n"
                    attributes:[self attrsWithFont:rowFont color:htmlColor]]];
        }
    }
    NSUInteger attrsStart = NSNotFound;
    if (self.attributeRows.count > 0) {
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"────────────────\n"
                attributes:[self attrsWithFont:subFont
                                         color:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]]]];
        attrsStart = text.length;
        NSUInteger i = 0;
        for (NSString *row in self.attributeRows) {
            [text appendAttributedString:[self attributedAttributeRow:row]];
            BOOL last = (++i >= self.attributeRows.count);
            [text appendAttributedString:[[NSAttributedString alloc]
                initWithString:(last ? @"\n" : @"\n\n")
                    attributes:[self attrsWithFont:[BrowserDOMInspectorHUDView rowFont]
                                             color:[NSColor whiteColor]]]];
        }
        [self annotateCopySegmentsIn:text
                               range:NSMakeRange(attrsStart, text.length - attrsStart)];
    }
    [self.bodyTextView.textStorage setAttributedString:text];
    [self.bodyTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.bodyTextView.window invalidateCursorRectsForView:self.bodyTextView];
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
    // 钉住：洋葱列必须整体在拖拽区以下，避免第一个节点点不到。
    CGFloat top;
    if (self.pinnedAppearance) {
        top = [self dragChromeHeight] + 4.0;
    } else {
        top = kHUDPadding;
    }
    CGFloat onionH = MAX(0, h - top - kHUDPadding);
    self.onionBar.frame = NSMakeRect(kHUDPadding, top, onionW, onionH);
    [self layoutOnionButtonsInBar];

    if (self.pinnedAppearance) {
        CGFloat bodyTop = [self dragChromeHeight] + 4.0;
        CGFloat bodyX = kHUDPadding + (onionW > 0 ? onionW + 8 : 0);
        CGFloat bodyW = MAX(0, w - bodyX - kHUDPadding);
        CGFloat bodyH = MAX(0, h - bodyTop - kHUDPadding);
        self.scrollView.frame = NSMakeRect(bodyX, bodyTop, bodyW, bodyH);
        self.bodyTextView.minSize = NSMakeSize(0, 0);
        self.bodyTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        NSUInteger lines = MAX(1, [[self.bodyTextView.string componentsSeparatedByCharactersInSet:
                                    [NSCharacterSet newlineCharacterSet]] count]);
        // 属性间空行后行距略松
        CGFloat textH = MAX(bodyH, lines * (kHUDRowHeight + 3));
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

/// 钉住态顶部拖拽条高度（不含按钮自身命中）。
- (CGFloat)dragChromeHeight {
    return kHUDPadding + kHUDIconButton + 6.0;
}

- (BOOL)pointInDragChrome:(NSPoint)local {
    if (!self.pinnedAppearance) return NO;
    if (local.y < 0 || local.y >= [self dragChromeHeight]) return NO;
    if (!self.selectorCopyButton.hidden && NSPointInRect(local, self.selectorCopyButton.frame)) {
        return NO;
    }
    if (!self.dismissButton.hidden && NSPointInRect(local, self.dismissButton.frame)) {
        return NO;
    }
    // 边缘改大小优先于整体拖动。
    if ([self resizeMaskAtPoint:local] != MeoHUDResizeNone) return NO;
    return YES;
}

/// 钉住态：四边四角可拖；视图 isFlipped，local.y=0 为视觉顶部。
- (MeoHUDResizeMask)resizeMaskAtPoint:(NSPoint)local {
    if (!self.pinnedAppearance) return MeoHUDResizeNone;
    NSRect b = self.bounds;
    if (!NSPointInRect(local, b)) return MeoHUDResizeNone;
    MeoHUDResizeMask mask = MeoHUDResizeNone;
    if (local.x <= kHUDResizeEdge) mask |= MeoHUDResizeMinX;
    if (local.x >= NSWidth(b) - kHUDResizeEdge) mask |= MeoHUDResizeMaxX;
    // flipped：顶部 → superview MaxY；底部 → MinY
    if (local.y <= kHUDResizeEdge) mask |= MeoHUDResizeMaxY;
    if (local.y >= NSHeight(b) - kHUDResizeEdge) mask |= MeoHUDResizeMinY;
    return mask;
}

- (NSCursor *)cursorForResizeMask:(MeoHUDResizeMask)mask {
    BOOL left = (mask & MeoHUDResizeMinX) != 0;
    BOOL right = (mask & MeoHUDResizeMaxX) != 0;
    BOOL bottom = (mask & MeoHUDResizeMinY) != 0;
    BOOL top = (mask & MeoHUDResizeMaxY) != 0;
    if ((left || right) && !(top || bottom)) return [NSCursor resizeLeftRightCursor];
    if ((top || bottom) && !(left || right)) return [NSCursor resizeUpDownCursor];
    // 四角：用对角语义光标（系统无公开对角时退回十字）。
    if ((left && top) || (right && bottom) || (left && bottom) || (right && top)) {
        return [NSCursor crosshairCursor];
    }
    return [NSCursor arrowCursor];
}

- (NSRect)clampedFrame:(NSRect)frame inSuperview:(NSView *)superview {
    if (!superview) return frame;
    NSRect bounds = superview.bounds;
    if (NSWidth(frame) > NSWidth(bounds)) frame.size.width = NSWidth(bounds);
    if (NSHeight(frame) > NSHeight(bounds)) frame.size.height = NSHeight(bounds);
    if (NSMinX(frame) < NSMinX(bounds)) frame.origin.x = NSMinX(bounds);
    if (NSMinY(frame) < NSMinY(bounds)) frame.origin.y = NSMinY(bounds);
    if (NSMaxX(frame) > NSMaxX(bounds)) frame.origin.x = NSMaxX(bounds) - NSWidth(frame);
    if (NSMaxY(frame) > NSMaxY(bounds)) frame.origin.y = NSMaxY(bounds) - NSHeight(frame);
    return frame;
}

- (NSRect)resizedFrameFromStart:(NSRect)start
                          delta:(NSPoint)delta
                           mask:(MeoHUDResizeMask)mask {
    NSRect frame = start;
    if (mask & MeoHUDResizeMinX) {
        frame.origin.x = start.origin.x + delta.x;
        frame.size.width = start.size.width - delta.x;
    }
    if (mask & MeoHUDResizeMaxX) {
        frame.size.width = start.size.width + delta.x;
    }
    if (mask & MeoHUDResizeMinY) {
        frame.origin.y = start.origin.y + delta.y;
        frame.size.height = start.size.height - delta.y;
    }
    if (mask & MeoHUDResizeMaxY) {
        frame.size.height = start.size.height + delta.y;
    }
    // 最小尺寸：若压得太小则钉住对边。
    if (NSWidth(frame) < kHUDMinResizeWidth) {
        if (mask & MeoHUDResizeMinX) {
            frame.origin.x = NSMaxX(start) - kHUDMinResizeWidth;
        }
        frame.size.width = kHUDMinResizeWidth;
    }
    if (NSHeight(frame) < kHUDMinResizeHeight) {
        if (mask & MeoHUDResizeMinY) {
            frame.origin.y = NSMaxY(start) - kHUDMinResizeHeight;
        }
        frame.size.height = kHUDMinResizeHeight;
    }
    return frame;
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.pinnedAppearance) {
        [super mouseDown:event];
        return;
    }
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    MeoHUDResizeMask resizeMask = [self resizeMaskAtPoint:local];
    if (resizeMask != MeoHUDResizeNone) {
        self.resizingMask = resizeMask;
        self.resizeStartFrame = self.frame;
        self.resizeStartMouseInSuperview =
            [self.superview convertPoint:event.locationInWindow fromView:nil];
        [[self cursorForResizeMask:resizeMask] push];
        return;
    }
    if (![self pointInDragChrome:local]) {
        [super mouseDown:event];
        return;
    }
    self.draggingBubble = YES;
    self.dragMouseInSuperview = [self.superview convertPoint:event.locationInWindow fromView:nil];
    self.dragFrameOrigin = self.frame.origin;
    [[NSCursor closedHandCursor] push];
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.resizingMask != MeoHUDResizeNone && self.superview) {
        NSPoint mouse = [self.superview convertPoint:event.locationInWindow fromView:nil];
        NSPoint delta = NSMakePoint(mouse.x - self.resizeStartMouseInSuperview.x,
                                    mouse.y - self.resizeStartMouseInSuperview.y);
        NSRect frame = [self resizedFrameFromStart:self.resizeStartFrame
                                             delta:delta
                                              mask:self.resizingMask];
        self.frame = [self clampedFrame:frame inSuperview:self.superview];
        self.userResized = YES;
        self.userRepositioned = YES;
        [self layoutChrome];
        [self.window invalidateCursorRectsForView:self];
        return;
    }
    if (!self.draggingBubble || !self.superview) {
        [super mouseDragged:event];
        return;
    }
    NSPoint mouse = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = mouse.x - self.dragMouseInSuperview.x;
    CGFloat dy = mouse.y - self.dragMouseInSuperview.y;
    NSRect frame = self.frame;
    frame.origin.x = self.dragFrameOrigin.x + dx;
    frame.origin.y = self.dragFrameOrigin.y + dy;
    self.frame = [self clampedFrame:frame inSuperview:self.superview];
    self.userRepositioned = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (self.resizingMask != MeoHUDResizeNone) {
        self.resizingMask = MeoHUDResizeNone;
        [NSCursor pop];
        [self layoutChrome];
        [self.window invalidateCursorRectsForView:self];
        return;
    }
    if (self.draggingBubble) {
        self.draggingBubble = NO;
        [NSCursor pop];
        return;
    }
    [super mouseUp:event];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (!self.pinnedAppearance) return;
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);
    CGFloat e = kHUDResizeEdge;
    // 四角优先
    [self addCursorRect:NSMakeRect(0, 0, e, e)
                 cursor:[self cursorForResizeMask:MeoHUDResizeMinX | MeoHUDResizeMaxY]];
    [self addCursorRect:NSMakeRect(w - e, 0, e, e)
                 cursor:[self cursorForResizeMask:MeoHUDResizeMaxX | MeoHUDResizeMaxY]];
    [self addCursorRect:NSMakeRect(0, h - e, e, e)
                 cursor:[self cursorForResizeMask:MeoHUDResizeMinX | MeoHUDResizeMinY]];
    [self addCursorRect:NSMakeRect(w - e, h - e, e, e)
                 cursor:[self cursorForResizeMask:MeoHUDResizeMaxX | MeoHUDResizeMinY]];
    // 四边
    [self addCursorRect:NSMakeRect(e, 0, w - 2 * e, e)
                 cursor:[NSCursor resizeUpDownCursor]];
    [self addCursorRect:NSMakeRect(e, h - e, w - 2 * e, e)
                 cursor:[NSCursor resizeUpDownCursor]];
    [self addCursorRect:NSMakeRect(0, e, e, h - 2 * e)
                 cursor:[NSCursor resizeLeftRightCursor]];
    [self addCursorRect:NSMakeRect(w - e, e, e, h - 2 * e)
                 cursor:[NSCursor resizeLeftRightCursor]];

    NSRect chrome = NSMakeRect(e, e, MAX(0, w - 2 * e), MAX(0, [self dragChromeHeight] - e));
    [self addCursorRect:chrome cursor:[NSCursor openHandCursor]];
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue < 0.01) return nil;
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(local, self.bounds)) return nil;
    if (self.pinnedAppearance) {
        // 边缘改大小优先于内部控件。
        if ([self resizeMaskAtPoint:local] != MeoHUDResizeNone) {
            return self;
        }
        // 顶部拖拽条优先归自己（按钮除外），便于拖动整块气泡。
        if ([self pointInDragChrome:local]) {
            return self;
        }
        if (!self.selectorCopyButton.hidden &&
            NSPointInRect(local, self.selectorCopyButton.frame)) {
            return [self.selectorCopyButton hitTest:point] ?: self.selectorCopyButton;
        }
        if (!self.dismissButton.hidden &&
            NSPointInRect(local, self.dismissButton.frame)) {
            return [self.dismissButton hitTest:point] ?: self.dismissButton;
        }
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

- (void)drawPanelBackgroundsInBounds:(NSRect)bounds {
    CGFloat w = NSWidth(bounds);
    CGFloat h = NSHeight(bounds);
    CGFloat radius = 8.0;
    NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    [clip addClip];

    // 底色
    [[NSColor colorWithCalibratedWhite:0.11 alpha:0.70] setFill];
    [clip fill];

    CGFloat onionW = [self onionColumnWidth];
    CGFloat bodyTop = self.pinnedAppearance ? [self dragChromeHeight] : 0;

    // 左侧节点区（偏冷蓝灰）
    if (onionW > 0) {
        NSRect left = NSMakeRect(0, bodyTop, onionW + kHUDPadding + 4, h - bodyTop);
        [[NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.24 alpha:0.78] setFill];
        NSRectFillUsingOperation(left, NSCompositingOperationSourceOver);
    }

    // 右侧属性区（偏暖深灰）
    CGFloat rightX = (onionW > 0) ? (onionW + kHUDPadding + 4) : 0;
    NSRect right = NSMakeRect(rightX, bodyTop, w - rightX, h - bodyTop);
    [[NSColor colorWithCalibratedRed:0.14 green:0.13 blue:0.12 alpha:0.55] setFill];
    NSRectFillUsingOperation(right, NSCompositingOperationSourceOver);

    // 左右分隔细线
    if (onionW > 0) {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.08] setStroke];
        NSBezierPath *div = [NSBezierPath bezierPath];
        [div moveToPoint:NSMakePoint(rightX + 0.5, bodyTop + 4)];
        [div lineToPoint:NSMakePoint(rightX + 0.5, h - 4)];
        div.lineWidth = 1.0;
        [div stroke];
    }

    // 顶部拖拽区（钉住态）：略亮的条带，与内容区分
    if (self.pinnedAppearance) {
        CGFloat chromeH = [self dragChromeHeight];
        NSRect chrome = NSMakeRect(0, 0, w, chromeH);
        [[NSColor colorWithCalibratedRed:0.18 green:0.20 blue:0.28 alpha:0.92] setFill];
        NSRectFillUsingOperation(chrome, NSCompositingOperationSourceOver);

        // 拖拽区底部分隔线
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.10] setStroke];
        NSBezierPath *chromeEdge = [NSBezierPath bezierPath];
        [chromeEdge moveToPoint:NSMakePoint(8, chromeH - 0.5)];
        [chromeEdge lineToPoint:NSMakePoint(w - 8, chromeH - 0.5)];
        chromeEdge.lineWidth = 1.0;
        [chromeEdge stroke];

        // 中央短把手提示
        CGFloat gripW = 28.0;
        CGFloat gripY = chromeH * 0.5;
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.22] setStroke];
        NSBezierPath *grip = [NSBezierPath bezierPath];
        [grip moveToPoint:NSMakePoint((w - gripW) * 0.5, gripY - 2)];
        [grip lineToPoint:NSMakePoint((w + gripW) * 0.5, gripY - 2)];
        [grip moveToPoint:NSMakePoint((w - gripW) * 0.5, gripY + 2)];
        [grip lineToPoint:NSMakePoint((w + gripW) * 0.5, gripY + 2)];
        grip.lineWidth = 1.5;
        grip.lineCapStyle = NSLineCapStyleRound;
        [grip stroke];
    }

    // 外轮廓细边（无底部橙色线）
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.12] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5, 0.5)
                                                           xRadius:radius yRadius:radius];
    border.lineWidth = 1.0;
    [border stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);

    [NSGraphicsContext saveGraphicsState];
    [self drawPanelBackgroundsInBounds:self.bounds];
    [NSGraphicsContext restoreGraphicsState];

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

    y += 2;
    CGFloat attrBottom = h - kHUDPadding;
    for (NSString *row in self.attributeRows) {
        if (y + kHUDRowHeight > attrBottom) break;
        NSAttributedString *colored = [self attributedAttributeRow:row];
        // 悬停态过长时截断展示。
        NSString *plain = colored.string;
        NSAttributedString *draw = colored;
        if ([plain sizeWithAttributes:@{NSFontAttributeName: [BrowserDOMInspectorHUDView rowFont]}].width > titleMaxW
            && plain.length > 4) {
            NSMutableAttributedString *trunc = [colored mutableCopy];
            while (trunc.length > 4 &&
                   [trunc.string sizeWithAttributes:@{NSFontAttributeName: [BrowserDOMInspectorHUDView rowFont]}].width > titleMaxW) {
                [trunc deleteCharactersInRange:NSMakeRange(trunc.length - 1, 1)];
            }
            [trunc appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\u2026"
                    attributes:[self attrsWithFont:[BrowserDOMInspectorHUDView rowFont]
                                             color:[NSColor colorWithCalibratedWhite:0.6 alpha:1.0]]]];
            draw = trunc;
        }
        [draw drawAtPoint:NSMakePoint(contentX, y)];
        y += kHUDRowHeight + 4; // 属性间距
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
    view.onCopiedSegment = ^(NSString *segment) {
        if (weakSelf.onCopiedSegment) weakSelf.onCopiedSegment(segment);
    };
    view.onSelectOnionIndex = ^(NSInteger index) {
        [weakSelf selectAncestorAtIndex:index];
    };
    view.onContentSizeMayChange = ^{
        BrowserDOMInspectorHUDView *v = weakSelf.view;
        NSWindow *win = weakSelf.hostWindow;
        if (!v || !win || v.hidden) return;
        // 用户已拖过大小：只重排内部，不改外框。
        if (v.userResized) {
            [v layoutChrome];
            [v setNeedsDisplay:YES];
            return;
        }
        NSSize size = [weakSelf contentSizeForView:v
                                            pinned:v.pinnedAppearance
                                          inWindow:win];
        v.frame = [weakSelf placedFrameForView:v
                                          size:size
                                      geometry:weakSelf.lastGeometry
                                   webViewRect:weakSelf.lastWebViewRect
                                      inWindow:win];
        [v layoutChrome];
        [v setNeedsDisplay:YES];
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
    BOOL hasClassAttr = NO;
    for (NSDictionary *attr in attributes) {
        if (![attr isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = [attr[@"name"] isKindOfClass:[NSString class]] ? attr[@"name"] : nil;
        NSString *value = [attr[@"value"] isKindOfClass:[NSString class]] ? attr[@"value"] : @"";
        if (name.length == 0) continue;
        if ([name isEqualToString:@"class"]) hasClassAttr = YES;
        // 全量展示：不截断、不跳过任何属性名。
        [rows addObject:[NSString stringWithFormat:@"%@=\"%@\"", name, value]];
    }
    // attributes 里若缺 class，用 scrub 后的 className 补上。
    if (!hasClassAttr && cls.length > 0) {
        NSUInteger insertAt = includeSelector && selector.length > 0 ? 1 : 0;
        [rows insertObject:[NSString stringWithFormat:@"class=\"%@\"", cls] atIndex:insertAt];
    }
    return rows;
}

- (NSString *)htmlPreviewForAncestor:(NSDictionary *)node {
    NSString *html = [node[@"outerHTML"] isKindOfClass:[NSString class]] ? node[@"outerHTML"] : @"";
    if (html.length > 0) return html;
    // 无 outerHTML 时用标签 + 文本拼一个可读预览。
    NSString *tag = [node[@"tagName"] isKindOfClass:[NSString class]] ? node[@"tagName"] : @"div";
    NSString *cls = [node[@"className"] isKindOfClass:[NSString class]] ? node[@"className"] : @"";
    NSString *elementID = [node[@"id"] isKindOfClass:[NSString class]] ? node[@"id"] : @"";
    NSDictionary *textObj = [node[@"text"] isKindOfClass:[NSDictionary class]] ? node[@"text"] : nil;
    NSString *own = [textObj[@"own"] isKindOfClass:[NSString class]] ? textObj[@"own"] : @"";
    NSMutableString *open = [NSMutableString stringWithFormat:@"<%@", tag];
    if (elementID.length > 0) [open appendFormat:@" id=\"%@\"", elementID];
    if (cls.length > 0) [open appendFormat:@" class=\"%@\"", cls];
    [open appendString:@">"];
    [open appendString:own];
    [open appendFormat:@"</%@>", tag];
    return open;
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
    view.htmlPreview = [self htmlPreviewForAncestor:node];
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

- (NSRect)placedFrameForView:(BrowserDOMInspectorHUDView *)view
                        size:(NSSize)size
                    geometry:(NSRect)geometry
                 webViewRect:(NSRect)webViewRect
                    inWindow:(NSWindow *)window {
    if (view.userRepositioned && view.pinnedAppearance) {
        NSRect frame = view.frame;
        frame.size = size;
        return [view clampedFrame:frame inSuperview:window.contentView];
    }
    return [self frameForGeometry:geometry
                      webViewRect:webViewRect
                       contentSize:size
                          inWindow:window];
}

- (void)selectAncestorAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.ancestors.count) return;
    self.selectedAncestorIndex = index;
    BrowserDOMInspectorHUDView *view = self.view;
    NSWindow *window = self.hostWindow;
    if (!view || !window) return;
    view.htmlPreviewExpanded = NO;
    [self applySelectedAncestorToView:view];
    NSSize size = view.userResized
        ? view.frame.size
        : [self contentSizeForView:view pinned:view.pinnedAppearance inWindow:window];
    view.frame = [self placedFrameForView:view
                                     size:size
                                 geometry:self.lastGeometry
                              webViewRect:self.lastWebViewRect
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
    NSInteger prevOnion = self.selectedAncestorIndex;
    self.ancestors = [self normalizedAncestorsFromSnapshot:snapshot];
    // 钉住刷新（后期渲染）时尽量保持当前洋葱选中；新悬停/新钉住落到叶子。
    if (pinned && view.pinnedAppearance && !view.hidden &&
        prevOnion >= 0 && prevOnion < (NSInteger)self.ancestors.count) {
        self.selectedAncestorIndex = prevOnion;
        // 钉住后期渲染刷新：保留 HTML 展开状态
    } else {
        self.selectedAncestorIndex = (NSInteger)self.ancestors.count - 1;
        view.htmlPreviewExpanded = NO;
    }

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSDictionary *node in self.ancestors) {
        [labels addObject:[self labelForAncestor:node]];
    }
    view.onionLabels = labels;

    [self applySelectedAncestorToView:view];
    // 悬停刷新时清掉用户拖拽/改大小；已钉住且用户拖过则保留。
    if (!pinned) {
        view.userRepositioned = NO;
        view.userResized = NO;
    }
    BOOL keepUserPos = pinned && view.pinnedAppearance && view.userRepositioned && !view.hidden;
    BOOL keepUserSize = pinned && view.pinnedAppearance && view.userResized && !view.hidden;
    view.pinnedAppearance = pinned;
    self.lastGeometry = geometry;
    self.lastWebViewRect = webViewRect;

    NSSize size = keepUserSize
        ? view.frame.size
        : [self contentSizeForView:view pinned:pinned inWindow:window];
    if (keepUserPos || keepUserSize) {
        view.frame = [self placedFrameForView:view
                                         size:size
                                     geometry:geometry
                                  webViewRect:webViewRect
                                     inWindow:window];
    } else {
        view.frame = [self frameForGeometry:geometry
                                webViewRect:webViewRect
                                 contentSize:size
                                    inWindow:window];
    }
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
    view.frame = [self placedFrameForView:view
                                     size:size
                                 geometry:self.lastGeometry
                              webViewRect:self.lastWebViewRect
                                 inWindow:window];
    [view reloadPinnedContent];
    [view setNeedsDisplay:YES];
}

- (NSSize)contentSizeForView:(BrowserDOMInspectorHUDView *)view
                      pinned:(BOOL)pinned
                    inWindow:(NSWindow *)window {
    (void)window;
    if (pinned && view.userResized && NSWidth(view.frame) > 1 && NSHeight(view.frame) > 1) {
        return view.frame.size;
    }
    NSFont *titleFont = [BrowserDOMInspectorHUDView titleFont];
    NSFont *bodyFont = [BrowserDOMInspectorHUDView rowFont];

    CGFloat contentW = [(view.titleText ?: @"") sizeWithAttributes:@{NSFontAttributeName: titleFont}].width;
    for (NSString *row in view.attributeRows) {
        contentW = MAX(contentW, [row sizeWithAttributes:@{NSFontAttributeName: bodyFont}].width);
    }

    CGFloat onionW = (view.onionLabels.count > 0) ? kHUDOnionWidth : 0;
    CGFloat trailing = pinned ? (kHUDIconButton * 2 + 20.0) : (kHUDIconButton + 16.0);
    CGFloat width = ceil(contentW) + kHUDPadding * 2 + trailing + (onionW > 0 ? onionW + 8 : 0);
    width = MIN(MAX(width, pinned ? 640.0 : 480.0), kHUDMaxWidth);

    CGFloat attrH = kHUDPadding * 2 + kHUDTitleHeight;
    if (view.subtitleText.length > 0) attrH += kHUDRowHeight;
    if (view.htmlPreview.length > 0) {
        NSUInteger htmlLines = kHUDHTMLCollapsedMaxLines;
        if (view.htmlPreviewExpanded) {
            CGFloat bodyW = MAX(80.0, width - kHUDPadding * 2 - (onionW > 0 ? onionW + 8 : 0) - 8.0);
            NSDictionary *htmlAttrs = @{NSFontAttributeName: bodyFont};
            NSRect htmlRect = [view.htmlPreview boundingRectWithSize:NSMakeSize(bodyW, CGFLOAT_MAX)
                                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                          attributes:htmlAttrs];
            CGFloat lineH = MAX(bodyFont.boundingRectForFont.size.height, kHUDRowHeight);
            htmlLines = MAX(1, (NSUInteger)ceil(htmlRect.size.height / lineH));
            htmlLines = MIN(htmlLines, 40); // 展开后也限制高度，其余靠滚动
            htmlLines += 1; // 「▲ 收起」一行
        }
        attrH += 8 + htmlLines * (kHUDRowHeight + 2);
    }
    // 属性行之间多留 4pt 间距（钉住态还有空行，高度按约 1.6 倍估算）
    CGFloat rowPitch = pinned ? (kHUDRowHeight * 1.7) : (kHUDRowHeight + 4.0);
    attrH += 4 + view.attributeRows.count * rowPitch;
    if (pinned) attrH += [view dragChromeHeight] + 8;

    CGFloat onionTop = pinned ? ([view dragChromeHeight] + 4.0) : kHUDPadding;
    CGFloat onionH = onionTop + kHUDPadding + view.onionLabels.count * (kHUDOnionItemH + kHUDOnionGap);
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
    CGFloat minX = webViewRect.size.width > 0 ? NSMinX(webViewRect) : NSMinX(content);
    CGFloat minY = webViewRect.size.height > 0 ? NSMinY(webViewRect) : NSMinY(content);
    CGFloat maxX = webViewRect.size.width > 0 ? NSMaxX(webViewRect) : NSMaxX(content);
    CGFloat maxY = webViewRect.size.height > 0 ? NSMaxY(webViewRect) : NSMaxY(content);
    if (maxX - minX < size.width) { minX = NSMinX(content); maxX = NSMaxX(content); }
    if (maxY - minY < size.height) { minY = NSMinY(content); maxY = NSMaxY(content); }

    // 锚在目标元素右下方，带间隙，避免挡在鼠标/元素正下方。
    static const CGFloat gapX = 18.0;
    static const CGFloat gapY = 16.0;
    NSRect target = geometry;
    CGFloat x = NSMaxX(target) + gapX;
    CGFloat y = NSMinY(target) - gapY - size.height; // AppKit：更低的 y = 视觉下方

    if (x + size.width > maxX) {
        // 右侧放不下：改到元素左侧
        x = NSMinX(target) - gapX - size.width;
    }
    if (x < minX) x = minX;
    if (x + size.width > maxX) x = maxX - size.width;

    if (y < minY) {
        // 下方放不下：改到元素上方偏右
        y = NSMaxY(target) + gapY;
    }
    if (y + size.height > maxY) {
        y = maxY - size.height;
    }
    if (y < minY) y = minY;

    return NSMakeRect(x, y, size.width, size.height);
}

- (void)hide {
    self.view.hidden = YES;
    self.view.userRepositioned = NO;
    self.view.userResized = NO;
    self.view.htmlPreviewExpanded = NO;
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
