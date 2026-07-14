#import "BrowserFaviconService.h"
#import "BrowserFaviconCache.h"
#import "BrowserFaviconHTMLParser.h"
#import "BrowserFaviconUtil.h"

NSErrorDomain const BrowserFaviconErrorDomain = @"BrowserFaviconErrorDomain";
NSNotificationName const BrowserFaviconDidUpdateNotification = @"BrowserFaviconDidUpdateNotification";
NSString * const BrowserFaviconHostUserInfoKey = @"host";

static const NSTimeInterval kChannelTimeout = 8.0;
static const NSUInteger kMaxIconBytes = 512 * 1024;
static const NSUInteger kMaxHTMLBytes = 64 * 1024;
static const NSUInteger kMaxConcurrentFetches = 2;
static const NSTimeInterval kNegativeCacheTTL = 24.0 * 60.0 * 60.0;
/// 低于此像素边长视为「偏糊」，若还有更高优先级候选则继续尝试。
static const NSUInteger kPreferredMinPixelEdge = 64;

typedef void (^BrowserFaviconFetchCompletion)(NSURL * _Nullable iconURL,
                                              NSImage * _Nullable image,
                                              NSError * _Nullable error);

@interface BrowserFaviconFetchJob : NSObject
@property (nonatomic, copy) NSString *pageURLString;
@property (nonatomic, copy, nullable) NSString *preferredIconURL;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) NSURL *pageURL;
@property (nonatomic, assign) BrowserFaviconFetchReason reason;
@property (nonatomic, strong) NSMutableArray<BrowserFaviconFetchCompletion> *completions;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation BrowserFaviconFetchJob
@end

@interface BrowserFaviconService () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserFaviconFetchJob *> *jobsByHost;
@property (nonatomic, strong) NSMutableArray<BrowserFaviconFetchJob *> *waitingJobs;
@property (nonatomic, strong) NSMutableSet<NSString *> *runningHosts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *negativeFailures;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableData *> *boundedBuffers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *boundedMaxBytes;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable)> *boundedCompletions;
@end

@implementation BrowserFaviconService

+ (instancetype)sharedService {
    static BrowserFaviconService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[BrowserFaviconService alloc] initPrivate];
    });
    return service;
}

- (instancetype)init {
    return [self initPrivate];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.meobrowser.favicon.service", DISPATCH_QUEUE_SERIAL);
        _jobsByHost = [NSMutableDictionary dictionary];
        _waitingJobs = [NSMutableArray array];
        _runningHosts = [NSMutableSet set];
        _boundedBuffers = [NSMutableDictionary dictionary];
        _boundedMaxBytes = [NSMutableDictionary dictionary];
        _boundedCompletions = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = kChannelTimeout;
        config.timeoutIntervalForResource = kChannelTimeout;
        config.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:config
                                                 delegate:self
                                            delegateQueue:nil];
        [self loadNegativeFailures];
    }
    return self;
}

#pragma mark - Paths / negative cache

- (NSURL *)failuresFileURL {
    return [[BrowserFaviconCache cacheDirectoryURL] URLByAppendingPathComponent:@"failures.plist"];
}

- (void)loadNegativeFailures {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:[self failuresFileURL]];
    if ([plist isKindOfClass:[NSDictionary class]]) {
        self.negativeFailures = [plist mutableCopy];
    } else {
        self.negativeFailures = [NSMutableDictionary dictionary];
    }
}

- (void)persistNegativeFailures {
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:[BrowserFaviconCache cacheDirectoryURL]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&error];
    [self.negativeFailures writeToURL:[self failuresFileURL] atomically:YES];
}

- (BOOL)isNegativeCachedForHost:(NSString *)host {
    NSNumber *failedAt = self.negativeFailures[host];
    if (failedAt == nil) {
        return NO;
    }
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - failedAt.doubleValue;
    if (age > kNegativeCacheTTL) {
        [self.negativeFailures removeObjectForKey:host];
        [self persistNegativeFailures];
        return NO;
    }
    return YES;
}

- (void)recordNegativeFailureForHost:(NSString *)host {
    self.negativeFailures[host] = @([[NSDate date] timeIntervalSince1970]);
    [self persistNegativeFailures];
}

- (void)clearNegativeFailureForHost:(NSString *)host {
    if (self.negativeFailures[host] == nil) {
        return;
    }
    [self.negativeFailures removeObjectForKey:host];
    [self persistNegativeFailures];
}

