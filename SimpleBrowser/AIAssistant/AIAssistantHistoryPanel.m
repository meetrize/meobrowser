#import "AIAssistantHistoryPanel.h"
#import "AIAssistantSession.h"
#import "AIAssistantSessionStore.h"
#import "BrowserAIAssistantPrompts.h"
#import "SBTextField.h"

@interface AIAssistantHistoryPanel () <NSTextFieldDelegate>
@property (nonatomic, strong) SBTextField *searchField;
@property (nonatomic, strong) NSScrollView *scroll;
@property (nonatomic, strong) NSStackView *listStack;
@property (nonatomic, strong) NSTextField *emptyLabel;
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

    [NSLayoutConstraint activateConstraints:@[
        [self.searchField.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [self.searchField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [self.searchField.heightAnchor constraintEqualToConstant:24],

        [self.scroll.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:8],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.listStack.topAnchor constraintEqualToAnchor:doc.topAnchor constant:0],
        [self.listStack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:8],
        [self.listStack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-8],
        [self.listStack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-8],
        [self.listStack.widthAnchor constraintEqualToAnchor:self.scroll.widthAnchor constant:-16],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.scroll.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.scroll.centerYAnchor],
    ]];
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
        [wrap.widthAnchor constraintEqualToConstant:300],
    ]];
    return wrap;
}

- (NSView *)rowForSession:(AIAssistantSession *)session {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.wantsLayer = YES;
    row.layer.cornerRadius = 6;

    NSButton *hit = [NSButton buttonWithTitle:@"" target:self action:@selector(rowClicked:)];
    hit.translatesAutoresizingMaskIntoConstraints = NO;
    hit.bezelStyle = NSBezelStyleInline;
    hit.bordered = NO;
    hit.identifier = session.sessionId;
    hit.toolTip = session.previewText;

    NSTextField *title = [NSTextField labelWithString:session.title.length ? session.title : @"新对话"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    title.lineBreakMode = NSLineBreakByTruncatingTail;

    NSString *sub = [NSString stringWithFormat:@"%@ · %@",
                     [self providerName:session.providerId], session.previewText ?: @""];
    NSTextField *preview = [NSTextField labelWithString:sub];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.font = [NSFont systemFontOfSize:10];
    preview.textColor = NSColor.secondaryLabelColor;
    preview.lineBreakMode = NSLineBreakByTruncatingTail;

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

    [row addSubview:hit];
    [row addSubview:title];
    [row addSubview:preview];
    [row addSubview:pinBtn];
    [row addSubview:delBtn];

    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToConstant:300],
        [row.heightAnchor constraintEqualToConstant:44],

        [hit.topAnchor constraintEqualToAnchor:row.topAnchor],
        [hit.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [hit.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [hit.trailingAnchor constraintEqualToAnchor:pinBtn.leadingAnchor constant:-4],

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
    for (NSDictionary *g in groups) {
        NSArray *sessions = g[@"sessions"];
        total += sessions.count;
        [self.listStack addArrangedSubview:[self sectionHeader:g[@"title"] ?: @""]];
        for (AIAssistantSession *s in sessions) {
            [self.listStack addArrangedSubview:[self rowForSession:s]];
        }
    }
    self.emptyLabel.hidden = (total > 0);
    self.emptyLabel.stringValue = q.length ? @"无匹配会话" : @"暂无会话";
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

- (void)rowClicked:(NSButton *)sender {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sender.identifier];
    if (s && self.onSelectSession) self.onSelectSession(s);
}

- (void)pinClicked:(NSButton *)sender {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sender.identifier];
    if (s && self.onTogglePin) self.onTogglePin(s);
}

- (void)deleteClicked:(NSButton *)sender {
    AIAssistantSession *s = [AIAssistantSessionStore.sharedStore sessionForId:sender.identifier];
    if (s && self.onDeleteSession) self.onDeleteSession(s);
}

@end
