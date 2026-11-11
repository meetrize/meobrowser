#import "BrowserScraperFeedService.h"
#import "BrowserScraperFeedHTTPServer.h"
#import "BrowserScraperFeedPreferences.h"
#import "BrowserScraperRSSWriter.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperEngine.h"
#import "BrowserScraperModels.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NSNotificationName const BrowserScraperFeedServiceStateDidChangeNotification =
    @"BrowserScraperFeedServiceStateDidChangeNotification";

static const NSTimeInterval kFeedCacheTTL = 60.0;
static const NSTimeInterval kFeedScrapeTimeout = 90.0;

@interface BrowserScraperFeedCacheEntry : NSObject
@property (nonatomic, strong) NSData *body;
@property (nonatomic, assign) NSTimeInterval expiresAt;
@end

@implementation BrowserScraperFeedCacheEntry
@end

@interface BrowserScraperFeedScrapeSession : NSObject <WKNavigationDelegate, BrowserScraperEngineDelegate>
@property (nonatomic, strong) BrowserScraperRecipe *recipe;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, copy) void (^completion)(NSArray<NSDictionary *> *_Nullable rows, NSError *_Nullable error);
@end

@implementation BrowserScraperFeedScrapeSession

- (void)finishWithRows:(NSArray<NSDictionary *> *)rows error:(NSError *)error {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    void (^completion)(NSArray<NSDictionary *> *, NSError *) = self.completion;
    self.completion = nil;
    WKWebView *wv = self.webView;
    self.webView = nil;
    self.engine.delegate = nil;
    wv.navigationDelegate = nil;
    if (completion) {
        completion(rows, error);
    }
}

- (void)begin {
    NSURL *url = [NSURL URLWithString:self.recipe.startURL];
    if (!url) {
        [self finishWithRows:nil
                       error:[NSError errorWithDomain:@"BrowserScraperFeed"
                                                 code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"startURL 无效"}]];
        return;
    }
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.finished || strongSelf.started) {
            return;
        }
        strongSelf.started = YES;
        [strongSelf.engine startFeedPreviewWithRecipe:strongSelf.recipe webView:strongSelf.webView];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    if (self.started || self.finished) {
        return;
    }
    self.started = YES;
    [self.engine startFeedPreviewWithRecipe:self.recipe webView:self.webView];
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
    // 不改 prefs.enabled：退出时 stop 不应关掉下次启动的自动开启。
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
        if (hit && hit.expiresAt > now && hit.body.length > 0) {
            NSLog(@"[ScraperFeed] cache hit %@", recipeID);
            respond(200, @"application/rss+xml; charset=utf-8", hit.body);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf enqueueScrapeRecipeID:recipeID
                                  completion:^(NSData *rss, NSError *error) {
                if (error || rss.length == 0) {
                    NSInteger code = error.code == 404 ? 404 : (error.code == 504 ? 504 : 500);
                    NSString *msg = error.localizedDescription ?: @"scrape failed";
                    respond(code, @"text/plain; charset=utf-8", [msg dataUsingEncoding:NSUTF8StringEncoding]);
                    return;
                }
                dispatch_async(strongSelf.workQueue, ^{
                    BrowserScraperFeedCacheEntry *entry = [[BrowserScraperFeedCacheEntry alloc] init];
                    entry.body = rss;
                    entry.expiresAt = [NSDate date].timeIntervalSince1970 + kFeedCacheTTL;
                    strongSelf.cache[recipeID] = entry;
                    NSLog(@"[ScraperFeed] cache store %@", recipeID);
                });
                respond(200, @"application/rss+xml; charset=utf-8", rss);
            }];
        });
    });
}

- (void)enqueueScrapeRecipeID:(NSString *)recipeID
                   completion:(void (^)(NSData *_Nullable rss, NSError *_Nullable error))completion {
    NSAssert([NSThread isMainThread], @"enqueue must be main");
    __weak typeof(self) weakSelf = self;
    dispatch_block_t job = ^{
        [weakSelf runScrapeRecipeID:recipeID completion:^(NSData *rss, NSError *error) {
            if (completion) {
                completion(rss, error);
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

- (void)runScrapeRecipeID:(NSString *)recipeID
               completion:(void (^)(NSData *_Nullable rss, NSError *_Nullable error))completion {
    BrowserScraperRecipe *recipe = [[BrowserScraperRecipeStore sharedStore] recipeWithID:recipeID];
    if (!recipe) {
        completion(nil, [NSError errorWithDomain:@"BrowserScraperFeed"
                                            code:404
                                        userInfo:@{NSLocalizedDescriptionKey: @"recipe not found"}]);
        return;
    }
    if (recipe.startURL.length == 0) {
        completion(nil, [NSError errorWithDomain:@"BrowserScraperFeed"
                                            code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"recipe missing startURL"}]);
        return;
    }

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = (recipe.session == BrowserScraperSessionEphemeral)
        ? [WKWebsiteDataStore nonPersistentDataStore]
        : [WKWebsiteDataStore defaultDataStore];

    BrowserScraperFeedScrapeSession *session = [[BrowserScraperFeedScrapeSession alloc] init];
    session.recipe = recipe;
    session.engine = [[BrowserScraperEngine alloc] init];
    session.engine.delegate = session;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 900) configuration:config];
    webView.navigationDelegate = session;
    session.webView = webView;
    self.activeSession = session;

    __weak typeof(self) weakSelf = self;
    __weak BrowserScraperFeedScrapeSession *weakSession = session;
    __block BOOL responded = NO;
    void (^finishOnce)(NSData *, NSError *) = ^(NSData *rss, NSError *error) {
        if (responded) {
            return;
        }
        responded = YES;
        completion(rss, error);
    };

    session.completion = ^(NSArray<NSDictionary *> *rows, NSError *error) {
        (void)weakSelf;
        if (error) {
            finishOnce(nil, error);
            return;
        }
        NSData *rss = [BrowserScraperRSSWriter RSS2DataFromRows:rows ?: @[] recipe:recipe];
        finishOnce(rss, nil);
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFeedScrapeTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong BrowserScraperFeedScrapeSession *strongSession = weakSession;
        if (!strongSession || strongSession.finished) {
            return;
        }
        [strongSession.engine cancel];
        [strongSession finishWithRows:nil
                                error:[NSError errorWithDomain:@"BrowserScraperFeed"
                                                          code:504
                                                      userInfo:@{NSLocalizedDescriptionKey: @"scrape timeout"}]];
    });

    [session begin];
}

@end
