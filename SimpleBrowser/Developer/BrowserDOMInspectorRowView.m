#import "BrowserDOMInspectorRowView.h"
#import "BrowserDOMValueSegmenter.h"

static const CGFloat kRowPadding = 4.0;
static const CGFloat kNameWidth = 116.0;
static const CGFloat kSegmentSpacing = 3.0;
static const CGFloat kSegmentHeight = 18.0;
static const CGFloat kSegmentPaddingX = 5.0;
static const CGFloat kRowMinHeight = 22.0;
static const CGFloat kRowMaxHeight = 420.0;
static const CGFloat kValueWrapWidth = 200.0;

/// 值区里的单个可复制分段。
@interface BrowserDOMSegmentChip : NSView
@property (nonatomic, strong) DomValueSegment *segment;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *ownerRawValue;
@property (nonatomic, copy, nullable) void (^onCopy)(NSString *description);
@property (nonatomic, strong, nullable) NSAttributedString *attributed;
@property (nonatomic, assign) BOOL highlighted;
@end

@implementation BrowserDOMSegmentChip

- (void)setHighlighted:(BOOL)highlighted {
    _highlighted = highlighted;
    self.needsDisplay = YES;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _highlighted = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 3.0;
        // NSTrackingArea 必须带一个「活跃状态」选项（ActiveAlways / ActiveInActiveApp），
        // 否则抛 NSInvalidArgumentException；InVisibleRect 只是修饰位，单独用同样会抛。
        // 见 Tests/tracking-area-probe.m 的实测结果。
        NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                              options:NSTrackingMouseEnteredAndExited |
                                                                      NSTrackingInVisibleRect |
                                                                      NSTrackingActiveInActiveApp
                                                                owner:self
                                                             userInfo:nil];
        [self addTrackingArea:area];
    }
    return self;
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.highlighted = YES;
    NSCursor *cursor = (self.segment.kind == DomSegmentKindBracketKey)
        ? [NSCursor pointingHandCursor]
        : [NSCursor crosshairCursor];
    [cursor set];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.highlighted = NO;
    [[NSCursor arrowCursor] set];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    [self copySegment];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSString *segmentText = self.segment.text ?: @"";

    NSMenuItem *copyItem = [menu addItemWithTitle:[NSString stringWithFormat:@"复制「%@」", segmentText]
                                           action:@selector(copySegment)
                                    keyEquivalent:@""];
    copyItem.target = self;
    NSMenuItem *copyPathItem = [menu addItemWithTitle:@"复制完整路径"
                                               action:@selector(copyFullPath)
                                        keyEquivalent:@""];
    copyPathItem.target = self;
    NSMenuItem *copyValueItem = [menu addItemWithTitle:[NSString stringWithFormat:@"复制 %@ 的完整值", self.ownerName]
                                                action:@selector(copyOwnerValue)
                                         keyEquivalent:@""];
    copyValueItem.target = self;
    copyValueItem.enabled = self.ownerRawValue.length > 0;

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)copySegment {
    [self pasteboardWrite:self.segment.text ?: @"" description:self.segment.text ?: @""];
}

- (void)copyFullPath {
    [self pasteboardWrite:self.segment.fullPath ?: @"" description:self.segment.fullPath ?: @""];
}

- (void)copyOwnerValue {
    [self pasteboardWrite:self.ownerRawValue ?: @"" description:self.ownerName];
}

- (void)pasteboardWrite:(NSString *)text description:(NSString *)description {
    if (text.length == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    if (self.onCopy) {
        self.onCopy(description);
    }
}

- (NSString *)description {
    return self.attributed.string ?: @"";
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect r = NSInsetRect(self.bounds, 0, 1);
    NSColor *bg = self.highlighted ? [NSColor colorWithCalibratedRed:0.18 green:0.48 blue:1.0 alpha:0.28]
                                   : [NSColor colorWithCalibratedWhite:1 alpha:0.06];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.12] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
    border.lineWidth = 1.0;
    [border stroke];
    [bg setFill];
    [border fill];
    if (self.attributed) {
        [self.attributed drawInRect:NSInsetRect(self.bounds, kSegmentPaddingX, 0)];
    }
}

@end

#pragma mark - Row View

@interface BrowserDOMInspectorRowView ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *rawValue;
@property (nonatomic, strong) NSMutableArray<BrowserDOMSegmentChip *> *chips;
@end

@implementation BrowserDOMInspectorRowView

- (instancetype)initWithName:(NSString *)name kind:(NSString *)kind value:(NSString *)value {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _name = [name copy] ?: @"";
        _kind = [kind copy] ?: @"attribute";
        _rawValue = [value copy] ?: @"";
        _chips = [NSMutableArray array];
        self.wantsLayer = YES;
        [self buildChips];
    }
    return self;
}

