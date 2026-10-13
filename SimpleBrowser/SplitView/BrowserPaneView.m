#import "BrowserPaneView.h"

@interface BrowserPaneView ()
@property (nonatomic, strong) NSView *chromeBar;
@property (nonatomic, strong) NSView *contentHostInner;
@property (nonatomic, strong) NSTextField *addressFieldInner;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *fwdBtn;
@property (nonatomic, strong) NSButton *goBtn;
@property (nonatomic, strong) NSTrackingArea *chromeTracking;
@property (nonatomic, strong) NSTextField *syncBadge;
@end

@implementation BrowserPaneView

- (instancetype)initWithIndex:(NSInteger)index {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _paneIndex = index;
        _chromeMode = BrowserPaneChromeAutohide;
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor textBackgroundColor] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [[NSColor clearColor] CGColor];

        _chromeBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _chromeBar.translatesAutoresizingMaskIntoConstraints = NO;
        _chromeBar.wantsLayer = YES;
        _chromeBar.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
        _chromeBar.layer.borderWidth = 0;
        [self addSubview:_chromeBar];
        NSView *chromeBottomLine = [[NSView alloc] initWithFrame:NSZeroRect];
        chromeBottomLine.translatesAutoresizingMaskIntoConstraints = NO;
        chromeBottomLine.wantsLayer = YES;
        chromeBottomLine.layer.backgroundColor = [[NSColor separatorColor] CGColor];
        [_chromeBar addSubview:chromeBottomLine];
        [NSLayoutConstraint activateConstraints:@[
            [chromeBottomLine.leadingAnchor constraintEqualToAnchor:_chromeBar.leadingAnchor],
            [chromeBottomLine.trailingAnchor constraintEqualToAnchor:_chromeBar.trailingAnchor],
            [chromeBottomLine.bottomAnchor constraintEqualToAnchor:_chromeBar.bottomAnchor],
            [chromeBottomLine.heightAnchor constraintEqualToConstant:1],
        ]];

        _backBtn = [NSButton buttonWithTitle:@"‹" target:self action:@selector(goBack:)];
        _backBtn.translatesAutoresizingMaskIntoConstraints = NO;
        _backBtn.bezelStyle = NSBezelStyleInline;
        [_chromeBar addSubview:_backBtn];
        _fwdBtn = [NSButton buttonWithTitle:@"›" target:self action:@selector(goForward:)];
        _fwdBtn.translatesAutoresizingMaskIntoConstraints = NO;
        _fwdBtn.bezelStyle = NSBezelStyleInline;
        [_chromeBar addSubview:_fwdBtn];
        _addressFieldInner = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _addressFieldInner.translatesAutoresizingMaskIntoConstraints = NO;
        _addressFieldInner.delegate = self;
        _addressFieldInner.target = self;
        _addressFieldInner.action = @selector(commitAddress:);
        _addressFieldInner.placeholderString = @"输入网址或搜索";
        _addressFieldInner.font = [NSFont systemFontOfSize:12];
        _addressFieldInner.enabled = YES;
        _addressFieldInner.editable = YES;
        _addressFieldInner.selectable = YES;
        _addressFieldInner.refusesFirstResponder = NO;
        [_chromeBar addSubview:_addressFieldInner];
        _goBtn = [NSButton buttonWithTitle:@"前往" target:self action:@selector(commitAddress:)];
        _goBtn.translatesAutoresizingMaskIntoConstraints = NO;
        _goBtn.bezelStyle = NSBezelStyleInline;
        [_chromeBar addSubview:_goBtn];

        _contentHostInner = [[NSView alloc] initWithFrame:NSZeroRect];
        _contentHostInner.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentHostInner];

        [NSLayoutConstraint activateConstraints:@[
            [_chromeBar.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_chromeBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_chromeBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_chromeBar.heightAnchor constraintEqualToConstant:30],
            [_backBtn.leadingAnchor constraintEqualToAnchor:_chromeBar.leadingAnchor constant:4],
            [_backBtn.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_backBtn.widthAnchor constraintEqualToConstant:20],
            [_fwdBtn.leadingAnchor constraintEqualToAnchor:_backBtn.trailingAnchor constant:2],
            [_fwdBtn.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_fwdBtn.widthAnchor constraintEqualToConstant:20],
            [_goBtn.trailingAnchor constraintEqualToAnchor:_chromeBar.trailingAnchor constant:-4],
            [_goBtn.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_goBtn.widthAnchor constraintEqualToConstant:36],
            [_addressFieldInner.leadingAnchor constraintEqualToAnchor:_fwdBtn.trailingAnchor constant:4],
            [_addressFieldInner.trailingAnchor constraintEqualToAnchor:_goBtn.leadingAnchor constant:-4],
            [_addressFieldInner.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_contentHostInner.topAnchor constraintEqualToAnchor:_chromeBar.bottomAnchor],
            [_contentHostInner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_contentHostInner.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_contentHostInner.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        [self applyChromeModeAnimated:NO];
        _syncBadge = [NSTextField labelWithString:@""];
        _syncBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _syncBadge.font = [NSFont boldSystemFontOfSize:11];
        _syncBadge.textColor = [NSColor controlAccentColor];
        _syncBadge.hidden = YES;
        [self addSubview:_syncBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_syncBadge.topAnchor constraintEqualToAnchor:self.topAnchor constant:34],
            [_syncBadge.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        ]];
    }
    return self;
}
- (void)setSyncBadge:(NSString *)badge {
    _syncBadge.stringValue = badge ?: @"";
    _syncBadge.hidden = (badge.length == 0);
}

