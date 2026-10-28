#import "AIAssistantHistoryPanel.h"
#import "AIAssistantSession.h"
#import "AIAssistantSessionStore.h"
#import "BrowserAIAssistantPrompts.h"
#import "SBTextField.h"

static const CGFloat kPanelWidth = 320.0;
static const CGFloat kSearchTop = 10.0;
static const CGFloat kSearchHeight = 24.0;
static const CGFloat kSearchToList = 8.0;
static const CGFloat kHeaderHeight = 24.0;
static const CGFloat kRowHeight = 44.0;
static const CGFloat kStackSpacing = 2.0;
static const CGFloat kListBottomPad = 8.0;
static const CGFloat kEmptyListMin = 56.0;
static const CGFloat kMaxPopoverHeight = 520.0;

@interface AIAssistantHistoryRowView : NSView
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, weak) AIAssistantHistoryPanel *panel;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, assign) BOOL pressed;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@end

@interface AIAssistantHistoryPanel () <NSTextFieldDelegate>
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSScrollView *scroll;
@property (nonatomic, strong) NSStackView *listStack;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSLayoutConstraint *scrollHeightConstraint;
@property (nonatomic, assign) CGFloat lastListContentHeight;
- (void)selectSessionId:(NSString *)sessionId;
- (void)togglePinSessionId:(NSString *)sessionId;
- (void)deleteSessionId:(NSString *)sessionId;
@end

@implementation AIAssistantHistoryRowView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:(NSTrackingMouseEnteredAndExited |
                                                              NSTrackingActiveInKeyWindow |
                                                              NSTrackingInVisibleRect)
                                                       owner:self
                                                    userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (void)applyHighlight {
    if (!self.wantsLayer) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
    }
    NSColor *bg = NSColor.clearColor;
    if (self.pressed) {
        if (@available(macOS 10.14, *)) {
            bg = [NSColor.controlAccentColor colorWithAlphaComponent:0.28];
        } else {
            bg = [NSColor.selectedControlColor colorWithAlphaComponent:0.55];
        }
    } else if (self.hovered) {
        if (@available(macOS 10.14, *)) {
            bg = [NSColor.controlAccentColor colorWithAlphaComponent:0.14];
        } else {
            bg = [[NSColor blackColor] colorWithAlphaComponent:0.08];
        }
    }
    self.layer.backgroundColor = bg.CGColor;
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovered = YES;
    [self applyHighlight];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovered = NO;
    self.pressed = NO;
    [self applyHighlight];
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    self.pressed = YES;
    [self applyHighlight];
}

- (void)mouseUp:(NSEvent *)event {
    BOOL wasPressed = self.pressed;
    self.pressed = NO;
    [self applyHighlight];
    if (!wasPressed) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(p, self.bounds)) return;
    [self.panel selectSessionId:self.sessionId];
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit) return nil;
    // 仅 pin/delete 按钮自己接收；其余点落到本行以便选中与悬停
    if ([hit isKindOfClass:[NSButton class]]) {
        return hit;
    }
    return self;
}

@end

@implementation AIAssistantHistoryPanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        [self build];
        [self reload];
    }
    return self;
}

- (NSImage *)symbol:(NSString *)name size:(CGFloat)size {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:size
                                                            weight:NSFontWeightRegular
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return [img imageWithSymbolConfiguration:cfg] ?: img;
    }
    return nil;
}

- (NSButton *)iconBtn:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *img = [self symbol:symbol size:12];
    NSButton *b = img ? [NSButton buttonWithImage:img target:self action:action]
                      : [NSButton buttonWithTitle:@"·" target:self action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.bezelStyle = NSBezelStyleInline;
    b.bordered = NO;
    b.imagePosition = NSImageOnly;
    b.toolTip = tip;
    if (@available(macOS 10.14, *)) {
        b.contentTintColor = NSColor.secondaryLabelColor;
    }
    [b.widthAnchor constraintEqualToConstant:22].active = YES;
    [b.heightAnchor constraintEqualToConstant:22].active = YES;
    return b;
}

