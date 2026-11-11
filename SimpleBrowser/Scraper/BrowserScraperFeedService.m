#import "BrowserScraperFeedService.h"
#import "BrowserScraperFeedHTTPServer.h"
#import "BrowserScraperFeedPreferences.h"
#import "BrowserScraperRSSWriter.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperEngine.h"
#import "BrowserScraperModels.h"
#import "BrowserScraperExcelWriter.h"
#import "BrowserWindowController.h"
#import "BrowserTabController.h"
#import "BrowserTab.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NSNotificationName const BrowserScraperFeedServiceStateDidChangeNotification =
    @"BrowserScraperFeedServiceStateDidChangeNotification";

static const NSTimeInterval kFeedCacheTTL = 60.0;
static const NSTimeInterval kFeedScrapeTimeout = 90.0;
static const NSTimeInterval kFeedPostLoadSettleSec = 1.2;

@interface BrowserScraperFeedCacheEntry : NSObject
@property (nonatomic, strong) NSData *body;
@property (nonatomic, assign) NSTimeInterval expiresAt;
@property (nonatomic, assign) NSInteger itemCount;
@end

@implementation BrowserScraperFeedCacheEntry
@end

@interface BrowserScraperFeedScrapeSession : NSObject <WKNavigationDelegate, BrowserScraperEngineDelegate>
@property (nonatomic, strong) BrowserScraperRecipe *recipe;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, strong, nullable) NSWindow *hostWindow;
@property (nonatomic, assign) BOOL ownsWebView;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, copy, nullable) void (^completion)(NSArray<NSDictionary *> *_Nullable rows, NSError *_Nullable error);
- (void)startOnExistingWebView:(WKWebView *)webView;
- (void)beginOffscreenLoad;
- (void)finishWithRows:(NSArray<NSDictionary *> *_Nullable)rows error:(NSError *_Nullable)error;
@end

@implementation BrowserScraperFeedScrapeSession

- (void)finishWithRows:(NSArray<NSDictionary *> *)rows error:(NSError *)error {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    void (^completion)(NSArray<NSDictionary *> *, NSError *) = self.completion;
    self.completion = nil;
    self.engine.delegate = nil;
    if (self.ownsWebView) {
        self.webView.navigationDelegate = nil;
        [self.webView stopLoading];
        self.webView = nil;
        NSWindow *win = self.hostWindow;
        self.hostWindow = nil;
        if (win) {
            [win orderOut:nil];
            win.contentView = nil;
        }
    } else {
        self.webView = nil;
    }
    if (completion) {
        completion(rows, error);
    }
}

- (void)startEngineOnWebView:(WKWebView *)webView {
    if (self.started || self.finished) {
        return;
    }
    self.started = YES;
    [self.engine startFeedPreviewWithRecipe:self.recipe webView:webView];
}

- (void)startOnExistingWebView:(WKWebView *)webView {
    self.ownsWebView = NO;
    self.webView = webView;
    // 现有标签页已渲染，稍等一帧再抽，避开正在导航的瞬间。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.finished) {
            return;
        }
        [strongSelf startEngineOnWebView:webView];
    });
}

- (void)beginOffscreenLoad {
    NSURL *url = [NSURL URLWithString:self.recipe.startURL];
    if (!url) {
        [self finishWithRows:nil
                       error:[NSError errorWithDomain:@"BrowserScraperFeed"
                                                 code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"startURL 无效"}]];
        return;
    }
    self.ownsWebView = YES;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = (self.recipe.session == BrowserScraperSessionEphemeral)
        ? [WKWebsiteDataStore nonPersistentDataStore]
        : [WKWebsiteDataStore defaultDataStore];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 900) configuration:config];
    webView.navigationDelegate = self;
    self.webView = webView;

    // 挂到隐藏窗口，降低部分站点/WebKit 在无窗口 WebView 上抽取失败的概率。
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 1280, 900)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    win.releasedWhenClosed = NO;
    win.contentView = webView;
    win.alphaValue = 0;
    win.ignoresMouseEvents = YES;
    [win orderBack:nil];
    self.hostWindow = win;

    [webView loadRequest:[NSURLRequest requestWithURL:url]];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.finished || strongSelf.started) {
            return;
        }
        NSLog(@"[ScraperFeed] navigation settle timeout, extract anyway");
        [strongSelf startEngineOnWebView:strongSelf.webView];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    if (self.started || self.finished) {
        return;
    }
    // SPA 常在 didFinish 之后才插入列表节点；短暂 settle 再抽。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFeedPostLoadSettleSec * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.finished || strongSelf.started) {
            return;
        }
        [strongSelf startEngineOnWebView:strongSelf.webView];
    });
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if (self.started) {
        return;
    }
    [self finishWithRows:nil error:error];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if (self.started) {
        return;
    }
    [self finishWithRows:nil error:error];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line {
    (void)engine;
    NSLog(@"[ScraperFeed] %@", line);
}