#pragma mark - Public

- (nullable NSImage *)cachedImageForHost:(NSString *)host {
    return [[BrowserFaviconCache sharedCache] imageForHost:host];
}

- (void)imageForPageURLString:(NSString *)pageURLString
              preferredIconURL:(nullable NSString *)iconURLString
                   triggerFetch:(BOOL)triggerFetch
                     completion:(void (^)(NSImage * _Nullable image))completion {
    if (!completion) {
        return;
    }
    NSString *host = BrowserFaviconHostFromURLString(pageURLString);
    if (host.length > 0) {
        NSImage *cached = [[BrowserFaviconCache sharedCache] imageForHost:host];
        if (cached != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached);
            });
            return;
        }
    }

    if (triggerFetch) {
        [self fetchAndCacheForPageURLString:pageURLString
                            preferredIconURL:iconURLString
                                      reason:BrowserFaviconFetchReasonSilent
                                  completion:^(NSURL *iconURL, NSImage *image, NSError *error) {
            (void)iconURL;
            (void)error;
            completion(image);
        }];
        return;
    }

    if (iconURLString.length > 0) {
        __weak typeof(self) weakSelf = self;
        [self downloadImageFromURLString:iconURLString completion:^(NSImage *image, NSURL *sourceURL, NSError *error) {
            (void)error;
            if (image != nil && host.length > 0) {
                [[BrowserFaviconCache sharedCache] storeImage:image
                                                      forHost:host
                                                    sourceURL:sourceURL.absoluteString
                                                      channel:@"manual"];
                [weakSelf postDidUpdateForHost:host];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(image);
            });
        }];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil);
    });
}

- (void)fetchAndCacheForPageURLString:(NSString *)pageURLString
                      preferredIconURL:(nullable NSString *)preferredIconURL
                                reason:(BrowserFaviconFetchReason)reason
                            completion:(void (^)(NSURL * _Nullable, NSImage * _Nullable, NSError * _Nullable))completion {
    NSString *host = BrowserFaviconHostFromURLString(pageURLString);
    NSURL *pageURL = [NSURL URLWithString:pageURLString];
    if (host.length == 0 || pageURL == nil) {
        NSError *error = [NSError errorWithDomain:BrowserFaviconErrorDomain
                                             code:BrowserFaviconErrorInvalidURL
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的网址"}];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil, error);
            });
        }
        return;
    }

    BrowserFaviconFetchCompletion wrapped = ^(NSURL *iconURL, NSImage *image, NSError *error) {
        if (completion) {
            completion(iconURL, image, error);
        }
    };

    dispatch_async(self.stateQueue, ^{
        if (reason == BrowserFaviconFetchReasonSilent && [self isNegativeCachedForHost:host]) {
            NSError *error = [NSError errorWithDomain:BrowserFaviconErrorDomain
                                                 code:BrowserFaviconErrorNegativeCached
                                             userInfo:@{NSLocalizedDescriptionKey: @"近期获取失败，稍后再试"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                wrapped(nil, nil, error);
            });
            return;
        }

        BrowserFaviconFetchJob *existing = self.jobsByHost[host];
        if (existing != nil) {
            if (preferredIconURL.length > 0 && existing.preferredIconURL.length == 0) {
                existing.preferredIconURL = preferredIconURL;
            }
            if (reason == BrowserFaviconFetchReasonUserAction) {
                existing.reason = BrowserFaviconFetchReasonUserAction;
            }
            [existing.completions addObject:[wrapped copy]];
            return;
        }

        BrowserFaviconFetchJob *job = [[BrowserFaviconFetchJob alloc] init];
        job.pageURLString = pageURLString;
        job.preferredIconURL = preferredIconURL;
        job.host = host;
        job.pageURL = pageURL;
        job.reason = reason;
        job.completions = [NSMutableArray arrayWithObject:[wrapped copy]];
        self.jobsByHost[host] = job;

        if (self.runningHosts.count >= kMaxConcurrentFetches) {
            [self.waitingJobs addObject:job];
            return;
        }
        [self startJobLocked:job];
    });
}

- (void)cancelFetchForHost:(NSString *)host {
    NSString *key = host.lowercaseString;
    if (key.length == 0) {
        return;
    }
    dispatch_async(self.stateQueue, ^{
        BrowserFaviconFetchJob *job = self.jobsByHost[key];
        if (job == nil) {
            return;
        }
        job.cancelled = YES;
        if (![self.runningHosts containsObject:key]) {
            [self.waitingJobs removeObject:job];
            [self finishJobLocked:job iconURL:nil image:nil error:[self cancelledError]];
        }
    });
}

