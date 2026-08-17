#import "BrowserReachabilityProbe.h"
#import <Network/Network.h>
#import <CFNetwork/CFNetwork.h>

static NSString * const kMeoQuickReachabilityProbeKey = @"MeoBrowserQuickReachabilityProbe";
static const NSTimeInterval kProbeBudgetSeconds = 2.0;
static const NSInteger kMaxConcurrentProbes = 4;
static const NSTimeInterval kNegativeCacheTTLSeconds = 8.0 * 60.0;
static const NSTimeInterval kProbeResultMemoTTLSeconds = 5.0;

@interface BrowserReachabilityProbeHandle ()
@property (nonatomic, copy, nullable) void (^cancelBlock)(void);
@property (atomic, assign) BOOL cancelled;
@end

@implementation BrowserReachabilityProbeHandle
- (void)cancel {
    if (self.cancelled) {
        return;
    }
    self.cancelled = YES;
    void (^block)(void) = self.cancelBlock;
    self.cancelBlock = nil;
    if (block) {
        block();
    }
}
@end

@interface BrowserReachabilityProbeMemo : NSObject
@property (nonatomic, assign) BrowserReachabilityProbeResult result;
@property (nonatomic, assign) NSInteger code;
@property (nonatomic, assign) NSTimeInterval expiry;
@end

@implementation BrowserReachabilityProbeMemo
@end

@interface BrowserReachabilityProbe ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_semaphore_t concurrencyGate;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserReachabilityProbeMemo *> *resultMemoByHostKey;
@end

@implementation BrowserReachabilityProbe

+ (instancetype)sharedProbe {
    static BrowserReachabilityProbe *probe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        probe = [[self alloc] init];
    });
    return probe;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.meobrowser.reachability-probe", DISPATCH_QUEUE_SERIAL);
        _concurrencyGate = dispatch_semaphore_create(kMaxConcurrentProbes);
        _resultMemoByHostKey = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (BOOL)isQuickProbeEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kMeoQuickReachabilityProbeKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kMeoQuickReachabilityProbeKey];
}

+ (void)setQuickProbeEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kMeoQuickReachabilityProbeKey];
}

+ (BOOL)isLoopbackHost:(NSString *)host {
    if (host.length == 0) {
        return YES;
    }
    NSString *lower = host.lowercaseString;
    if ([lower isEqualToString:@"localhost"] || [lower isEqualToString:@"127.0.0.1"] || [lower isEqualToString:@"::1"]) {
        return YES;
    }
    return NO;
}

+ (BOOL)systemProxyAppliesToURL:(NSURL *)url {
    if (!url) {
        return NO;
    }
    CFDictionaryRef settings = CFNetworkCopySystemProxySettings();
    if (!settings) {
        return NO;
    }
    CFArrayRef proxies = CFNetworkCopyProxiesForURL((__bridge CFURLRef)url, settings);
    CFRelease(settings);
    if (!proxies) {
        return NO;
    }
    BOOL applies = NO;
    CFIndex count = CFArrayGetCount(proxies);
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef proxy = CFArrayGetValueAtIndex(proxies, i);
        CFStringRef type = CFDictionaryGetValue(proxy, kCFProxyTypeKey);
        if (type && !CFEqual(type, kCFProxyTypeNone)) {
            applies = YES;
            break;
        }
    }
    CFRelease(proxies);
    return applies;
}

+ (BOOL)shouldProbeURL:(NSURL *)url {
    if (![self isQuickProbeEnabled]) {
        return NO;
    }
    if (!url) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    NSString *host = url.host;
    if (host.length == 0 || [self isLoopbackHost:host]) {
        return NO;
    }
    // 系统代理会代理解析/连接；直连探测易误判，宁可不快速失败。
    if ([self systemProxyAppliesToURL:url]) {
        return NO;
    }
    return YES;
}

