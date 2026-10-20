#import "BrowserDOMInspectorPanel.h"
#import "BrowserDOMInspectorRowView.h"

static const CGFloat kPanelPadding = 10.0;
static const CGFloat kPanelHeaderHeight = 62.0;
static const CGFloat kGroupHeaderHeight = 22.0;
static const CGFloat kGroupSpacing = 6.0;
static const CGFloat kPanelMinWidth = 260.0;
static const CGFloat kPanelDefaultWidth = 320.0;

#pragma mark - Group Header

@interface BrowserDOMInspectorGroupHeader : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *countText;
@property (nonatomic, copy, nullable) void (^onToggle)(void);
@property (nonatomic, assign) BOOL expanded;
@end

@implementation BrowserDOMInspectorGroupHeader

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (self.onToggle) self.onToggle();
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect r = NSInsetRect(self.bounds, kPanelPadding, 3);
    [[NSColor colorWithCalibratedWhite:1 alpha:0.08] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];

    NSString *marker = self.expanded ? @"▾" : @"▸";
    [[marker stringByAppendingFormat:@" %@", self.titleText] drawInRect:r
        withAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
                          NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.95 alpha:1.0] }];

    if (self.countText.length > 0) {
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.55 alpha:1.0],
        };
        NSSize size = [self.countText sizeWithAttributes:attrs];
        [self.countText drawInRect:NSMakeRect(NSMaxX(r) - size.width, NSMinY(r), size.width, NSHeight(r))
                    withAttributes:attrs];
    }
}

@end

#pragma mark - Panel

@interface BrowserDOMInspectorPanel ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *stackContainer;
@property (nonatomic, copy) NSArray<NSString *> *allCopyPairs;
@property (nonatomic, strong) NSDictionary *currentSnapshot;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSButton *selectorButton;
@property (nonatomic, strong) NSButton *allAttributesButton;
@end

@implementation BrowserDOMInspectorPanel

- (instancetype)initWithFrame:(NSRect)frame {
    (void)frame;
    self = [super initWithFrame:NSMakeRect(0, 0, kPanelDefaultWidth, 400)];
    if (self) {
        _visible = NO;
        _allCopyPairs = @[];
        _currentSnapshot = @{};
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.11 alpha:0.98].CGColor;
        self.layer.borderColor = [NSColor colorWithCalibratedWhite:1 alpha:0.12].CGColor;
        self.layer.borderWidth = 1.0;
        [self buildScrollView];
        [self buildHeader];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)buildScrollView {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    self.stackContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.stackContainer;
    [self addSubview:scroll];
    self.scrollView = scroll;
}

- (void)buildHeader {
    self.closeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(handleClose:)];
    self.selectorButton = [NSButton buttonWithTitle:@"⌗ CSS 选择器" target:self action:@selector(handleCopySelector:)];
    self.allAttributesButton = [NSButton buttonWithTitle:@"⧉ 全部属性" target:self action:@selector(handleCopyAll:)];
    for (NSButton *button in @[self.closeButton, self.selectorButton, self.allAttributesButton]) {
        button.bezelStyle = NSBezelStyleInline;
        button.controlSize = NSControlSizeSmall;
        button.font = [NSFont systemFontOfSize:11];
    }
    [self addSubview:self.closeButton];
    [self addSubview:self.selectorButton];
    [self addSubview:self.allAttributesButton];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    CGFloat top = NSHeight(self.bounds) - kPanelPadding;

    self.closeButton.frame = NSMakeRect(width - kPanelPadding - 24, top - 22, 24, 20);
    self.selectorButton.frame = NSMakeRect(kPanelPadding, top - 24, 110, 20);
    self.allAttributesButton.frame = NSMakeRect(kPanelPadding + 116, top - 24, 92, 20);

    self.scrollView.frame = NSMakeRect(0, 0, width, NSHeight(self.bounds) - kPanelHeaderHeight);
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(kPanelDefaultWidth, NSHeight(self.bounds));
}

#pragma mark - Snapshot

- (void)showSnapshot:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:[NSDictionary class]]) return;
    self.currentSnapshot = snapshot;
    self.visible = YES;
    [self rebuildWithSnapshot:snapshot];
    [self setNeedsLayout:YES];
}

- (void)hidePanel {
    self.visible = NO;
}