- (void)scraperEngine:(BrowserScraperEngine *)engine
didFinishWithRunDirectory:(NSString *)runDirectory
                error:(NSError *)error {
    (void)runDirectory;
    NSArray<NSDictionary *> *rows = engine.previewRows ?: @[];
    // 取消被映射为 nil error 时仍返回已抽到的行。
    [self finishWithRows:rows error:error];
}

@end

@interface BrowserScraperFeedService ()
@property (nonatomic, strong) BrowserScraperFeedHTTPServer *server;
@property (nonatomic, assign, readwrite, getter=isListening) BOOL listening;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserScraperFeedCacheEntry *> *cache;
@property (nonatomic, strong, nullable) BrowserScraperFeedScrapeSession *activeSession;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *pendingJobs;
@property (nonatomic, assign) BOOL draining;
@end

@implementation BrowserScraperFeedService

+ (BrowserScraperFeedService *)sharedService {
    static BrowserScraperFeedService *svc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        svc = [[BrowserScraperFeedService alloc] init];
    });
    return svc;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _server = [[BrowserScraperFeedHTTPServer alloc] init];
        _workQueue = dispatch_queue_create("meo.scraper.feed.service", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
        _pendingJobs = [NSMutableArray array];
        __weak typeof(self) weakSelf = self;
        _server.requestHandler = ^(NSString *method, NSString *path,
                                   NSDictionary<NSString *, NSString *> *headers,
                                   NSData *body,
                                   BrowserScraperFeedHTTPRespondBlock respond) {
            [weakSelf handleMethod:method path:path headers:headers body:body respond:respond];
        };
    }
    return self;
}

- (void)notify {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:BrowserScraperFeedServiceStateDidChangeNotification
                          object:self];
    });
}

- (NSString *)baseURLString {
    NSInteger port = self.listeningPort > 0
        ? self.listeningPort
        : BrowserScraperFeedPreferences.sharedPreferences.port;
    return [NSString stringWithFormat:@"http://127.0.0.1:%ld", (long)port];
}

- (NSString *)feedURLStringForRecipeID:(NSString *)recipeID {
    NSString *rid = recipeID ?: @"";
    return [NSString stringWithFormat:@"%@/scraper/feeds/%@.xml", [self baseURLString], rid];
}

- (BOOL)startServer:(NSError **)error {
    BrowserScraperFeedPreferences *prefs = BrowserScraperFeedPreferences.sharedPreferences;
    NSError *local = nil;
    BOOL ok = [self.server startOnPort:prefs.port error:&local];
    if (!ok) {
        if (error) {
            *error = local;
        }
        return NO;
    }
    prefs.enabled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.listening = self.server.isRunning;
        self.listeningPort = self.server.listeningPort > 0 ? self.server.listeningPort : prefs.port;
        [self notify];
    });
    self.listening = YES;
    self.listeningPort = prefs.port;
    [self notify];
    return YES;
}

- (void)stopServer {
    [self.server stop];
    self.listening = NO;
    self.listeningPort = 0;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.workQueue, ^{
        [weakSelf.cache removeAllObjects];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.activeSession) {
            [self.activeSession.engine cancel];
            [self.activeSession finishWithRows:nil
                                         error:[NSError errorWithDomain:@"BrowserScraperFeed"
                                                                   code:503
                                                               userInfo:@{NSLocalizedDescriptionKey: @"服务已停止"}]];
            self.activeSession = nil;
        }
        [self.pendingJobs removeAllObjects];
        self.draining = NO;
    });
    [self notify];
}

