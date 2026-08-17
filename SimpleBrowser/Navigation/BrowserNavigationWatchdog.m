#import "BrowserNavigationWatchdog.h"
#import "BrowserNavigationSession.h"
#import "BrowserNavigationTimeouts.h"

typedef NS_ENUM(NSInteger, BrowserNavigationWatchdogKind) {
    BrowserNavigationWatchdogKindOverall = 1,
    BrowserNavigationWatchdogKindProvisional = 2,
    BrowserNavigationWatchdogKindDocumentGrace = 3,
};

@interface BrowserNavigationWatchdogEntry : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, strong) BrowserNavigationSession *session;
@property (nonatomic, strong, nullable) NSURL *URL;
@property (nonatomic, assign) BrowserNavigationWatchdogKind kind;
@property (nonatomic, assign) NSInteger token;
@property (nonatomic, strong, nullable) dispatch_block_t block;
@end

@implementation BrowserNavigationWatchdogEntry
@end

@interface BrowserNavigationWatchdog ()
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *overallByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *provisionalByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *documentGraceByWebView;
@property (nonatomic, assign) NSInteger nextToken;
@end

@implementation BrowserNavigationWatchdog

- (instancetype)init {
    self = [super init];
    if (self) {
        _overallByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _provisionalByWebView = [NSMapTable weakToStrongObjectsMapTable];
        _documentGraceByWebView = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *)tableForKind:(BrowserNavigationWatchdogKind)kind {
    switch (kind) {
        case BrowserNavigationWatchdogKindOverall:
            return self.overallByWebView;
        case BrowserNavigationWatchdogKindProvisional:
            return self.provisionalByWebView;
        case BrowserNavigationWatchdogKindDocumentGrace:
            return self.documentGraceByWebView;
    }
    return self.overallByWebView;
}

- (void)cancelEntry:(BrowserNavigationWatchdogEntry *)entry
            inTable:(NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *)table {
    if (!entry) {
        return;
    }
    if (entry.block) {
        dispatch_block_cancel(entry.block);
        entry.block = nil;
    }
    WKWebView *webView = entry.webView;
    if (webView) {
        BrowserNavigationWatchdogEntry *current = [table objectForKey:webView];
        if (current == entry) {
            [table removeObjectForKey:webView];
        }
    }
}

- (void)cancelOverallForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserNavigationWatchdogEntry *entry = [self.overallByWebView objectForKey:webView];
    [self cancelEntry:entry inTable:self.overallByWebView];
}

- (void)cancelProvisionalForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserNavigationWatchdogEntry *entry = [self.provisionalByWebView objectForKey:webView];
    [self cancelEntry:entry inTable:self.provisionalByWebView];
}

- (void)cancelDocumentLoadGraceForWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    BrowserNavigationWatchdogEntry *entry = [self.documentGraceByWebView objectForKey:webView];
    [self cancelEntry:entry inTable:self.documentGraceByWebView];
}

- (void)cancelAllForWebView:(WKWebView *)webView {
    [self cancelOverallForWebView:webView];
    [self cancelProvisionalForWebView:webView];
    [self cancelDocumentLoadGraceForWebView:webView];
}

- (void)scheduleKind:(BrowserNavigationWatchdogKind)kind
           forWebView:(WKWebView *)webView
              session:(BrowserNavigationSession *)session
                  URL:(NSURL *)url
             interval:(NSTimeInterval)interval
              handler:(BrowserNavigationWatchdogHandler)handler {
    if (!webView || !session || !handler || interval <= 0) {
        return;
    }

    NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *table = [self tableForKind:kind];
    BrowserNavigationWatchdogEntry *existing = [table objectForKey:webView];
    [self cancelEntry:existing inTable:table];

    BrowserNavigationWatchdogEntry *entry = [[BrowserNavigationWatchdogEntry alloc] init];
    entry.webView = webView;
    entry.session = session;
    entry.URL = url;
    entry.kind = kind;
    entry.token = ++self.nextToken;
    [table setObject:entry forKey:webView];

    NSInteger token = entry.token;
    NSInteger generation = session.generation;
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf || !strongWebView) {
            return;
        }
        NSMapTable<WKWebView *, BrowserNavigationWatchdogEntry *> *currentTable =
            [strongSelf tableForKind:kind];
        BrowserNavigationWatchdogEntry *current = [currentTable objectForKey:strongWebView];
        if (!current || current.token != token) {
            return;
        }
        if (current.session.generation != generation) {
            [strongSelf cancelEntry:current inTable:currentTable];
            return;
        }
        BrowserNavigationSession *firedSession = current.session;
        NSURL *failingURL = current.URL;
        // T2 只取消自身，保留其它表干净；T0/T1 取消全部以免残留。
        if (kind == BrowserNavigationWatchdogKindDocumentGrace) {
            [strongSelf cancelDocumentLoadGraceForWebView:strongWebView];
        } else {
            [strongSelf cancelAllForWebView:strongWebView];
        }
        handler(strongWebView, firedSession, failingURL);
    });
    entry.block = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)startOverallTimeoutForWebView:(WKWebView *)webView
                              session:(BrowserNavigationSession *)session
                                  URL:(NSURL *)url
                              handler:(BrowserNavigationWatchdogHandler)handler {
    [self scheduleKind:BrowserNavigationWatchdogKindOverall
             forWebView:webView
                session:session
                    URL:url
               interval:BrowserNavigationOverallTimeout
                handler:handler];
}

- (void)startProvisionalTimeoutForWebView:(WKWebView *)webView
                                  session:(BrowserNavigationSession *)session
                                      URL:(NSURL *)url
                                  handler:(BrowserNavigationWatchdogHandler)handler {
    [self scheduleKind:BrowserNavigationWatchdogKindProvisional
             forWebView:webView
                session:session
                    URL:url
               interval:BrowserMainFrameNavigationTimeout
                handler:handler];
}

- (void)startDocumentLoadGraceForWebView:(WKWebView *)webView
                                 session:(BrowserNavigationSession *)session
                                     URL:(NSURL *)url
                                interval:(NSTimeInterval)interval
                                 handler:(BrowserNavigationWatchdogHandler)handler {
    [self scheduleKind:BrowserNavigationWatchdogKindDocumentGrace
             forWebView:webView
                session:session
                    URL:url
               interval:interval
                handler:handler];
}

@end
