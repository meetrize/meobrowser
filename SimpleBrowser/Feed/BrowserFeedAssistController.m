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
@property (nonatomic, strong) NSMapTable<WKWebView *, NSNumber *> *probeGenerationByWebView;
@property (nonatomic, strong) BrowserFeedURLSchemeHandler *feedURLSchemeHandler;
@end

@implementation BrowserFeedAssistController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _currentFeeds = @[];
        _feedsByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _probeGenerationByWebView = [NSMapTable weakToStrongObjectsMapTable];
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
    NSUInteger next = [[self.probeGenerationByWebView objectForKey:webView] unsignedIntegerValue] + 1;
    [self.probeGenerationByWebView setObject:@(next) forKey:webView];
    [self.feedsByWebView setObject:@[] forKey:webView];
    if (webView == self.windowController.webView) {
        self.currentFeeds = @[];
        [self refreshButtonAppearance];
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    if (!webView) {
        return;
    }
    // Feed 可读页本身无 <link rel=alternate>，跳过扫描。
    if ([BrowserFeedReader isFeedReaderURL:webView.URL]) {
        return;
    }
    NSURL *pageURL = url ?: webView.URL;
    NSUInteger generation = [[self.probeGenerationByWebView objectForKey:webView] unsignedIntegerValue];

    // 文档结束脚本可能早于 didFinish；主动再扫一次避免被清空后漏报。
    [webView evaluateJavaScript:[BrowserFeedDetector scanFeedsJavaScript]
              completionHandler:^(id result, NSError *error) {
        (void)error;
        if ([[self.probeGenerationByWebView objectForKey:webView] unsignedIntegerValue] != generation) {
            return;
        }
        NSArray<BrowserFeedItem *> *parsed = [BrowserFeedDetector feedItemsFromDictionaries:
                                              [result isKindOfClass:[NSArray class]] ? result : @[]];
        if (parsed.count > 0) {
            [self applyFeeds:parsed forWebView:webView merge:NO];
            return;
        }
        // 页面未声明 Feed（如 36kr）：探测 /feed、/rss、atom.xml 等常见路径。
        [self probeConventionalFeedsForWebView:webView pageURL:pageURL generation:generation];
    }];
}

- (void)probeConventionalFeedsForWebView:(WKWebView *)webView
                                pageURL:(NSURL *)pageURL
                             generation:(NSUInteger)generation {
    if (!webView || !pageURL) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BrowserFeedDetector probeConventionalFeedsForPageURL:pageURL
                                        completionHandler:^(NSArray<BrowserFeedItem *> *feeds) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if ([[strongSelf.probeGenerationByWebView objectForKey:webView] unsignedIntegerValue] != generation) {
            return;
        }
        if (feeds.count == 0) {
            return;
        }
        // 若期间 HTML 扫描已发现 Feed，则合并去重。
        [strongSelf applyFeeds:feeds forWebView:webView merge:YES];
    }];
}

- (void)applyFeeds:(NSArray<BrowserFeedItem *> *)feeds
        forWebView:(WKWebView *)webView
             merge:(BOOL)merge {
    if (!webView) {
        return;
    }
    NSArray<BrowserFeedItem *> *finalFeeds = feeds ?: @[];
    if (merge) {
        NSArray<BrowserFeedItem *> *existing = [self.feedsByWebView objectForKey:webView] ?: @[];
        if (existing.count > 0) {
            NSMutableArray<BrowserFeedItem *> *merged = [existing mutableCopy];
            NSMutableSet<NSString *> *seen = [NSMutableSet set];
            for (BrowserFeedItem *item in existing) {
                if (item.url.absoluteString.length > 0) {
                    [seen addObject:item.url.absoluteString];
                }
            }
            for (BrowserFeedItem *item in feeds) {
                NSString *key = item.url.absoluteString;
                if (key.length == 0 || [seen containsObject:key]) {
                    continue;
                }
                [seen addObject:key];
                [merged addObject:item];
            }
            finalFeeds = [merged copy];
        }
    }
    [self.feedsByWebView setObject:finalFeeds forKey:webView];
    if (webView == self.windowController.webView) {
        self.currentFeeds = finalFeeds;
        [self refreshButtonAppearance];
    }
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
    NSArray<BrowserFeedItem *> *parsed = [BrowserFeedDetector feedItemsFromDictionaries:
                                          [raw isKindOfClass:[NSArray class]] ? raw : @[]];

    // 空结果不覆盖已探测到的常规路径 Feed（避免 MutationObserver 晚到的空扫描清掉按钮）。
    if (parsed.count == 0) {
        NSArray<BrowserFeedItem *> *existing = [self.feedsByWebView objectForKey:webView];
        if (existing.count > 0) {
            return;
        }
        [self applyFeeds:@[] forWebView:webView merge:NO];
        return;
    }
    [self applyFeeds:parsed forWebView:webView merge:YES];
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