- (void)cancelAll {
    dispatch_async(self.stateQueue, ^{
        NSArray<BrowserFaviconFetchJob *> *jobs = self.jobsByHost.allValues;
        for (BrowserFaviconFetchJob *job in jobs) {
            job.cancelled = YES;
        }
        [self.waitingJobs removeAllObjects];
        NSError *error = [self cancelledError];
        for (BrowserFaviconFetchJob *job in jobs) {
            if (![self.runningHosts containsObject:job.host]) {
                [self finishJobLocked:job iconURL:nil image:nil error:error];
            }
        }
        [self.session invalidateAndCancel];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = kChannelTimeout;
        config.timeoutIntervalForResource = kChannelTimeout;
        self.session = [NSURLSession sessionWithConfiguration:config
                                                     delegate:self
                                                delegateQueue:nil];
        self.boundedBuffers = [NSMutableDictionary dictionary];
        self.boundedMaxBytes = [NSMutableDictionary dictionary];
        self.boundedCompletions = [NSMutableDictionary dictionary];
        [self.runningHosts removeAllObjects];
    });
}

#pragma mark - Job lifecycle

- (void)startJobLocked:(BrowserFaviconFetchJob *)job {
    [self.runningHosts addObject:job.host];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [weakSelf runWaterfallForJob:job];
    });
}