- (void)rebuildWithSnapshot:(NSDictionary *)snapshot {
    for (NSView *sub in [self.stackContainer.subviews copy]) {
        [sub removeFromSuperview];
    }
    NSMutableArray<NSString *> *copyPairs = [NSMutableArray array];
    NSMutableArray<NSView *> *rows = [NSMutableArray array];

    [self appendGroupRowsWithTitle:@"身份" rows:[self identityRowsFromSnapshot:snapshot]
                           copyPairs:copyPairs expanded:YES into:rows];
    [self appendGroupRowsWithTitle:@"自定义属性"
                             rows:[self rowsFromArray:snapshot[@"attributes"] kinds:@[@"data", @"aria"]]
                         copyPairs:copyPairs expanded:YES into:rows];
    [self appendGroupRowsWithTitle:@"标准属性"
                             rows:[self rowsFromArray:snapshot[@"attributes"] kinds:@[@"attribute", @"identity", @"handler"]]
                         copyPairs:copyPairs expanded:NO into:rows];
    [self appendGroupRowsWithTitle:@"属性对象"
                             rows:[self rowsFromArray:snapshot[@"properties"] kinds:@[@"property"]]
                         copyPairs:copyPairs expanded:NO into:rows];
    [self appendGroupRowsWithTitle:@"几何" rows:[self geometryRowsFromSnapshot:snapshot]
                         copyPairs:copyPairs expanded:NO into:rows];
    [self appendGroupRowsWithTitle:@"计算样式" rows:[self styleRowsFromSnapshot:snapshot]
                         copyPairs:copyPairs expanded:NO into:rows];
    [self appendGroupRowsWithTitle:@"文本" rows:[self textRowsFromSnapshot:snapshot]
                         copyPairs:copyPairs expanded:NO into:rows];

    self.allCopyPairs = [copyPairs copy];
    [self layoutRows:rows];
}

#pragma mark - Groups

- (void)appendGroupRowsWithTitle:(NSString *)title
                           rows:(NSArray<BrowserDOMInspectorRowView *> *)rows
                      copyPairs:(NSMutableArray<NSString *> *)copyPairs
                      expanded:(BOOL)expanded
                           into:(NSMutableArray<NSView *> *)container {
    if (rows.count == 0) return;
    NSString *countText = [NSString stringWithFormat:@"%lu 项", (unsigned long)rows.count];

    BrowserDOMInspectorGroupHeader *header =
        [[BrowserDOMInspectorGroupHeader alloc] initWithFrame:NSZeroRect];
    __weak typeof(self) weakSelf = self;
    __weak BrowserDOMInspectorGroupHeader *weakHeader = header;
    header.titleText = title;
    header.countText = countText;
    header.expanded = expanded;

    NSMutableArray<NSView *> *group = [NSMutableArray arrayWithObject:header];
    if (expanded) {
        [group addObjectsFromArray:rows];
    }
    for (BrowserDOMInspectorRowView *row in rows) {
        [copyPairs addObject:[NSString stringWithFormat:@"%@=\"%@\"", row.name, row.rawValue]];
    }
    header.onToggle = ^{
        BrowserDOMInspectorGroupHeader *strongHeader = weakHeader;
        if (!strongHeader) return;
        strongHeader.expanded = !strongHeader.expanded;
        [weakSelf rebuildWithSnapshot:weakSelf.currentSnapshot];
    };
    [container addObjectsFromArray:group];
}

- (void)layoutRows:(NSArray<NSView *> *)rows {
    CGFloat width = MAX(NSWidth(self.bounds), kPanelMinWidth);
    CGFloat y = kPanelPadding;
    for (NSView *row in rows) {
        CGFloat height = kGroupHeaderHeight;
        if ([row isKindOfClass:[BrowserDOMInspectorRowView class]]) {
            height = row.intrinsicContentSize.height + kGroupSpacing;
        } else {
            height += kGroupSpacing;
        }
        row.frame = NSMakeRect(0, y, width, height);
        y += height;
    }
    self.stackContainer.frame = NSMakeRect(0, 0, width, y + kPanelPadding);
}

#pragma mark - Row Builders

- (NSArray<BrowserDOMInspectorRowView *> *)identityRowsFromSnapshot:(NSDictionary *)snapshot {
    NSMutableArray<BrowserDOMInspectorRowView *> *rows = [NSMutableArray array];
    NSString *tag = [self stringValue:snapshot[@"tagName"]];
    [rows addObject:[self rowWithName:@"tagName" value:tag.length > 0 ? tag : @""]];
    NSString *elementID = [self stringValue:snapshot[@"id"]];
    if (elementID.length > 0) [rows addObject:[self rowWithName:@"id" value:elementID]];
    NSString *cls = [self stringValue:snapshot[@"className"]];
    if (cls.length > 0) [rows addObject:[self rowWithName:@"className" value:cls]];
    NSString *selector = [self stringValue:snapshot[@"selector"]];
    if (selector.length > 0) [rows addObject:[self rowWithName:@"selector" value:selector]];
    NSString *xpath = [self stringValue:snapshot[@"xpath"]];
    if (xpath.length > 0) [rows addObject:[self rowWithName:@"xpath" value:xpath]];
    return rows;
}