- (void)build {
    self.searchField = [SBTextField standardField];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholderString = @"搜索会话";
    self.searchField.delegate = self;
    self.searchField.target = self;
    self.searchField.action = @selector(searchChanged:);

    self.scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.hasVerticalScroller = YES;
    self.scroll.borderType = NSNoBorder;
    self.scroll.drawsBackground = NO;

    NSView *doc = [[NSView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    self.listStack = [NSStackView stackViewWithViews:@[]];
    self.listStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.listStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.listStack.alignment = NSLayoutAttributeLeading;
    self.listStack.spacing = 2;
    [doc addSubview:self.listStack];
    self.scroll.documentView = doc;

    self.emptyLabel = [NSTextField labelWithString:@"暂无会话"];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.font = [NSFont systemFontOfSize:12];
    self.emptyLabel.textColor = NSColor.tertiaryLabelColor;
    self.emptyLabel.hidden = YES;

    [self addSubview:self.searchField];
    [self addSubview:self.scroll];
    [self addSubview:self.emptyLabel];

    self.scrollHeightConstraint = [self.scroll.heightAnchor constraintEqualToConstant:kEmptyListMin];
    self.scrollHeightConstraint.priority = NSLayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.searchField.topAnchor constraintEqualToAnchor:self.topAnchor constant:kSearchTop],
        [self.searchField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [self.searchField.heightAnchor constraintEqualToConstant:kSearchHeight],

        [self.scroll.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:kSearchToList],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        self.scrollHeightConstraint,

        [self.listStack.topAnchor constraintEqualToAnchor:doc.topAnchor constant:0],
        [self.listStack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:8],
        [self.listStack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-8],
        [self.listStack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-kListBottomPad],
        [self.listStack.widthAnchor constraintEqualToConstant:kPanelWidth - 16],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.scroll.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.scroll.centerYAnchor],
    ]];
}

- (CGFloat)headerChromeHeight {
    return kSearchTop + kSearchHeight + kSearchToList;
}

- (CGFloat)maxListHeight {
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    CGFloat screenCap = screen.visibleFrame.size.height * 0.65;
    if (screenCap < 200) screenCap = 200;
    CGFloat maxTotal = MIN(kMaxPopoverHeight, screenCap);
    return MAX(kEmptyListMin, maxTotal - [self headerChromeHeight]);
}

- (NSSize)preferredPopoverSize {
    CGFloat listH = self.lastListContentHeight > 0 ? self.lastListContentHeight : kEmptyListMin;
    CGFloat cappedList = MIN(listH, [self maxListHeight]);
    return NSMakeSize(kPanelWidth, [self headerChromeHeight] + cappedList);
}

- (void)applyScrollHeightForContent:(CGFloat)contentHeight {
    self.lastListContentHeight = contentHeight;
    CGFloat maxList = [self maxListHeight];
    CGFloat visible = MIN(contentHeight, maxList);
    self.scrollHeightConstraint.constant = visible;
    BOOL needsScroll = contentHeight > maxList + 0.5;
    self.scroll.hasVerticalScroller = needsScroll;
    self.scroll.verticalScrollElasticity = needsScroll ? NSScrollElasticityAutomatic : NSScrollElasticityNone;
    if (self.onPreferredSizeChanged) {
        self.onPreferredSizeChanged([self preferredPopoverSize]);
    }
}

- (NSString *)providerName:(NSString *)pid {
    for (NSDictionary *p in [BrowserAIAssistantPrompts providerCatalog]) {
        if ([p[@"id"] isEqualToString:pid]) return p[@"title"] ?: pid;
    }
    return pid ?: @"";
}

- (NSView *)sectionHeader:(NSString *)title {
    NSTextField *lab = [NSTextField labelWithString:title];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    lab.textColor = NSColor.secondaryLabelColor;
    NSView *wrap = [[NSView alloc] initWithFrame:NSZeroRect];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:lab];
    [NSLayoutConstraint activateConstraints:@[
        [lab.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:4],
        [lab.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [lab.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8],
        [lab.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-2],
        [wrap.widthAnchor constraintEqualToConstant:kPanelWidth - 20],
        [wrap.heightAnchor constraintEqualToConstant:kHeaderHeight],
    ]];
    return wrap;
}