- (void)runWaterfallForJob:(BrowserFaviconFetchJob *)job {
    if (job.cancelled) {
        [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
        return;
    }

    // Channel 0 — preferred
    if (job.preferredIconURL.length > 0) {
        __block NSImage *image = nil;
        __block NSURL *sourceURL = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self downloadImageFromURLString:job.preferredIconURL completion:^(NSImage *img, NSURL *url, NSError *error) {
            (void)error;
            image = img;
            sourceURL = url;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (job.cancelled) {
            [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
            return;
        }
        if (image != nil) {
            [self succeedJob:job image:image sourceURL:sourceURL channel:@"manual"];
            return;
        }
    }

    // Channel 1 — disk（Silent 命中清晰缓存可秒开；UserAction「自动获取」跳过，强制重拉）
    if (job.reason != BrowserFaviconFetchReasonUserAction) {
        NSImage *diskImage = [[BrowserFaviconCache sharedCache] imageForHost:job.host];
        if (diskImage != nil && BrowserFaviconMaxPixelEdge(diskImage) >= kPreferredMinPixelEdge) {
            NSString *source = [[BrowserFaviconCache sharedCache] sourceURLForHost:job.host];
            NSURL *sourceURL = source.length > 0 ? [NSURL URLWithString:source] : nil;
            [self succeedJob:job image:diskImage sourceURL:sourceURL channel:@"disk" skipStore:YES];
            return;
        }
    }

    if (job.cancelled) {
        [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
        return;
    }

    // Channel 2 — Google s2（优先：通常最清晰；不通再走其它渠）
    if (!job.cancelled) {
        NSString *urlString =
            [NSString stringWithFormat:@"https://www.google.com/s2/favicons?domain=%@&sz=64",
                                       [self percentEncodedHost:job.host]];
        if ([self tryThirdPartyURLString:urlString channel:@"google" job:job allowSmall:YES]) {
            return;
        }
    }

    // Channel 3 — 站点候选（HTML / apple-touch / favicon.ico）
    if ([self trySiteCandidatesForJob:job]) {
        return;
    }

    // Channel 4+ — 其它第三方兜底
    if (!job.cancelled) {
        NSString *urlString =
            [NSString stringWithFormat:@"https://cn.cravatar.com/favicon/api/index.php?url=%@",
                                       [self percentEncodedHost:job.host]];
        if ([self tryThirdPartyURLString:urlString channel:@"cravatar" job:job allowSmall:YES]) {
            return;
        }
    }

    if (!job.cancelled) {
        NSString *urlString =
            [NSString stringWithFormat:@"https://icons.duckduckgo.com/ip3/%@.ico", job.host];
        if ([self tryThirdPartyURLString:urlString channel:@"duckduckgo" job:job allowSmall:YES]) {
            return;
        }
    }

    if (job.cancelled) {
        [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
        return;
    }

    dispatch_async(self.stateQueue, ^{
        [self recordNegativeFailureForHost:job.host];
    });
    NSError *error = [NSError errorWithDomain:BrowserFaviconErrorDomain
                                         code:BrowserFaviconErrorAllChannelsFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"未能获取图标"}];
    [self completeJob:job iconURL:nil image:nil error:error];
}

- (BOOL)trySiteCandidatesForJob:(BrowserFaviconFetchJob *)job {
    NSArray<NSURL *> *candidates = [self orderedSiteCandidateURLsForJob:job];
    if (candidates.count == 0) {
        return NO;
    }

    NSImage *bestImage = nil;
    NSURL *bestURL = nil;
    NSUInteger bestEdge = 0;

    for (NSUInteger i = 0; i < candidates.count; i++) {
        if (job.cancelled) {
            [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
            return YES;
        }
        NSURL *candidate = candidates[i];
        __block NSImage *image = nil;
        __block NSURL *sourceURL = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self downloadImageFromURL:candidate maxBytes:kMaxIconBytes completion:^(NSImage *img, NSURL *url, NSError *error) {
            (void)error;
            image = img;
            sourceURL = url;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (image == nil) {
            continue;
        }

        NSUInteger edge = BrowserFaviconMaxPixelEdge(image);
        BOOL isLast = (i + 1 == candidates.count);
        if (edge >= kPreferredMinPixelEdge) {
            [self succeedJob:job image:image sourceURL:sourceURL channel:@"site"];
            return YES;
        }
        // 记录目前最好的小图；若后面还有候选则继续找更大的。
        if (edge > bestEdge) {
            bestEdge = edge;
            bestImage = image;
            bestURL = sourceURL;
        }
        if (isLast && bestImage != nil) {
            [self succeedJob:job image:bestImage sourceURL:bestURL channel:@"site"];
            return YES;
        }
    }

    if (bestImage != nil) {
        [self succeedJob:job image:bestImage sourceURL:bestURL channel:@"site"];
        return YES;
    }
    return NO;
}

- (NSArray<NSURL *> *)orderedSiteCandidateURLsForJob:(BrowserFaviconFetchJob *)job {
    NSMutableArray<NSURL *> *ordered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^appendURL)(NSURL *) = ^(NSURL *url) {
        if (url == nil || url.absoluteString.length == 0) {
            return;
        }
        NSString *key = url.absoluteString;
        if ([seen containsObject:key]) {
            return;
        }
        [seen addObject:key];
        [ordered addObject:url];
    };

    // 1) HTML <link> 已按清晰度降序
    for (NSURL *url in [self iconCandidatesFromHTMLForJob:job]) {
        appendURL(url);
    }

    // 2) 约定高清路径（先于 favicon.ico）
    NSURL *origin = [self originURLFromPageURL:job.pageURL];
    NSArray<NSString *> *wellKnownPaths = @[
        @"/apple-touch-icon.png",
        @"/apple-touch-icon-precomposed.png",
        @"/apple-touch-icon-180x180.png",
        @"/apple-touch-icon-152x152.png",
        @"/favicon-192x192.png",
        @"/favicon-32x32.png",
        @"/favicon.ico",
    ];
    for (NSString *path in wellKnownPaths) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:origin resolvingAgainstBaseURL:NO];
        components.path = path;
        appendURL(components.URL);
    }

    return [ordered copy];
}

- (BOOL)tryThirdPartyURLString:(NSString *)urlString
                       channel:(NSString *)channel
                           job:(BrowserFaviconFetchJob *)job
                     allowSmall:(BOOL)allowSmall {
    __block NSImage *image = nil;
    __block NSURL *sourceURL = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self downloadImageFromURLString:urlString completion:^(NSImage *img, NSURL *url, NSError *error) {
        (void)error;
        image = img;
        sourceURL = url;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (image == nil) {
        return NO;
    }
    NSUInteger edge = BrowserFaviconMaxPixelEdge(image);
    if (!allowSmall && edge < kPreferredMinPixelEdge) {
        return NO;
    }
    [self succeedJob:job image:image sourceURL:sourceURL channel:channel];
    return YES;
}

- (NSArray<NSURL *> *)iconCandidatesFromHTMLForJob:(BrowserFaviconFetchJob *)job {
    NSURL *pageURL = job.pageURL;
    NSURL *origin = [self originURLFromPageURL:pageURL];
    NSArray<NSURL *> *pagesToTry = @[ pageURL ];
    if (origin != nil && ![origin.absoluteString isEqualToString:pageURL.absoluteString]) {
        pagesToTry = @[ pageURL, origin ];
    }

    for (NSURL *htmlURL in pagesToTry) {
        if (job.cancelled) {
            break;
        }
        __block NSData *htmlData = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self downloadDataFromURL:htmlURL
                         maxBytes:kMaxHTMLBytes
                       completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
            (void)response;
            (void)error;
            htmlData = data;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (htmlData.length == 0) {
            continue;
        }
        NSArray<NSURL *> *urls = [BrowserFaviconHTMLParser iconURLsFromHTMLData:htmlData pageURL:htmlURL];
        if (urls.count > 0) {
            return urls;
        }
    }
    return @[];
}

- (void)succeedJob:(BrowserFaviconFetchJob *)job
             image:(NSImage *)image
         sourceURL:(NSURL *)sourceURL
           channel:(NSString *)channel {
    [self succeedJob:job image:image sourceURL:sourceURL channel:channel skipStore:NO];
}

- (void)succeedJob:(BrowserFaviconFetchJob *)job
             image:(NSImage *)image
         sourceURL:(NSURL *)sourceURL
           channel:(NSString *)channel
         skipStore:(BOOL)skipStore {
    if (job.cancelled) {
        [self completeJob:job iconURL:nil image:nil error:[self cancelledError]];
        return;
    }
    if (!skipStore) {
        [[BrowserFaviconCache sharedCache] storeImage:image
                                              forHost:job.host
                                            sourceURL:sourceURL.absoluteString
                                              channel:channel];
    }
    dispatch_async(self.stateQueue, ^{
        [self clearNegativeFailureForHost:job.host];
    });
    [self postDidUpdateForHost:job.host];
    [self completeJob:job iconURL:sourceURL image:image error:nil];
}

- (void)completeJob:(BrowserFaviconFetchJob *)job
            iconURL:(NSURL *)iconURL
              image:(NSImage *)image
              error:(NSError *)error {
    dispatch_async(self.stateQueue, ^{
        [self finishJobLocked:job iconURL:iconURL image:image error:error];
    });
}

- (void)finishJobLocked:(BrowserFaviconFetchJob *)job
                iconURL:(NSURL *)iconURL
                  image:(NSImage *)image
                  error:(NSError *)error {
    [self.runningHosts removeObject:job.host];
    [self.jobsByHost removeObjectForKey:job.host];
    [self.waitingJobs removeObject:job];

    NSArray<BrowserFaviconFetchCompletion> *completions = [job.completions copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (BrowserFaviconFetchCompletion block in completions) {
            block(iconURL, image, error);
        }
    });

    while (self.runningHosts.count < kMaxConcurrentFetches && self.waitingJobs.count > 0) {
        BrowserFaviconFetchJob *next = self.waitingJobs.firstObject;
        [self.waitingJobs removeObjectAtIndex:0];
        if (next.cancelled) {
            [self finishJobLocked:next iconURL:nil image:nil error:[self cancelledError]];
            continue;
        }
        if (self.jobsByHost[next.host] == nil) {
            continue;
        }
        [self startJobLocked:next];
    }
}

- (void)postDidUpdateForHost:(NSString *)host {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BrowserFaviconDidUpdateNotification
                                                            object:host
                                                          userInfo:@{BrowserFaviconHostUserInfoKey: host ?: @""}];
    });
}

