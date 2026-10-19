#import "BrowserPaneView.h"

@interface BrowserPaneView ()
@property (nonatomic, strong) NSView *chromeBar;
@property (nonatomic, strong) NSView *contentHostInner;
@property (nonatomic, strong) NSTextField *addressFieldInner;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *fwdBtn;
@property (nonatomic, strong) NSButton *reloadBtn;
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

        _backBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(goBack:)];
        _backBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self styleNavButton:_backBtn symbol:@"chevron.backward" fallback:@"‹" tip:@"后退"];
        [_chromeBar addSubview:_backBtn];
        _fwdBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(goForward:)];
        _fwdBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self styleNavButton:_fwdBtn symbol:@"chevron.forward" fallback:@"›" tip:@"前进"];
        [_chromeBar addSubview:_fwdBtn];
        _reloadBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(reloadPane:)];
        _reloadBtn.translatesAutoresizingMaskIntoConstraints = NO;
        _reloadBtn.enabled = NO;
        [self styleNavButton:_reloadBtn symbol:@"arrow.clockwise" fallback:@"↻" tip:@"刷新本栏"];
        [_chromeBar addSubview:_reloadBtn];
        [self applyReloadIconForLoading:NO];
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
        // 分栏地址栏恒为单行：长 URL 超宽时尾部截断，不折行（折行会把栏撑高、错位）。
        _addressFieldInner.usesSingleLineMode = YES;
        _addressFieldInner.lineBreakMode = NSLineBreakByTruncatingTail;
        _addressFieldInner.cell.wraps = NO;
        _addressFieldInner.cell.truncatesLastVisibleLine = YES;
        // 去掉聚焦时的加粗蓝色描边（focus ring），改用自身边框表达聚焦。
        _addressFieldInner.focusRingType = NSFocusRingTypeNone;
        [_chromeBar addSubview:_addressFieldInner];
        _goBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(commitAddress:)];
        _goBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self styleNavButton:_goBtn symbol:@"arrow.right.circle" fallback:@"→" tip:@"前往"];
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
            [_reloadBtn.leadingAnchor constraintEqualToAnchor:_fwdBtn.trailingAnchor constant:2],
            [_reloadBtn.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_reloadBtn.widthAnchor constraintEqualToConstant:20],
            [_reloadBtn.heightAnchor constraintEqualToConstant:20],
            [_goBtn.trailingAnchor constraintEqualToAnchor:_chromeBar.trailingAnchor constant:-4],
            [_goBtn.centerYAnchor constraintEqualToAnchor:_chromeBar.centerYAnchor],
            [_goBtn.widthAnchor constraintEqualToConstant:22],
            [_goBtn.heightAnchor constraintEqualToConstant:20],
            [_addressFieldInner.leadingAnchor constraintEqualToAnchor:_reloadBtn.trailingAnchor constant:4],
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
        @try { [_webView removeObserver:self forKeyPath:@"isLoading"]; } @catch (NSException *e) {}
    }
    [_webView removeFromSuperview];
    _webView = nil;
    [self syncReloadButtonState];
    [self syncNavButtonStates];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"isLoading"] && object == _webView) {
        [self applyReloadIconForLoading:_webView.isLoading];
        return;
    }
    if ([keyPath isEqualToString:@"URL"] && object == _webView) {
        NSURL *url = _webView.URL ?: change[NSKeyValueChangeNewKey];
        if ([url isKindOfClass:[NSNull class]]) url = nil;
        if ([url isKindOfClass:[NSURL class]] || url == nil) {
            [self updateAddressFieldWithURL:url];
        }
        [self syncNavButtonStates];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

/// 后退/前进可用态随历史变化；不可用时降到三级标签色，一眼看出"没得可点"。
- (void)syncNavButtonStates {
    BOOL hasWebView = (_webView != nil);
    BOOL canBack = hasWebView && _webView.canGoBack;
    BOOL canFwd = hasWebView && _webView.canGoForward;
    _backBtn.enabled = canBack;
    _fwdBtn.enabled = canFwd;
    _backBtn.contentTintColor = canBack ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor];
    _fwdBtn.contentTintColor = canFwd ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor];
}