- (void)buildChips {
    NSArray<DomValueSegment *> *segments =
        [BrowserDOMValueSegmenter segmentsForValue:self.rawValue rootPath:self.name];
    for (DomValueSegment *segment in segments) {
        BrowserDOMSegmentChip *chip = [[BrowserDOMSegmentChip alloc] initWithFrame:NSZeroRect];
        chip.segment = segment;
        chip.ownerName = self.name;
        chip.ownerRawValue = self.rawValue;
        __weak typeof(self) weakSelf = self;
        chip.onCopy = ^(NSString *description) {
            if (weakSelf.onCopy) weakSelf.onCopy(description);
        };
        chip.attributed = [self attributedForSegment:segment];
        [self.chips addObject:chip];
        [self addSubview:chip];
    }
}

- (NSAttributedString *)attributedForSegment:(DomValueSegment *)segment {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFontAttributeName] = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    switch (segment.kind) {
        case DomSegmentKindIdentifier:
            attrs[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedRed:0.42 green:0.68 blue:1.0 alpha:1.0];
            break;
        case DomSegmentKindBracketKey:
            attrs[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedRed:0.72 green:0.60 blue:1.0 alpha:1.0];
            break;
        case DomSegmentKindJSONLeaf:
            attrs[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedRed:0.42 green:0.82 blue:0.55 alpha:1.0];
            break;
        case DomSegmentKindLiteral:
            attrs[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
            break;
    }
    return [[NSAttributedString alloc] initWithString:segment.text ?: @"" attributes:attrs];
}

- (NSDictionary *)nameAttributes {
    return @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.62 alpha:1.0],
    };
}

- (NSSize)intrinsicContentSize {
    CGFloat valueWidth = 0;
    NSMutableArray<NSNumber *> *lineWidths = [NSMutableArray array];

    for (BrowserDOMSegmentChip *chip in self.chips) {
        CGFloat w = chip.attributed ? chip.attributed.size.width + kSegmentPaddingX * 2 : 0;
        CGFloat current = lineWidths.count > 0 ? [lineWidths.lastObject doubleValue] : 0;
        if (lineWidths.count == 0) {
            [lineWidths addObject:@(w)];
        } else if (current + kSegmentSpacing + w > kValueWrapWidth) {
            [lineWidths addObject:@(w)];
        } else {
            [lineWidths addObject:@(current + kSegmentSpacing + w)];
        }
    }
    for (NSNumber *w in lineWidths) {
        valueWidth = MAX(valueWidth, w.doubleValue);
    }
    NSUInteger lineCount = MAX(lineWidths.count, (NSUInteger)1);
    CGFloat height = kRowPadding * 2 + lineCount * kSegmentHeight + (lineCount - 1) * kSegmentSpacing;
    return NSMakeSize(kNameWidth + 8 + valueWidth + 8,
                      MIN(MAX(height, kRowMinHeight), kRowMaxHeight));
}

- (void)layout {
    [super layout];
    CGFloat x = kNameWidth + 8;
    CGFloat y = NSHeight(self.bounds) - kRowPadding - kSegmentHeight;
    CGFloat maxX = NSWidth(self.bounds) - kSegmentPaddingX;

    for (BrowserDOMSegmentChip *chip in self.chips) {
        CGFloat w = chip.attributed ? chip.attributed.size.width + kSegmentPaddingX * 2 : 0;
        if (x + w > maxX && x > kNameWidth + 8) {
            x = kNameWidth + 8;
            y -= kSegmentHeight + kSegmentSpacing;
        }
        chip.frame = NSMakeRect(x, y, w, kSegmentHeight);
        x += w + kSegmentSpacing;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    CGFloat height = MAX(newSize.height, self.intrinsicContentSize.height);
    [super setFrameSize:NSMakeSize(newSize.width, height)];
    [self setNeedsLayout:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect r = NSInsetRect(self.bounds, 2, 1);
    [[NSColor colorWithCalibratedWhite:1 alpha:0.07] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];

    [self.name drawInRect:NSMakeRect(kRowPadding + 4,
                                     NSHeight(self.bounds) - kRowPadding - 14,
                                     kNameWidth, 14)
           withAttributes:[self nameAttributes]];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *copyName = [menu addItemWithTitle:[NSString stringWithFormat:@"复制属性名「%@」", self.name]
                                           action:@selector(copyName)
                                    keyEquivalent:@""];
    copyName.target = self;
    copyName.enabled = self.name.length > 0;

    NSMenuItem *copyValue = [menu addItemWithTitle:[NSString stringWithFormat:@"复制 %@ 的完整值", self.name]
                                            action:@selector(copyValue)
                                     keyEquivalent:@""];
    copyValue.target = self;
    copyValue.enabled = self.rawValue.length > 0;

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *copyNameItem = [menu addItemWithTitle:@"复制属性名"
                                                action:@selector(copyName)
                                         keyEquivalent:@""];
    copyNameItem.target = self;

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)copyName {
    [self writeToPasteboard:self.name description:self.name];
}

- (void)copyValue {
    [self writeToPasteboard:self.rawValue description:self.name];
}

- (void)writeToPasteboard:(NSString *)text description:(NSString *)description {
    if (text.length == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    if (self.onCopy) self.onCopy(description);
}

@end