- (NSString *)normalizedPath:(NSString *)path {
    NSString *p = path ?: @"/";
    NSRange q = [p rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        p = [p substringToIndex:q.location];
    }
    if (p.length == 0) {
        p = @"/";
    }
    return p;
}

- (void)handleMethod:(NSString *)method
                path:(NSString *)path
             headers:(NSDictionary<NSString *, NSString *> *)headers
                body:(NSData *)body
             respond:(BrowserScraperFeedHTTPRespondBlock)respond {
    (void)headers;
    (void)body;
    NSString *norm = [self normalizedPath:path];
    if (![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]) {
        respond(405, @"text/plain; charset=utf-8", [@"method not allowed" dataUsingEncoding:NSUTF8StringEncoding]);
        return;
    }
    if ([norm isEqualToString:@"/health"] || [norm isEqualToString:@"/"]) {
        NSData *json = [@"{\"ok\":true,\"service\":\"scraper-feed\"}" dataUsingEncoding:NSUTF8StringEncoding];
        respond(200, @"application/json; charset=utf-8", json);
        return;
    }

    NSString *prefix = @"/scraper/feeds/";
    NSString *suffix = @".xml";
    if ([norm hasPrefix:prefix] && [norm hasSuffix:suffix] && norm.length > prefix.length + suffix.length) {
        NSString *recipeID = [norm substringWithRange:NSMakeRange(prefix.length,
                                                                  norm.length - prefix.length - suffix.length)];
        recipeID = [recipeID stringByRemovingPercentEncoding] ?: recipeID;
        if (recipeID.length == 0 || [recipeID containsString:@"/"]) {
            respond(404, @"text/plain; charset=utf-8", [@"not found" dataUsingEncoding:NSUTF8StringEncoding]);
            return;
        }
        [self serveFeedForRecipeID:recipeID respond:respond];
        return;
    }

    respond(404, @"text/plain; charset=utf-8", [@"not found" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)serveFeedForRecipeID:(NSString *)recipeID respond:(BrowserScraperFeedHTTPRespondBlock)respond {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.workQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            respond(503, @"text/plain; charset=utf-8", [@"unavailable" dataUsingEncoding:NSUTF8StringEncoding]);
            return;
        }
        BrowserScraperFeedCacheEntry *hit = strongSelf.cache[recipeID];
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (hit && hit.expiresAt > now && hit.body.length > 0 && hit.itemCount > 0) {
            NSLog(@"[ScraperFeed] cache hit %@ (%ld items)", recipeID, (long)hit.itemCount);
            respond(200, @"application/rss+xml; charset=utf-8", hit.body);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf enqueueScrapeRecipeID:recipeID
                                  completion:^(NSData *rss, NSInteger itemCount, NSError *error) {
                if (error || rss.length == 0) {
                    NSInteger code = error.code == 404 ? 404 : (error.code == 504 ? 504 : 500);
                    NSString *msg = error.localizedDescription ?: @"scrape failed";
                    respond(code, @"text/plain; charset=utf-8", [msg dataUsingEncoding:NSUTF8StringEncoding]);
                    return;
                }
                if (itemCount > 0) {
                    dispatch_async(strongSelf.workQueue, ^{
                        BrowserScraperFeedCacheEntry *entry = [[BrowserScraperFeedCacheEntry alloc] init];
                        entry.body = rss;
                        entry.itemCount = itemCount;
                        entry.expiresAt = [NSDate date].timeIntervalSince1970 + kFeedCacheTTL;
                        strongSelf.cache[recipeID] = entry;
                        NSLog(@"[ScraperFeed] cache store %@ (%ld items)", recipeID, (long)itemCount);
                    });
                } else {
                    NSLog(@"[ScraperFeed] skip cache empty feed %@", recipeID);
                }
                respond(200, @"application/rss+xml; charset=utf-8", rss);
            }];
        });
    });
}