- (NSView *)rowForSession:(AIAssistantSession *)session {
    AIAssistantHistoryRowView *row = [[AIAssistantHistoryRowView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.wantsLayer = YES;
    row.layer.cornerRadius = 6;
    row.sessionId = session.sessionId;
    row.panel = self;
    row.toolTip = session.previewText;
    [row applyHighlight];

    NSTextField *title = [NSTextField labelWithString:session.title.length ? session.title : @"新对话"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.selectable = NO;
    title.editable = NO;

    NSString *sub = [NSString stringWithFormat:@"%@ · %@",
                     [self providerName:session.providerId], session.previewText ?: @""];
    NSTextField *preview = [NSTextField labelWithString:sub];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.font = [NSFont systemFontOfSize:10];
    preview.textColor = NSColor.secondaryLabelColor;
    preview.lineBreakMode = NSLineBreakByTruncatingTail;
    preview.selectable = NO;
    preview.editable = NO;

    NSString *pinSymbol = session.pinned ? @"pin.fill" : @"pin";
    NSButton *pinBtn = [self iconBtn:pinSymbol tip:(session.pinned ? @"取消固定" : @"固定") action:@selector(pinClicked:)];
    pinBtn.identifier = session.sessionId;
    if (session.pinned) {
        if (@available(macOS 10.14, *)) {
            pinBtn.contentTintColor = NSColor.controlAccentColor;
        }
    }

    NSButton *delBtn = [self iconBtn:@"trash" tip:@"删除" action:@selector(deleteClicked:)];
    delBtn.identifier = session.sessionId;

    [row addSubview:title];
    [row addSubview:preview];
    [row addSubview:pinBtn];
    [row addSubview:delBtn];

    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToConstant:kPanelWidth - 20],
        [row.heightAnchor constraintEqualToConstant:kRowHeight],

        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:5],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:6],
        [title.trailingAnchor constraintEqualToAnchor:pinBtn.leadingAnchor constant:-4],

        [preview.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
        [preview.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [delBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [delBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-2],
        [pinBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [pinBtn.trailingAnchor constraintEqualToAnchor:delBtn.leadingAnchor constant:-2],
    ]];
    return row;
}

- (void)reload {
    for (NSView *v in self.listStack.arrangedSubviews.copy) {
        [self.listStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSString *q = self.searchField.stringValue ?: @"";
    NSArray<NSDictionary *> *groups = [AIAssistantSessionStore.sharedStore groupedSessionsMatchingQuery:q];
    NSUInteger total = 0;
    NSUInteger sectionCount = 0;
    for (NSDictionary *g in groups) {
        NSArray *sessions = g[@"sessions"];
        if (sessions.count == 0) continue;
        total += sessions.count;
        sectionCount += 1;
        [self.listStack addArrangedSubview:[self sectionHeader:g[@"title"] ?: @""]];
        for (AIAssistantSession *s in sessions) {
            [self.listStack addArrangedSubview:[self rowForSession:s]];
        }
    }
    self.emptyLabel.hidden = (total > 0);
    self.emptyLabel.stringValue = q.length ? @"无匹配会话" : @"暂无会话";

    CGFloat contentH = kEmptyListMin;
    if (total > 0) {
        // 每组一个 header + 若干 row；stack spacing 在相邻项之间
        NSUInteger itemCount = sectionCount + total;
        contentH = sectionCount * kHeaderHeight
            + total * kRowHeight
            + (itemCount > 0 ? (itemCount - 1) * kStackSpacing : 0)
            + kListBottomPad;
    }
    [self applyScrollHeightForContent:contentH];
    [self.listStack layoutSubtreeIfNeeded];
}

- (void)focusSearch {
    [self.window makeFirstResponder:self.searchField];
}

- (void)searchChanged:(id)sender {
    (void)sender;
    [self reload];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.searchField) {
        [self reload];
    }
}

- (void)selectSessionId:(NSString *)sessionId {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sessionId];
    if (s && self.onSelectSession) {
        self.onSelectSession(s);
    }
}

- (void)togglePinSessionId:(NSString *)sessionId {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sessionId];
    if (s && self.onTogglePin) {
        self.onTogglePin(s);
    }
}

- (void)deleteSessionId:(NSString *)sessionId {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sessionId];
    if (s && self.onDeleteSession) {
        self.onDeleteSession(s);
    }
}

- (void)pinClicked:(NSButton *)sender {
    [self togglePinSessionId:sender.identifier];
}

- (void)deleteClicked:(NSButton *)sender {
    [self deleteSessionId:sender.identifier];
}

@end
