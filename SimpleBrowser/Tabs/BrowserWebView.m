#import "BrowserWebView.h"
#import "BrowsingPreferences.h"

@interface BrowserWebView ()
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuDownload;
@property (nonatomic, assign, readwrite) BOOL pendingContextMenuOpenInNewWindow;
@property (nonatomic, weak) NSMenuItem *openResourceMenuItem;
@property (nonatomic, weak) NSMenuItem *openLinkInNewWindowMenuItem;
@property (nonatomic, strong, nullable) NSEvent *contextMenuEvent;
@end

@implementation BrowserWebView

- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super willOpenMenu:menu withEvent:event];

    self.contextMenuEvent = event;
    self.pendingContextMenuDownload = NO;
    self.pendingContextMenuOpenInNewWindow = NO;
    self.openResourceMenuItem = nil;
    self.openLinkInNewWindowMenuItem = nil;

    NSMenuItem *downloadItem = nil;
    NSMenuItem *openImageItem = nil;
    NSMenuItem *openMediaItem = nil;
    NSMenuItem *openLinkInNewWindowItem = nil;
    NSMenuItem *searchWebItem = nil;

    NSString *engineName = [BrowsingPreferences displayNameForSearchEngineID:[BrowsingPreferences defaultSearchEngineID]];
    NSString *searchTitle = [NSString stringWithFormat:@"使用「%@」搜索", engineName];

    for (NSMenuItem *item in menu.itemArray) {
        if ([self isSearchWebMenuItem:item]) {
            item.title = searchTitle;
            item.target = self;
            item.action = @selector(meo_searchSelectionWithDefaultEngine:);
            searchWebItem = item;
            continue;
        }

        NSString *identifier = item.identifier;
        if ([identifier isEqualToString:@"WKMenuItemIdentifierDownloadImage"] ||
            [identifier isEqualToString:@"WKMenuItemIdentifierDownloadMedia"]) {
            downloadItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenImageInNewWindow"]) {
            openImageItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenMediaInNewWindow"]) {
            openMediaItem = item;
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenLinkInNewWindow"]) {
            openLinkInNewWindowItem = item;
        }
    }

    // WebKit 该项实际会走 createWebView → 本应用开新标签，标题改为与行为一致。
    if (openLinkInNewWindowItem) {
        openLinkInNewWindowItem.title = @"在新标签页中打开链接";
        self.openLinkInNewWindowMenuItem = openLinkInNewWindowItem;

        NSInteger index = [menu indexOfItem:openLinkInNewWindowItem];
        if (index != NSNotFound) {
            NSMenuItem *openInWindow = [[NSMenuItem alloc] initWithTitle:@"在新窗口中打开链接"
                                                                  action:@selector(meo_openLinkInNewWindow:)
                                                           keyEquivalent:@""];
            openInWindow.target = self;
            openInWindow.representedObject = openLinkInNewWindowItem;
            [menu insertItem:openInWindow atIndex:index + 1];
        }
    }

    // 选中文本含 http(s):// 时，提供「在新标签中打开」（已有链接菜单时不必重复）。
    if (!openLinkInNewWindowItem) {
        [self meo_insertOpenSelectionURLItemInMenu:menu nearItem:searchWebItem];
    }

    if (downloadItem) {
        // WebKit 系统「Download Image/Media」常不触发 WKDownload；改为劫持 Open*InNewWindow 取 URL。
        NSMenuItem *openItem = nil;
        if ([downloadItem.identifier isEqualToString:@"WKMenuItemIdentifierDownloadMedia"]) {
            openItem = openMediaItem ?: openImageItem;
        } else {
            openItem = openImageItem ?: openMediaItem;
        }
        self.openResourceMenuItem = openItem;
        downloadItem.target = self;
        downloadItem.action = @selector(meo_downloadContextResource:);
        downloadItem.representedObject = openItem;
    }
}

- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super didCloseMenu:menu withEvent:event];
    // createWebView 异步到达，稍后再清标记，避免误伤普通弹窗导航。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingContextMenuDownload = NO;
        strongSelf.pendingContextMenuOpenInNewWindow = NO;
        strongSelf.openResourceMenuItem = nil;
        strongSelf.openLinkInNewWindowMenuItem = nil;
        strongSelf.contextMenuEvent = nil;
    });
}

- (BOOL)isSearchWebMenuItem:(NSMenuItem *)item {
    NSString *identifier = item.identifier;
    if ([identifier isEqualToString:@"WKMenuItemIdentifierSearchWeb"]) {
        return YES;
    }

    NSString *title = item.title ?: @"";
    if (title.length == 0) {
        return NO;
    }

    NSString *lower = title.lowercaseString;
    // 英文：Search with Google / Search DuckDuckGo…
    if ([lower containsString:@"search with "] ||
        [lower hasPrefix:@"search google"] ||
        [lower hasPrefix:@"search duckduckgo"] ||
        [lower hasPrefix:@"search bing"] ||
        [lower hasPrefix:@"search yahoo"] ||
        [lower hasPrefix:@"search ecosia"] ||
        [lower hasPrefix:@"search baidu"]) {
        return YES;
    }

    // 中文：使用「Google」搜索 / 用 Google 搜索
    BOOL looksLikeChineseSearch = [title containsString:@"搜索"] &&
        ([title containsString:@"使用"] || [title hasPrefix:@"用"]);
    if (looksLikeChineseSearch) {
        return YES;
    }

    return NO;
}

