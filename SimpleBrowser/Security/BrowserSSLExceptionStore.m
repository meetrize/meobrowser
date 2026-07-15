#import "BrowserSSLExceptionStore.h"

@interface BrowserSSLExceptionStore ()
@property (nonatomic, strong) NSMutableSet<NSString *> *allowedHostKeys;
@end

@implementation BrowserSSLExceptionStore

+ (instancetype)sharedStore {
    static BrowserSSLExceptionStore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserSSLExceptionStore alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _allowedHostKeys = [[NSMutableSet alloc] init];
    }
    return self;
}

+ (NSString *)hostKeyForHost:(NSString *)host port:(NSInteger)port {
    NSString *normalizedHost = host.lowercaseString ?: @"";
    NSInteger normalizedPort = port;
    if (normalizedPort <= 0) {
        normalizedPort = 443;
    }
    return [NSString stringWithFormat:@"%@:%ld", normalizedHost, (long)normalizedPort];
}

+ (nullable NSString *)hostKeyForURL:(NSURL *)url {
    if (!url || url.host.length == 0) {
        return nil;
    }
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) {
        return nil;
    }
    NSNumber *portNumber = url.port;
    NSInteger port = portNumber != nil ? portNumber.integerValue : 443;
    return [self hostKeyForHost:url.host port:port];
}

- (BOOL)allowsHostKey:(NSString *)hostKey {
    if (hostKey.length == 0) {
        return NO;
    }
    @synchronized (self) {
        return [self.allowedHostKeys containsObject:hostKey];
    }
}

- (BOOL)allowsURL:(NSURL *)url {
    NSString *key = [[self class] hostKeyForURL:url];
    if (!key) {
        return NO;
    }
    return [self allowsHostKey:key];
}

- (void)allowHostKey:(NSString *)hostKey {
    if (hostKey.length == 0) {
        return;
    }
    @synchronized (self) {
        [self.allowedHostKeys addObject:hostKey];
    }
}

- (void)revokeHostKey:(NSString *)hostKey {
    if (hostKey.length == 0) {
        return;
    }
    @synchronized (self) {
        [self.allowedHostKeys removeObject:hostKey];
    }
}

- (void)removeAll {
    @synchronized (self) {
        [self.allowedHostKeys removeAllObjects];
    }
}

@end
