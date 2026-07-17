#import "BrowserFeedAssistController.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"
#import "BrowserTab.h"
#import "BrowserFeedDetector.h"
#import "BrowserFeedItem.h"
#import "BrowserFeedReader.h"
#import "BrowserFeedURLSchemeHandler.h"

@interface BrowserFeedAssistController ()
@property (nonatomic, copy) NSArray<BrowserFeedItem *> *currentFeeds;
@property (nonatomic, strong) NSMapTable<WKWebView *, NSArray<BrowserFeedItem *> *> *feedsByWebView;
@property (nonatomic, strong) BrowserFeedURLSchemeHandler *feedURLSchemeHandler;
@end

@implementation BrowserFeedAssistController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _currentFeeds = @[];
        _feedsByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _feedURLSchemeHandler = [[BrowserFeedURLSchemeHandler alloc] init];
    }
    return self;
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [BrowserFeedDetector installOnConfiguration:configuration messageHandler:self];
    // 须在创建 WKWebView 前注册；同一 configuration 只注册一次。
    if (![configuration urlSchemeHandlerForURLScheme:BrowserFeedURLScheme]) {
        [configuration setURLSchemeHandler:self.feedURLSchemeHandler forURLScheme:BrowserFeedURLScheme];
    }
}

- (void)wireFeedButton:(NSButton *)button {
    self.feedButton = button;
    button.target = self;
    button.action = @selector(showFeedMenu:);
    [self refreshButtonAppearance];
}

#pragma mark - Navigation

- (void)updateForURL:(NSURL *)url {
    (void)url;
    WKWebView *webView = self.windowController.webView;
    if (webView) {
        NSArray<BrowserFeedItem *> *feeds = [self.feedsByWebView objectForKey:webView];
        self.currentFeeds = feeds ?: @[];
    } else {
        self.currentFeeds = @[];
    }
    [self refreshButtonAppearance];
}

- (void)noteNavigationStartedInWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    [self.feedsByWebView setObject:@[] forKey:webView];
    if (webView == self.windowController.webView) {
        self.currentFeeds = @[];
        [self refreshButtonAppearance];
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    (void)url;
    if (!webView) {
        return;
    }
    // Feed 可读页本身无 <link rel=alternate>，跳过扫描。
    if ([BrowserFeedReader isFeedReaderURL:webView.URL]) {
        return;
    }
    // 文档结束脚本可能早于 didFinish；主动再扫一次避免被清空后漏报。
    [webView evaluateJavaScript:
     @"(function(){"
     @"  try {"
     @"    var nodes = document.querySelectorAll('link[rel]');"
     @"    var seen = {}; var feeds = [];"
     @"    function isFeedType(type) {"
     @"      if (!type) return false; var t = String(type).toLowerCase();"
     @"      return t.indexOf('application/rss+xml') !== -1"
     @"          || t.indexOf('application/atom+xml') !== -1"
     @"          || t.indexOf('application/feed+json') !== -1"
     @"          || t.indexOf('application/rdf+xml') !== -1;"
     @"    }"
     @"    function hasFeedRel(rel) {"
     @"      if (!rel) return false;"
     @"      return String(rel).toLowerCase().split(/\\s+/).some(function(p){return p==='alternate'||p==='feed';});"
     @"    }"
     @"    for (var i = 0; i < nodes.length; i++) {"
     @"      var el = nodes[i]; var href = el.getAttribute('href');"
     @"      if (!href || !hasFeedRel(el.getAttribute('rel')) || !isFeedType(el.getAttribute('type')||'')) continue;"
     @"      var url = new URL(href, document.baseURI || location.href).href;"
     @"      if (seen[url]) continue; seen[url] = true;"
     @"      feeds.push({ title: (el.getAttribute('title')||'').trim(), url: url, type: el.getAttribute('type')||'' });"
     @"    }"
     @"    return feeds;"
     @"  } catch (e) { return []; }"
     @"})()"
                     completionHandler:^(id result, NSError *error) {
        (void)error;
        if (![result isKindOfClass:[NSArray class]]) {
            return;
        }
        NSMutableArray<BrowserFeedItem *> *parsed = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (id item in (NSArray *)result) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *feedDict = (NSDictionary *)item;
            NSString *urlString = feedDict[@"url"];
            if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
                continue;
            }
            NSURL *feedURL = [NSURL URLWithString:urlString];
            if (!feedURL || [seen containsObject:feedURL.absoluteString]) {
                continue;
            }
            [seen addObject:feedURL.absoluteString];
            BrowserFeedItem *feed = [[BrowserFeedItem alloc] init];
            NSString *title = feedDict[@"title"];
            feed.title = [title isKindOfClass:[NSString class]] && title.length > 0
                ? title
                : (feedURL.host ?: urlString);
            feed.url = feedURL;
            NSString *type = feedDict[@"type"];
            feed.mimeType = [type isKindOfClass:[NSString class]] ? type : nil;
            [parsed addObject:feed];
        }
        NSArray<BrowserFeedItem *> *feeds = [parsed copy];
        [self.feedsByWebView setObject:feeds forKey:webView];
        if (webView == self.windowController.webView) {
            self.currentFeeds = feeds;
            [self refreshButtonAppearance];
        }
    }];
}

