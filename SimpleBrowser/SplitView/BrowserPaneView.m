#import "BrowserPaneView.h"

@interface BrowserPaneView ()
@property (nonatomic, strong) NSView *chromeBar;
@property (nonatomic, strong) NSView *contentHostInner;
@property (nonatomic, strong) NSTextField *addressFieldInner;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *fwdBtn;
@property (nonatomic, strong) NSButton *goBtn;
@property (nonatomic, strong) NSTrackingArea *chromeTracking;
@property (nonatomic, strong) NSTextField *syncBadgeLabel;
@property (nonatomic, assign) BOOL mouseInside;
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
            // 内容区永远撑满整个 pane(自动隐藏/隐藏模式不给地址栏预留空间)
            [_contentHostInner.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_contentHostInner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_contentHostInner.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_contentHostInner.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        // 地址栏浮层:盖在内容区上面(z-order 最前),hover 时滑下来盖住网页顶部
        // 注意:chromeBar 已在 contentHost 之前 addSubview,需显式顶到最前
        [self addSubview:_chromeBar positioned:NSWindowAbove relativeTo:nil];
        [self applyChromeModeAnimated:NO];
        _syncBadgeLabel = [NSTextField labelWithString:@""];
        _syncBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _syncBadgeLabel.font = [NSFont boldSystemFontOfSize:11];
        _syncBadgeLabel.textColor = [NSColor controlAccentColor];
        _syncBadgeLabel.hidden = YES;
        [self addSubview:_syncBadgeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_syncBadgeLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:34],
            [_syncBadgeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        ]];
    }
    return self;
}
- (void)setSyncBadge:(NSString *)badge {
    _syncBadgeLabel.stringValue = badge ?: @"";
    _syncBadgeLabel.hidden = (badge.length == 0);
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
    (void)animated;
    if (_chromeMode == BrowserPaneChromeAlways) {
        _chromeBar.hidden = NO;
        [self setContentTopInset:30];
    } else if (_chromeMode == BrowserPaneChromeAutohide) {
        // 自动隐藏:内容撑满;显示时浮层盖住顶部(不挤压网页)
        [self setContentTopInset:0];
        _chromeBar.hidden = !(self.active && self.mouseInside);
    } else {
        [self setContentTopInset:0];
        _chromeBar.hidden = YES;
    }
}
/// 内容区顶部内边距:总是显示=30(地址栏占位),其余=0(撑满)
- (void)setContentTopInset:(CGFloat)inset {
    for (NSLayoutConstraint *con in self.constraints) {
        if (con.firstItem == _contentHostInner && con.firstAttribute == NSLayoutAttributeTop) {
            con.constant = inset;
            return;
        }
    }
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
    (void)e;
    _mouseInside = YES;
    // 自动隐藏:鼠标移到栏内,地址栏从顶部滑下来盖住网页(不抢焦点,点击才聚焦)
    if (_chromeMode == BrowserPaneChromeAutohide) _chromeBar.hidden = NO;
}
- (void)mouseDown:(NSEvent *)e {
    // 子视图(地址栏/按钮/WebView)会先吃掉自己的点击;落到这里说明点在空白处 -> 聚焦本栏
    if (self.becameActiveHandler) self.becameActiveHandler(self.paneIndex);
    else self.active = YES;
    [super mouseDown:e];
}

- (void)mouseExited:(NSEvent *)e {
    (void)e;
    _mouseInside = NO;
    if (_chromeMode == BrowserPaneChromeAutohide) {
        // 焦点在地址框里(正在输入)就不藏,输完回车/切走再藏
        if ([self.window.firstResponder isKindOfClass:[NSTextView class]]) {
            NSText *ed = _addressFieldInner.currentEditor;
            if (self.window.firstResponder == (id)ed) return;
        }
        _chromeBar.hidden = YES;
    }
}

- (void)detachWebView {
    if (_webView) {
        @try { [_webView removeObserver:self forKeyPath:@"URL"]; } @catch (NSException *e) {}
    }
    [_webView removeFromSuperview];
    _webView = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"URL"] && object == _webView) {
        NSURL *url = _webView.URL ?: change[NSKeyValueChangeNewKey];
        if ([url isKindOfClass:[NSNull class]]) url = nil;
        if ([url isKindOfClass:[NSURL class]] || url == nil) {
            [self updateAddressFieldWithURL:url];
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc {
    if (_webView) {
        @try { [_webView removeObserver:self forKeyPath:@"URL"]; } @catch (NSException *e) {}
    }
}

- (void)attachWebView:(WKWebView *)webView {
    if (_webView == webView) return;
    if (_webView) {
        @try { [_webView removeObserver:self forKeyPath:@"URL"]; } @catch (NSException *e) {}
    }
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
    @try {
        [webView addObserver:self forKeyPath:@"URL"
                    options:NSKeyValueObservingOptionNew
                    context:NULL];
    } @catch (NSException *e) {}
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
    if (![NSThread isMainThread]) {
        NSURL *u = url;
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateAddressFieldWithURL:u]; });
        return;
    }
    if (!url) return;
    // 用户正在本栏输入时不抢写,避免覆盖编辑中的字符
    if (self.window.firstResponder && self.window.firstResponder == (id)_addressFieldInner.currentEditor) return;
    NSString *s = url.absoluteString;
    if (s.length && ![s isEqualToString:_addressFieldInner.stringValue]) {
        _addressFieldInner.stringValue = s;
    }
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