- (void)enqueueScrapeRecipeID:(NSString *)recipeID
                   completion:(void (^)(NSData *_Nullable rss, NSInteger itemCount, NSError *_Nullable error))completion {
    NSAssert([NSThread isMainThread], @"enqueue must be main");
    __weak typeof(self) weakSelf = self;
    dispatch_block_t job = ^{
        [weakSelf runScrapeRecipeID:recipeID completion:^(NSData *rss, NSInteger itemCount, NSError *error) {
            if (completion) {
                completion(rss, itemCount, error);
            }
            [weakSelf finishCurrentJobAndDrain];
        }];
    };
    [self.pendingJobs addObject:[job copy]];
    [self drainQueueIfNeeded];
}

- (void)drainQueueIfNeeded {
    NSAssert([NSThread isMainThread], @"drain must be main");
    if (self.draining || self.pendingJobs.count == 0) {
        return;
    }
    self.draining = YES;
    dispatch_block_t job = self.pendingJobs.firstObject;
    [self.pendingJobs removeObjectAtIndex:0];
    job();
}

- (void)finishCurrentJobAndDrain {
    NSAssert([NSThread isMainThread], @"finish must be main");
    self.activeSession = nil;
    self.draining = NO;
    [self drainQueueIfNeeded];
}

/// 优先复用已打开且匹配策略的标签页（与预览同源），避免离屏重载 SPA 抽空。
- (nullable WKWebView *)liveWebViewMatchingRecipe:(BrowserScraperRecipe *)recipe {
    WKWebView *fallback = nil;
    for (NSWindow *window in NSApp.windows) {
        id wc = window.windowController;
        if (![wc isKindOfClass:[BrowserWindowController class]]) {
            continue;
        }
        BrowserWindowController *browser = (BrowserWindowController *)wc;
        for (BrowserTab *tab in browser.tabController.tabs) {
            if (tab.isNewTabPage || !tab.webView) {
                continue;
            }
            NSURL *url = [tab currentOrRestorableURL] ?: tab.webView.URL;
            if (!url || [url.host isEqualToString:@"127.0.0.1"] || [url.host isEqualToString:@"localhost"]) {
                continue;
            }
            BOOL match = [recipe.match matchesURL:url];
            if (!match && recipe.startURL.length > 0) {
                NSURL *start = [NSURL URLWithString:recipe.startURL];
                if (start.host.length && [url.host.lowercaseString isEqualToString:start.host.lowercaseString]) {
                    match = YES;
                }
            }
            if (!match) {
                continue;
            }
            if (tab == browser.tabController.selectedTab) {
                return tab.webView;
            }
            if (!fallback) {
                fallback = tab.webView;
            }
        }
    }
    return fallback;
}

- (NSArray<NSDictionary *> *)latestSpillRowsForRecipeID:(NSString *)recipeID {
    NSString *root = [BrowserScraperRecipeStore runsRootDirectory];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSArray *sorted = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *pa = [root stringByAppendingPathComponent:a];
        NSString *pb = [root stringByAppendingPathComponent:b];
        NSDictionary *aa = [[NSFileManager defaultManager] attributesOfItemAtPath:pa error:nil];
        NSDictionary *ba = [[NSFileManager defaultManager] attributesOfItemAtPath:pb error:nil];
        return [ba[NSFileModificationDate] compare:aa[NSFileModificationDate]];
    }];
    for (NSString *name in sorted) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSString *dir = [root stringByAppendingPathComponent:name];
        NSString *metaPath = [dir stringByAppendingPathComponent:@"meta.json"];
        NSData *metaData = [NSData dataWithContentsOfFile:metaPath];
        if (!metaData) {
            continue;
        }
        id meta = [NSJSONSerialization JSONObjectWithData:metaData options:0 error:nil];
        if (![meta isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *rid = [meta[@"recipeId"] isKindOfClass:[NSString class]] ? meta[@"recipeId"] : @"";
        if (![rid isEqualToString:recipeID]) {
            continue;
        }
        NSString *status = [meta[@"status"] isKindOfClass:[NSString class]] ? meta[@"status"] : @"";
        if (status.length && ![status isEqualToString:@"ok"] && ![status isEqualToString:@"running"]) {
            // 仍尝试读取 spill：试运行 / feed 也写 ndjson
        }
        NSString *ndjson = [dir stringByAppendingPathComponent:@"rows.ndjson"];
        NSArray *rows = [BrowserScraperExcelWriter loadRowsFromNDJSON:ndjson error:nil];
        if (rows.count > 0) {
            NSLog(@"[ScraperFeed] fallback spill %@ (%lu rows from %@)", recipeID, (unsigned long)rows.count, name);
            return rows;
        }
    }
    return @[];
}