#pragma mark - Feed reader intercept

- (BOOL)handleNavigationResponseIfFeed:(WKNavigationResponse *)navigationResponse
                               webView:(WKWebView *)webView
                       decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (![BrowserFeedReader shouldHandleNavigationResponse:navigationResponse] || !webView) {
        return NO;
    }

    NSURL *feedURL = navigationResponse.response.URL;
    if (!feedURL) {
        return NO;
    }

    // 取消原始 XML 导航，改走自定义 scheme，确保可读页进入后退栈。
    decisionHandler(WKNavigationResponsePolicyCancel);
    NSURL *readerURL = [BrowserFeedReader readerURLForFeedURL:feedURL];
    if (readerURL) {
        [webView loadRequest:[NSURLRequest requestWithURL:readerURL]];
    }
    return YES;
}

#pragma mark - Script messages

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:BrowserFeedAssistHandlerName]) {
        return;
    }
    WKWebView *webView = message.webView;
    if (!webView) {
        return;
    }

    id body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)body;
    if (![dict[@"event"] isEqualToString:@"feeds"]) {
        return;
    }
    NSArray *raw = dict[@"feeds"];
    if (![raw isKindOfClass:[NSArray class]]) {
        return;
    }

    NSMutableArray<BrowserFeedItem *> *parsed = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *feedDict = (NSDictionary *)item;
        NSString *urlString = feedDict[@"url"];
        if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
            continue;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url || [seen containsObject:url.absoluteString]) {
            continue;
        }
        [seen addObject:url.absoluteString];

        BrowserFeedItem *feed = [[BrowserFeedItem alloc] init];
        NSString *title = feedDict[@"title"];
        feed.title = [title isKindOfClass:[NSString class]] && title.length > 0
            ? title
            : (url.host ?: urlString);
        feed.url = url;
        NSString *type = feedDict[@"type"];
        feed.mimeType = [type isKindOfClass:[NSString class]] ? type : nil;
        [parsed addObject:feed];
    }

    NSArray<BrowserFeedItem *> *feeds = [parsed copy];
    [self.feedsByWebView setObject:feeds forKey:webView];
    if (webView == self.windowController.webView) {
        self.currentFeeds = feeds;
        [self refreshButtonAppearance];
    }
}

#pragma mark - UI

- (void)refreshButtonAppearance {
    NSButton *button = self.feedButton;
    if (!button) {
        return;
    }
    BOOL hasFeeds = self.currentFeeds.count > 0;
    button.enabled = hasFeeds;

    if (@available(macOS 10.14, *)) {
        button.contentTintColor = hasFeeds
            ? [NSColor controlAccentColor]
            : [NSColor secondaryLabelColor];
    }

    if (hasFeeds) {
        button.toolTip = [NSString stringWithFormat:@"RSS · 发现 %lu 个 Feed",
                          (unsigned long)self.currentFeeds.count];
    } else {
        button.toolTip = @"RSS（当前页未发现 Feed）";
    }
}

- (IBAction)showFeedMenu:(id)sender {
    if (self.currentFeeds.count == 0) {
        return;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"RSS"];
    menu.autoenablesItems = NO;
    for (BrowserFeedItem *feed in self.currentFeeds) {
        NSString *title = feed.title.length > 0 ? feed.title : (feed.url.absoluteString ?: @"Feed");
        NSString *urlString = feed.url.absoluteString ?: @"";
        if (urlString.length > 0 && ![title isEqualToString:urlString]) {
            // 单行展示：标题 + 缩短 URL
            NSString *shortURL = urlString;
            if (shortURL.length > 64) {
                shortURL = [[shortURL substringToIndex:61] stringByAppendingString:@"…"];
            }
            title = [NSString stringWithFormat:@"%@  ·  %@", title, shortURL];
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(openFeedFromMenu:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = feed.url;
        item.toolTip = urlString;
        item.enabled = YES;
        [menu addItem:item];
    }

    if ([sender isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)sender;
        NSPoint location = NSMakePoint(0, NSHeight(view.bounds) + 2);
        [menu popUpMenuPositioningItem:nil atLocation:location inView:view];
        return;
    }

    NSButton *button = self.feedButton;
    if (button && !button.hidden && button.window) {
        NSPoint location = NSMakePoint(0, NSHeight(button.bounds) + 2);
        [menu popUpMenuPositioningItem:nil atLocation:location inView:button];
        return;
    }

    NSEvent *event = NSApp.currentEvent;
    NSView *host = self.windowController.window.contentView;
    if (event && host) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:host];
    }
}

- (void)openFeedFromMenu:(NSMenuItem *)sender {
    NSURL *url = sender.representedObject;
    if (![url isKindOfClass:[NSURL class]]) {
        return;
    }
    // 始终在新标签打开 Feed。
    [self.windowController.tabController addTabWithURL:url];
}

@end