- (void)meo_insertOpenSelectionURLItemInMenu:(NSMenu *)menu nearItem:(NSMenuItem *)nearItem {
    NSMenuItem *openSelectionURLItem = [[NSMenuItem alloc] initWithTitle:@"在新标签中打开"
                                                                  action:@selector(meo_openSelectionURLInNewTab:)
                                                           keyEquivalent:@""];
    openSelectionURLItem.target = self;
    openSelectionURLItem.hidden = YES;

    if (nearItem) {
        NSInteger index = [menu indexOfItem:nearItem];
        if (index != NSNotFound) {
            [menu insertItem:openSelectionURLItem atIndex:index];
        } else {
            [menu insertItem:openSelectionURLItem atIndex:0];
        }
    } else {
        [menu insertItem:openSelectionURLItem atIndex:0];
    }

    __weak typeof(self) weakSelf = self;
    __weak NSMenu *weakMenu = menu;
    __weak NSMenuItem *weakItem = openSelectionURLItem;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        NSMenu *strongMenu = weakMenu;
        NSMenuItem *strongItem = weakItem;
        if (!strongSelf || !strongMenu || !strongItem) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            if ([strongMenu.itemArray containsObject:strongItem]) {
                [strongMenu removeItem:strongItem];
            }
            return;
        }

        NSString *urlString = [strongSelf meo_HTTPURLStringFromSelectedText:(NSString *)result];
        if (urlString.length == 0) {
            if ([strongMenu.itemArray containsObject:strongItem]) {
                [strongMenu removeItem:strongItem];
            }
            return;
        }

        strongItem.representedObject = urlString;
        strongItem.hidden = NO;
    }];
}

- (nullable NSString *)meo_HTTPURLStringFromSelectedText:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSRange httpsRange = [trimmed rangeOfString:@"https://" options:NSCaseInsensitiveSearch];
    NSRange httpRange = [trimmed rangeOfString:@"http://" options:NSCaseInsensitiveSearch];

    NSUInteger start = NSNotFound;
    if (httpsRange.location != NSNotFound && httpRange.location != NSNotFound) {
        start = MIN(httpsRange.location, httpRange.location);
    } else if (httpsRange.location != NSNotFound) {
        start = httpsRange.location;
    } else if (httpRange.location != NSNotFound) {
        start = httpRange.location;
    }
    if (start == NSNotFound) {
        return nil;
    }

    NSString *fromURL = [trimmed substringFromIndex:start];
    NSRange whitespace = [fromURL rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (whitespace.location != NSNotFound) {
        fromURL = [fromURL substringToIndex:whitespace.location];
    }

    static NSCharacterSet *trailingPunctuation;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trailingPunctuation = [NSCharacterSet characterSetWithCharactersInString:@". ,;:)]}\"'" ];
    });
    while (fromURL.length > 0) {
        unichar last = [fromURL characterAtIndex:fromURL.length - 1];
        if (![trailingPunctuation characterIsMember:last]) {
            break;
        }
        fromURL = [fromURL substringToIndex:fromURL.length - 1];
    }

    NSURL *url = [NSURL URLWithString:fromURL];
    if (!url.scheme.length || !url.host.length) {
        return nil;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }

    return fromURL;
}

- (void)meo_openSelectionURLInNewTab:(id)sender {
    NSString *urlString = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        id represented = [(NSMenuItem *)sender representedObject];
        if ([represented isKindOfClass:[NSString class]]) {
            urlString = (NSString *)represented;
        }
    }

    __weak typeof(self) weakSelf = self;
    void (^openURL)(NSString *) = ^(NSString *candidate) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || candidate.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:candidate];
        if (!url) {
            return;
        }
        if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        } else {
            [strongSelf loadRequest:[NSURLRequest requestWithURL:url]];
        }
    };

    if (urlString.length > 0) {
        openURL(urlString);
        return;
    }

    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *extracted = [strongSelf meo_HTTPURLStringFromSelectedText:(NSString *)result];
        openURL(extracted);
    }];
}

- (void)meo_searchSelectionWithDefaultEngine:(id)sender {
#pragma unused(sender)
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSURL *url = [BrowsingPreferences searchURLForQuery:(NSString *)result];
        if (!url) {
            return;
        }
        if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        } else {
            [strongSelf loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }];
}