- (void)dealloc {
    if (_webView) {
        @try { [_webView removeObserver:self forKeyPath:@"URL"]; } @catch (NSException *e) {}
        @try { [_webView removeObserver:self forKeyPath:@"isLoading"]; } @catch (NSException *e) {}
    }
}

- (void)attachWebView:(WKWebView *)webView {
    if (_webView == webView) return;
    if (_webView) {
        @try { [_webView removeObserver:self forKeyPath:@"URL"]; } @catch (NSException *e) {}
        @try { [_webView removeObserver:self forKeyPath:@"isLoading"]; } @catch (NSException *e) {}
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
    @try {
        [webView addObserver:self forKeyPath:@"isLoading"
                    options:NSKeyValueObservingOptionNew
                    context:NULL];
    } @catch (NSException *e) {}
    [self syncReloadButtonState];
    [self syncNavButtonStates];
    [self applyReloadIconForLoading:webView.isLoading];
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

- (void)goBack:(id)s { if ([_webView canGoBack]) { [_webView goBack]; [self syncNavButtonStates]; } }
- (void)goForward:(id)s { if ([_webView canGoForward]) { [_webView goForward]; [self syncNavButtonStates]; } }

/// 导航键统一外观：无边框图标按钮（macOS 11+ 用 SF Symbol，旧系统回退字符）。
- (void)styleNavButton:(NSButton *)button symbol:(NSString *)symbol fallback:(NSString *)fallback tip:(NSString *)tip {
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.contentTintColor = [NSColor secondaryLabelColor];
    button.toolTip = tip;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                             weight:NSFontWeightRegular
                                                              scale:NSImageSymbolScaleMedium];
        NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
        if (img) { button.image = [img imageWithSymbolConfiguration:cfg]; return; }
    }
    button.title = fallback;
}

/// 刷新图标:空闲=顺时针箭头,加载中=叉(点击即停止),与 Safari 一致。
- (void)applyReloadIconForLoading:(BOOL)loading {
    if (@available(macOS 11.0, *)) {
        NSString *symbol = loading ? @"xmark" : @"arrow.clockwise";
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                             weight:NSFontWeightRegular
                                                              scale:NSImageSymbolScaleMedium];
        NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:(loading ? @"停止" : @"刷新")];
        if (img) _reloadBtn.image = [img imageWithSymbolConfiguration:cfg];
    } else {
        _reloadBtn.title = loading ? @"✕" : @"↻";
    }
    _reloadBtn.toolTip = loading ? @"停止加载" : @"刷新本栏";
}

- (void)syncReloadButtonState {
    BOOL hasWebView = (_webView != nil);
    _reloadBtn.enabled = hasWebView;
    if (!hasWebView) {
        [self applyReloadIconForLoading:NO];
    }
}

- (void)reloadPane:(id)s {
    WKWebView *webView = _webView;
    if (!webView) {
        // 该栏还没建页：退回成「按地址栏内容加载」
        [self submitAddressField];
        return;
    }
    if (webView.isLoading) {
        [webView stopLoading];
        return;
    }
    NSURL *url = webView.URL;
    if (url) {
        [webView loadRequest:[NSURLRequest requestWithURL:url]];
    } else {
        [webView reload];
    }
}

- (void)commitAddress:(id)s { [self submitAddressField]; }

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object != _addressFieldInner) return;
    // 结束编辑 ≠ 回车提交。点地址栏后再点页面也会走这里，若无条件提交就会把当前页
    // 重新 load 一遍（表现为"点一下页面自动刷新"）。仅当内容与当前页 URL 不同才跳转。
    [self submitAddressFieldOnlyIfChanged];
}

/// 仅在地址栏内容与当前页地址不同时才跳转（用于失焦提交）。
- (void)submitAddressFieldOnlyIfChanged {
    NSString *typed = [_addressFieldInner.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *current = _webView.URL.absoluteString ?: @"";
    if (typed.length == 0 || [typed isEqualToString:current]) return;
    [self submitAddressField];
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