+ (uint16_t)portForURL:(NSURL *)url {
    if (url.port != nil) {
        return (uint16_t)url.port.unsignedIntegerValue;
    }
    if ([url.scheme.lowercaseString isEqualToString:@"https"]) {
        return 443;
    }
    return 80;
}

- (nullable BrowserReachabilityProbeHandle *)probeURL:(NSURL *)url
                                          completion:(BrowserReachabilityProbeCompletion)completion {
    if (!completion) {
        return nil;
    }
    if (![BrowserReachabilityProbe shouldProbeURL:url]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(BrowserReachabilityProbeResultUnknown, 0);
        });
        return nil;
    }

    NSString *hostKey = [BrowserHostNegativeCache hostKeyForURL:url];
    if (hostKey.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(BrowserReachabilityProbeResultUnknown, 0);
        });
        return nil;
    }

    __block BrowserReachabilityProbeMemo *memo = nil;
    dispatch_sync(self.queue, ^{
        BrowserReachabilityProbeMemo *existing = self.resultMemoByHostKey[hostKey];
        if (existing && existing.expiry > NSDate.date.timeIntervalSince1970) {
            memo = existing;
        }
    });
    if (memo) {
        BrowserReachabilityProbeResult result = memo.result;
        NSInteger code = memo.code;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, code);
        });
        return nil;
    }

    BrowserReachabilityProbeHandle *handle = [[BrowserReachabilityProbeHandle alloc] init];
    NSString *host = url.host;
    uint16_t port = [BrowserReachabilityProbe portForURL:url];
    __weak typeof(self) weakSelf = self;

    dispatch_async(self.queue, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || handle.cancelled) {
            return;
        }

        dispatch_semaphore_wait(strongSelf.concurrencyGate, DISPATCH_TIME_FOREVER);
        if (handle.cancelled) {
            dispatch_semaphore_signal(strongSelf.concurrencyGate);
            return;
        }

        __block nw_connection_t connection = nil;
        __block dispatch_source_t timeoutSource = nil;
        __block BOOL finished = NO;

        void (^finish)(BrowserReachabilityProbeResult, NSInteger) =
            ^(BrowserReachabilityProbeResult result, NSInteger code) {
                if (finished) {
                    return;
                }
                finished = YES;
                if (timeoutSource) {
                    dispatch_source_cancel(timeoutSource);
                    timeoutSource = nil;
                }
                if (connection) {
                    nw_connection_cancel(connection);
                    connection = nil;
                }
                dispatch_semaphore_signal(strongSelf.concurrencyGate);

                if (result != BrowserReachabilityProbeResultUnknown) {
                    BrowserReachabilityProbeMemo *stored = [[BrowserReachabilityProbeMemo alloc] init];
                    stored.result = result;
                    stored.code = code;
                    stored.expiry = NSDate.date.timeIntervalSince1970 + kProbeResultMemoTTLSeconds;
                    strongSelf.resultMemoByHostKey[hostKey] = stored;
                }

                BOOL cancelled = handle.cancelled;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (cancelled) {
                        return;
                    }
                    completion(result, code);
                });
            };

        handle.cancelBlock = ^{
            dispatch_async(strongSelf.queue, ^{
                finish(BrowserReachabilityProbeResultUnknown, 0);
            });
        };

        const char *hostC = host.UTF8String ?: "";
        char portBuf[16];
        snprintf(portBuf, sizeof(portBuf), "%u", (unsigned)port);
        nw_endpoint_t endpoint = nw_endpoint_create_host(hostC, portBuf);
        // 仅 TCP，不做 TLS；避免证书问题被当成不可达。
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                                   NW_PARAMETERS_DEFAULT_CONFIGURATION);
        connection = nw_connection_create(endpoint, parameters);
        nw_connection_set_queue(connection, strongSelf.queue);
        nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
            if (finished || handle.cancelled) {
                return;
            }
            if (state == nw_connection_state_ready) {
                finish(BrowserReachabilityProbeResultReachable, 0);
                return;
            }
            if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
                if (!error) {
                    finish(BrowserReachabilityProbeResultUnknown, 0);
                    return;
                }
                nw_error_domain_t domain = nw_error_get_error_domain(error);
                int code = nw_error_get_error_code(error);
                if (domain == nw_error_domain_dns) {
                    finish(BrowserReachabilityProbeResultDNSFailed, NSURLErrorDNSLookupFailed);
                    return;
                }
                if (domain == nw_error_domain_posix) {
                    if (code == ECONNREFUSED || code == EHOSTUNREACH || code == ENETUNREACH
                        || code == EADDRNOTAVAIL) {
                        finish(BrowserReachabilityProbeResultUnreachable, NSURLErrorCannotConnectToHost);
                        return;
                    }
                }
                finish(BrowserReachabilityProbeResultUnknown, 0);
            }
        });

        timeoutSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, strongSelf.queue);
        dispatch_source_set_timer(timeoutSource,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kProbeBudgetSeconds * NSEC_PER_SEC)),
                                  DISPATCH_TIME_FOREVER,
                                  (uint64_t)(50 * NSEC_PER_MSEC));
        dispatch_source_set_event_handler(timeoutSource, ^{
            finish(BrowserReachabilityProbeResultUnknown, 0);
        });
        dispatch_resume(timeoutSource);
        nw_connection_start(connection);
    });

    return handle;
}