- (void)meo_openLinkInNewWindow:(id)sender {
    NSMenuItem *openItem = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        openItem = [(NSMenuItem *)sender representedObject];
    }
    if (![openItem isKindOfClass:[NSMenuItem class]]) {
        openItem = self.openLinkInNewWindowMenuItem;
    }

    if (openItem.action && openItem.target) {
        self.pendingContextMenuOpenInNewWindow = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [openItem.target performSelector:openItem.action withObject:openItem];
#pragma clang diagnostic pop
        return;
    }

    [self meo_openLinkAtContextMenuPointInNewWindow];
}

- (void)meo_openLinkAtContextMenuPointInNewWindow {
    NSEvent *event = self.contextMenuEvent;
    if (!event) {
        return;
    }

    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = locationInView.x;
    CGFloat y = NSHeight(self.bounds) - locationInView.y;

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  function absUrl(u) {"
         "    try { return new URL(u, document.baseURI).href; } catch (e) { return u; }"
         "  }"
         "  var el = document.elementFromPoint(x, y);"
         "  while (el) {"
         "    if (el.tagName === 'A' && el.href) { return absUrl(el.href); }"
         "    el = el.parentElement;"
         "  }"
         "  return null;"
         "})(%f, %f)", x, y];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *urlString = (NSString *)result;
        if (urlString.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            return;
        }
        if (strongSelf.openURLInNewWindowHandler) {
            strongSelf.openURLInNewWindowHandler(url);
        } else if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        }
    }];
}

- (void)meo_downloadContextResource:(id)sender {
    NSMenuItem *openItem = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        openItem = [(NSMenuItem *)sender representedObject];
    }
    if (![openItem isKindOfClass:[NSMenuItem class]]) {
        openItem = self.openResourceMenuItem;
    }

    if (openItem.action && openItem.target) {
        self.pendingContextMenuDownload = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [openItem.target performSelector:openItem.action withObject:openItem];
#pragma clang diagnostic pop
        return;
    }

    // 找不到 Open Image/Media 时，用点击坐标兜底解析图片 URL。
    [self meo_downloadResourceAtContextMenuPoint];
}

- (void)meo_downloadResourceAtContextMenuPoint {
    NSEvent *event = self.contextMenuEvent;
    if (!event) {
        return;
    }

    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = locationInView.x;
    // AppKit 原点在左下；elementFromPoint 使用视口左上原点。
    CGFloat y = NSHeight(self.bounds) - locationInView.y;

    NSString *script = [NSString stringWithFormat:
        @"(function(x, y) {"
         "  function absUrl(u) {"
         "    try { return new URL(u, document.baseURI).href; } catch (e) { return u; }"
         "  }"
         "  var el = document.elementFromPoint(x, y);"
         "  if (!el) { return null; }"
         "  var n = el;"
         "  while (n) {"
         "    if (n.tagName === 'IMG') {"
         "      return absUrl(n.currentSrc || n.src);"
         "    }"
         "    if (n.tagName === 'VIDEO' || n.tagName === 'AUDIO' || n.tagName === 'SOURCE') {"
         "      var src = n.currentSrc || n.src;"
         "      if (src) { return absUrl(src); }"
         "    }"
         "    if (n.tagName === 'PICTURE') {"
         "      var img = n.querySelector('img');"
         "      if (img) { return absUrl(img.currentSrc || img.src); }"
         "    }"
         "    n = n.parentElement;"
         "  }"
         "  n = el;"
         "  while (n && n !== document.documentElement) {"
         "    var bg = getComputedStyle(n).backgroundImage;"
         "    var m = bg && bg.match(/url\\([\"']?([^\"')]+)[\"']?\\)/);"
         "    if (m && m[1] && m[1] !== 'none') { return absUrl(m[1]); }"
         "    n = n.parentElement;"
         "  }"
         "  return null;"
         "})(%f, %f)", x, y];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *urlString = (NSString *)result;
        if (urlString.length == 0) {
            return;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            return;
        }
        [strongSelf meo_deliverDownloadURL:url];
    }];
}

- (nullable NSURL *)consumePendingContextMenuDownloadURL:(NSURL *)candidateURL {
    if (!self.pendingContextMenuDownload) {
        return nil;
    }
    self.pendingContextMenuDownload = NO;
    self.openResourceMenuItem = nil;
    if (!candidateURL) {
        return nil;
    }
    return candidateURL;
}

- (nullable NSURL *)consumePendingContextMenuOpenInNewWindowURL:(NSURL *)candidateURL {
    if (!self.pendingContextMenuOpenInNewWindow) {
        return nil;
    }
    self.pendingContextMenuOpenInNewWindow = NO;
    self.openLinkInNewWindowMenuItem = nil;
    if (!candidateURL) {
        return nil;
    }
    return candidateURL;
}

- (void)meo_deliverDownloadURL:(NSURL *)url {
    if (!url) {
        return;
    }
    if (self.downloadURLHandler) {
        self.downloadURLHandler(url);
    } else if (@available(macOS 11.3, *)) {
        [self startDownloadUsingRequest:[NSURLRequest requestWithURL:url]
                      completionHandler:^(__unused WKDownload *download) {
        }];
    }
}

@end