- (NSError *)cancelledError {
    return [NSError errorWithDomain:BrowserFaviconErrorDomain
                               code:BrowserFaviconErrorCancelled
                           userInfo:@{NSLocalizedDescriptionKey: @"已取消"}];
}

#pragma mark - URL helpers

- (NSURL *)originURLFromPageURL:(NSURL *)pageURL {
    NSURLComponents *components = [NSURLComponents componentsWithURL:pageURL resolvingAgainstBaseURL:NO];
    if (components.scheme.length == 0) {
        components.scheme = @"https";
    }
    components.user = nil;
    components.password = nil;
    components.path = @"";
    components.query = nil;
    components.fragment = nil;
    NSURL *url = components.URL;
    if (url == nil) {
        return pageURL;
    }
    // Ensure trailing path root for appending.
    NSURLComponents *rooted = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    rooted.path = @"/";
    return rooted.URL ?: url;
}

- (NSString *)percentEncodedHost:(NSString *)host {
    return [host stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: host;
}

#pragma mark - Downloads

- (void)downloadImageFromURLString:(NSString *)urlString
                        completion:(void (^)(NSImage * _Nullable, NSURL * _Nullable, NSError * _Nullable))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (completion) {
            completion(nil, nil, [NSError errorWithDomain:BrowserFaviconErrorDomain
                                                     code:BrowserFaviconErrorInvalidURL
                                                 userInfo:nil]);
        }
        return;
    }
    [self downloadImageFromURL:url maxBytes:kMaxIconBytes completion:completion];
}