@end

@interface BrowserHostNegativeCacheEntry : NSObject
@property (nonatomic, assign) NSInteger code;
@property (nonatomic, assign) NSTimeInterval expiry;
@end

@implementation BrowserHostNegativeCacheEntry
@end

@interface BrowserHostNegativeCache ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserHostNegativeCacheEntry *> *entries;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation BrowserHostNegativeCache

+ (instancetype)sharedCache {
    static BrowserHostNegativeCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[self alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.meobrowser.host-negative-cache", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSString *)hostKeyForURL:(NSURL *)url {
    if (!url.host.length) {
        return nil;
    }
    NSString *host = url.host.lowercaseString;
    NSInteger port = url.port != nil ? url.port.integerValue
        : ([url.scheme.lowercaseString isEqualToString:@"https"] ? 443 : 80);
    BOOL defaultPort = ([url.scheme.lowercaseString isEqualToString:@"https"] && port == 443)
        || ([url.scheme.lowercaseString isEqualToString:@"http"] && port == 80);
    if (defaultPort) {
        return host;
    }
    return [NSString stringWithFormat:@"%@:%ld", host, (long)port];
}

- (NSNumber *)failureCodeForHostKey:(NSString *)hostKey {
    if (hostKey.length == 0) {
        return nil;
    }
    __block NSNumber *code = nil;
    dispatch_sync(self.queue, ^{
        BrowserHostNegativeCacheEntry *entry = self.entries[hostKey];
        if (!entry) {
            return;
        }
        if (entry.expiry <= NSDate.date.timeIntervalSince1970) {
            [self.entries removeObjectForKey:hostKey];
            return;
        }
        code = @(entry.code);
    });
    return code;
}

- (void)recordFailureCode:(NSInteger)code forHostKey:(NSString *)hostKey {
    if (hostKey.length == 0 || code == 0) {
        return;
    }
    dispatch_async(self.queue, ^{
        BrowserHostNegativeCacheEntry *entry = [[BrowserHostNegativeCacheEntry alloc] init];
        entry.code = code;
        entry.expiry = NSDate.date.timeIntervalSince1970 + kNegativeCacheTTLSeconds;
        self.entries[hostKey] = entry;
    });
}

- (void)clearHostKey:(NSString *)hostKey {
    if (hostKey.length == 0) {
        return;
    }
    dispatch_async(self.queue, ^{
        [self.entries removeObjectForKey:hostKey];
    });
}

- (void)clearAll {
    dispatch_async(self.queue, ^{
        [self.entries removeAllObjects];
    });
}

@end