- (NSArray<BrowserDOMInspectorRowView *> *)rowsFromArray:(id)array kinds:(NSArray<NSString *> *)kinds {
    if (![array isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<BrowserDOMInspectorRowView *> *rows = [NSMutableArray array];
    for (NSDictionary *item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *kind = [self stringValue:item[@"kind"]];
        if (kind.length > 0 && ![kinds containsObject:kind]) continue;
        [rows addObject:[self rowWithName:[self stringValue:item[@"name"]]
                                     kind:kind
                                     value:[self stringValue:item[@"value"]]]];
    }
    return rows;
}

- (NSArray<BrowserDOMInspectorRowView *> *)geometryRowsFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *geo = [snapshot[@"geometry"] isKindOfClass:[NSDictionary class]] ? snapshot[@"geometry"] : nil;
    if (geo.count == 0) return @[];
    NSMutableArray<BrowserDOMInspectorRowView *> *rows = [NSMutableArray array];
    NSArray<NSString *> *keys = @[@"x", @"y", @"width", @"height", @"scrollWidth",
                                  @"scrollHeight", @"scrollTop", @"scrollLeft"];
    for (NSString *key in keys) {
        id value = geo[key];
        if (!value) continue;
        [rows addObject:[self rowWithName:key value:[self stringValue:value]]];
    }
    [rows addObject:[self rowWithName:@"inViewport"
                                 value:[geo[@"inViewport"] boolValue] ? @"是" : @"否"]];
    return rows;
}

- (NSArray<BrowserDOMInspectorRowView *> *)styleRowsFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *style = [snapshot[@"styleSummary"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"styleSummary"] : nil;
    NSMutableArray<BrowserDOMInspectorRowView *> *rows = [NSMutableArray array];
    for (NSString *key in [style.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [rows addObject:[self rowWithName:key value:[self stringValue:style[key]]]];
    }
    return rows;
}

- (NSArray<BrowserDOMInspectorRowView *> *)textRowsFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *text = [snapshot[@"text"] isKindOfClass:[NSDictionary class]] ? snapshot[@"text"] : nil;
    if (text.count == 0) return @[];
    NSMutableArray<BrowserDOMInspectorRowView *> *rows = [NSMutableArray array];
    [rows addObject:[self rowWithName:@"textContent" value:[self stringValue:text[@"own"]]]];
    if ([text[@"length"] integerValue] > 0) {
        [rows addObject:[self rowWithName:@"textLength" value:[self stringValue:text[@"length"]]]];
    }
    NSDictionary *a11y = [snapshot[@"a11y"] isKindOfClass:[NSDictionary class]] ? snapshot[@"a11y"] : nil;
    for (NSString *key in @[@"role", @"label", @"alt"]) {
        NSString *value = [self stringValue:a11y[key]];
        if (value.length > 0) [rows addObject:[self rowWithName:key value:value]];
    }
    if ([a11y[@"hidden"] boolValue]) {
        [rows addObject:[self rowWithName:@"hidden" value:@"是"]];
    }
    return rows;
}

- (BrowserDOMInspectorRowView *)rowWithName:(NSString *)name value:(NSString *)value {
    return [self rowWithName:name kind:@"attribute" value:value];
}

- (BrowserDOMInspectorRowView *)rowWithName:(NSString *)name kind:(NSString *)kind value:(NSString *)value {
    BrowserDOMInspectorRowView *row = [[BrowserDOMInspectorRowView alloc] initWithName:name kind:kind value:value];
    __weak typeof(self) weakSelf = self;
    row.onCopy = ^(NSString *description) {
        if (weakSelf.onCopy) weakSelf.onCopy(description);
    };
    return row;
}

- (NSString *)stringValue:(id)value {
    if (!value || value == [NSNull null]) return @"";
    return [value isKindOfClass:[NSString class]] ? value : [value description];
}

#pragma mark - Actions

- (void)handleClose:(id)sender {
    (void)sender;
    if (self.onRequestClose) self.onRequestClose();
}

- (void)handleCopySelector:(id)sender {
    (void)sender;
    NSString *selector = [self stringValue:self.currentSnapshot[@"selector"]];
    if (selector.length == 0) return;
    [self writeToPasteboard:selector description:@"CSS 选择器"];
}

- (void)handleCopyAll:(id)sender {
    (void)sender;
    if (self.allCopyPairs.count == 0) return;
    NSString *text = [self.allCopyPairs componentsJoinedByString:@"\n"];
    [self writeToPasteboard:text description:@"全部属性"];
}

- (void)writeToPasteboard:(NSString *)text description:(NSString *)description {
    if (text.length == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    if (self.onCopy) self.onCopy(description);
}

@end