/// 内部下载回调在会话队列触发，避免依赖主线程（防止瀑布 semaphore 死锁）。
- (void)downloadImageFromURL:(NSURL *)url
                    maxBytes:(NSUInteger)maxBytes
                  completion:(void (^)(NSImage * _Nullable, NSURL * _Nullable, NSError * _Nullable))completion {
    [self downloadDataFromURL:url
                     maxBytes:maxBytes
                   completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            if (completion) {
                completion(nil, nil, error);
            }
            return;
        }
        if (response != nil && response.statusCode >= 400) {
            if (completion) {
                completion(nil, nil, [NSError errorWithDomain:BrowserFaviconErrorDomain
                                                         code:BrowserFaviconErrorAllChannelsFailed
                                                     userInfo:nil]);
            }
            return;
        }
        NSImage *image = BrowserFaviconImageFromData(data);
        if (image == nil) {
            if (completion) {
                completion(nil, nil, [NSError errorWithDomain:BrowserFaviconErrorDomain
                                                         code:BrowserFaviconErrorDecodeFailed
                                                     userInfo:nil]);
            }
            return;
        }
        if (completion) {
            completion(image, url, nil);
        }
    }];
}

- (void)downloadDataFromURL:(NSURL *)url
                   maxBytes:(NSUInteger)maxBytes
                 completion:(void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable))completion {
    if (url == nil || !completion) {
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (maxBytes > 0 && maxBytes < NSUIntegerMax) {
        NSString *range = [NSString stringWithFormat:@"bytes=0-%lu", (unsigned long)(maxBytes - 1)];
        [request setValue:range forHTTPHeaderField:@"Range"];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.stateQueue, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(nil, nil, [NSError errorWithDomain:BrowserFaviconErrorDomain
                                                     code:BrowserFaviconErrorCancelled
                                                 userInfo:nil]);
            return;
        }
        NSURLSessionDataTask *task = [strongSelf.session dataTaskWithRequest:request];
        NSNumber *key = @(task.taskIdentifier);
        strongSelf.boundedBuffers[key] = [NSMutableData data];
        strongSelf.boundedMaxBytes[key] = @(maxBytes);
        strongSelf.boundedCompletions[key] = [completion copy];
        [task resume];
    });
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    (void)session;
    NSNumber *key = @(dataTask.taskIdentifier);
    dispatch_sync(self.stateQueue, ^{
        NSMutableData *buffer = self.boundedBuffers[key];
        NSUInteger maxBytes = self.boundedMaxBytes[key].unsignedIntegerValue;
        if (buffer == nil) {
            return;
        }
        NSUInteger room = (maxBytes > buffer.length) ? (maxBytes - buffer.length) : 0;
        if (room == 0) {
            [dataTask cancel];
            return;
        }
        if (data.length <= room) {
            [buffer appendData:data];
        } else {
            [buffer appendData:[data subdataWithRange:NSMakeRange(0, room)]];
            [dataTask cancel];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    (void)session;
    NSNumber *key = @(task.taskIdentifier);
    __block NSData *data = nil;
    __block void (^completion)(NSData *, NSHTTPURLResponse *, NSError *) = nil;
    __block NSHTTPURLResponse *response = nil;

    dispatch_sync(self.stateQueue, ^{
        data = [self.boundedBuffers[key] copy];
        completion = self.boundedCompletions[key];
        [self.boundedBuffers removeObjectForKey:key];
        [self.boundedMaxBytes removeObjectForKey:key];
        [self.boundedCompletions removeObjectForKey:key];
        if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
            response = (NSHTTPURLResponse *)task.response;
        }
    });

    if (!completion) {
        return;
    }

    // 主动 cancel（截断）时若已有数据，视为成功。
    if (error != nil && data.length == 0) {
        completion(nil, response, error);
        return;
    }
    if (error != nil && error.code == NSURLErrorCancelled && data.length > 0) {
        completion(data, response, nil);
        return;
    }
    if (error != nil) {
        completion(nil, response, error);
        return;
    }
    completion(data, response, nil);
}

@end