- (void)runScrapeRecipeID:(NSString *)recipeID
               completion:(void (^)(NSData *_Nullable rss, NSInteger itemCount, NSError *_Nullable error))completion {
    BrowserScraperRecipe *recipe = [[BrowserScraperRecipeStore sharedStore] recipeWithID:recipeID];
    if (!recipe) {
        completion(nil, 0, [NSError errorWithDomain:@"BrowserScraperFeed"
                                               code:404
                                           userInfo:@{NSLocalizedDescriptionKey: @"recipe not found"}]);
        return;
    }

    WKWebView *live = [self liveWebViewMatchingRecipe:recipe];
    if (!live && recipe.startURL.length == 0) {
        completion(nil, 0, [NSError errorWithDomain:@"BrowserScraperFeed"
                                               code:400
                                           userInfo:@{NSLocalizedDescriptionKey: @"recipe missing startURL，且无已打开的匹配标签页"}]);
        return;
    }

    BrowserScraperFeedScrapeSession *session = [[BrowserScraperFeedScrapeSession alloc] init];
    session.recipe = recipe;
    session.engine = [[BrowserScraperEngine alloc] init];
    session.engine.delegate = session;
    self.activeSession = session;

    __weak BrowserScraperFeedScrapeSession *weakSession = session;
    __block BOOL responded = NO;
    void (^finishOnce)(NSData *, NSInteger, NSError *) = ^(NSData *rss, NSInteger itemCount, NSError *error) {
        if (responded) {
            return;
        }
        responded = YES;
        completion(rss, itemCount, error);
    };

    session.completion = ^(NSArray<NSDictionary *> *rows, NSError *error) {
        NSArray<NSDictionary *> *finalRows = rows ?: @[];
        if (error) {
            // 超时/失败时尽量用 spill 兜底，避免阅读器完全空白。
            NSArray *spill = [self latestSpillRowsForRecipeID:recipeID];
            if (spill.count > 0) {
                NSData *rss = [BrowserScraperRSSWriter RSS2DataFromRows:spill recipe:recipe];
                finishOnce(rss, (NSInteger)spill.count, nil);
                return;
            }
            finishOnce(nil, 0, error);
            return;
        }
        if (finalRows.count == 0) {
            NSArray *spill = [self latestSpillRowsForRecipeID:recipeID];
            if (spill.count > 0) {
                finalRows = spill;
            }
        }
        NSData *rss = [BrowserScraperRSSWriter RSS2DataFromRows:finalRows recipe:recipe];
        finishOnce(rss, (NSInteger)finalRows.count, nil);
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFeedScrapeTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong BrowserScraperFeedScrapeSession *strongSession = weakSession;
        if (!strongSession || strongSession.finished) {
            return;
        }
        [strongSession.engine cancel];
        NSArray *partial = strongSession.engine.previewRows ?: @[];
        if (partial.count > 0) {
            [strongSession finishWithRows:partial error:nil];
            return;
        }
        [strongSession finishWithRows:nil
                                error:[NSError errorWithDomain:@"BrowserScraperFeed"
                                                          code:504
                                                      userInfo:@{NSLocalizedDescriptionKey: @"scrape timeout"}]];
    });

    if (live) {
        NSLog(@"[ScraperFeed] use live tab for %@", recipeID);
        [session startOnExistingWebView:live];
    } else {
        NSLog(@"[ScraperFeed] offscreen load for %@", recipeID);
        [session beginOffscreenLoad];
    }
}

@end