- (NSView *)contentHost { return _contentHostInner; }
- (NSTextField *)addressField { return _addressFieldInner; }

- (void)setActive:(BOOL)active {
    _active = active;
    self.layer.borderColor = (active ? [NSColor controlAccentColor] : [NSColor clearColor]).CGColor;
}

- (void)setChromeMode:(BrowserPaneChromeMode)mode {
    _chromeMode = mode;
    [self applyChromeModeAnimated:YES];
}

- (void)applyChromeModeAnimated:(BOOL)animated {
    BOOL show = (_chromeMode == BrowserPaneChromeAlways) || (_chromeMode == BrowserPaneChromeAutohide && self.active);
    if (_chromeMode == BrowserPaneChromeHidden) show = NO;
    _chromeBar.hidden = !show;
}

- (void)setActiveAndReveal:(BOOL)active {
    self.active = active;
    [self applyChromeModeAnimated:NO];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_chromeTracking) { [self removeTrackingArea:_chromeTracking]; _chromeTracking = nil; }
    _chromeTracking = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_chromeTracking];
}

- (void)mouseEntered:(NSEvent *)e {
    // 自动隐藏模式:移到栏内即显示地址栏,不抢焦点(点击才聚焦)
    if (_chromeMode == BrowserPaneChromeAutohide) _chromeBar.hidden = NO;
}
- (void)mouseDown:(NSEvent *)e {
    // 子视图(地址栏/按钮/WebView)会先吃掉自己的点击;落到这里说明点在空白处 -> 聚焦本栏
    if (self.becameActiveHandler) self.becameActiveHandler(self.paneIndex);
    else self.active = YES;
    [super mouseDown:e];
}

- (void)mouseExited:(NSEvent *)e {
    if (_chromeMode == BrowserPaneChromeAutohide) _chromeBar.hidden = YES;
}

- (void)attachWebView:(WKWebView *)webView {
    if (_webView == webView) return;
    [_webView removeFromSuperview];
    _webView = webView;
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentHostInner addSubview:webView];
    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:_contentHostInner.topAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:_contentHostInner.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:_contentHostInner.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:_contentHostInner.bottomAnchor],
    ]];
    [self updateAddressFieldWithURL:webView.URL];
}

- (void)setPlaceholderURL:(NSURL *)url {
    if (url) _addressFieldInner.stringValue = url.absoluteString;
    else if (_addressFieldInner.stringValue.length == 0) _addressFieldInner.placeholderString = [NSString stringWithFormat:@"栏 %ld — 输入网址", (long)_paneIndex + 1];
}

- (void)loadURL:(NSURL *)url {
    [self updateAddressFieldWithURL:url];
    if (_webView) [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)updateAddressFieldWithURL:(NSURL *)url {
    if (url) _addressFieldInner.stringValue = url.absoluteString;
}

- (void)goBack:(id)s { if ([_webView canGoBack]) [_webView goBack]; }
- (void)goForward:(id)s { if ([_webView canGoForward]) [_webView goForward]; }
- (void)commitAddress:(id)s { [self submitAddressField]; }

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object == _addressFieldInner) [self submitAddressField];
}

- (void)submitAddressField {
    NSString *raw = [_addressFieldInner.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (raw.length == 0) return;
    NSURL *url = nil;
    if ([raw containsString:@"://"]) url = [NSURL URLWithString:raw];
    if (!url) {
        if ([raw containsString:@"."] && ![raw containsString:@" "])
            url = [NSURL URLWithString:[@"https://" stringByAppendingString:raw]];
        else {
            NSString *q = [raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            url = [NSURL URLWithString:[@"https://www.google.com/search?q=" stringByAppendingString:q ?: @""]];
        }
    }
    if (url && self.openURLHandler) self.openURLHandler(self.paneIndex, url);
    else if (url) [self loadURL:url];
}

@end
