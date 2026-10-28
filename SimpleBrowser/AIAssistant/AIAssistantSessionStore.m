#import "AIAssistantSessionStore.h"

NSNotificationName const AIAssistantSessionStoreDidChangeNotification = @"AIAssistantSessionStoreDidChangeNotification";

static NSString * const kCurrentSessionKey = @"AIAssistant.currentSessionId";

@interface AIAssistantSessionStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIAssistantSession *> *byId;
@property (nonatomic, copy, nullable) NSString *currentSessionIdInternal;
@end

@implementation AIAssistantSessionStore

+ (AIAssistantSessionStore *)sharedStore {
    static AIAssistantSessionStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[AIAssistantSessionStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _byId = [NSMutableDictionary dictionary];
        _currentSessionIdInternal = [NSUserDefaults.standardUserDefaults stringForKey:kCurrentSessionKey];
        [self loadFromDisk];
    }
    return self;
}

- (NSURL *)sessionsFileURL {
    NSArray *urls = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = urls.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"MeoBrowser/AIAssistant"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"sessions.json"]];
}

- (void)loadFromDisk {
    NSURL *url = [self sessionsFileURL];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSArray *arr = json[@"sessions"];
    if (![arr isKindOfClass:[NSArray class]]) {
        return;
    }
    [self.byId removeAllObjects];
    for (id item in arr) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        AIAssistantSession *s = [AIAssistantSession sessionFromDictionary:item];
        if (s.sessionId.length) {
            self.byId[s.sessionId] = s;
        }
    }
    if (self.currentSessionIdInternal.length && !self.byId[self.currentSessionIdInternal]) {
        self.currentSessionIdInternal = nil;
    }
}

- (void)persistToDisk {
    NSMutableArray *arr = [NSMutableArray array];
    for (AIAssistantSession *s in self.byId.allValues) {
        [arr addObject:[s dictionaryRepresentation]];
    }
    NSDictionary *root = @{ @"sessions": arr, @"version": @1 };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToURL:[self sessionsFileURL] atomically:YES];
    }
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:AIAssistantSessionStoreDidChangeNotification object:self];
}

- (NSString *)currentSessionId {
    return self.currentSessionIdInternal;
}

- (void)setCurrentSessionId:(NSString *)currentSessionId {
    NSString *next = currentSessionId.length ? currentSessionId : nil;
    if ((self.currentSessionIdInternal == nil && next == nil) ||
        [self.currentSessionIdInternal isEqualToString:next]) {
        return;
    }
    self.currentSessionIdInternal = next;
    if (next) {
        [NSUserDefaults.standardUserDefaults setObject:next forKey:kCurrentSessionKey];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCurrentSessionKey];
    }
    [self notify];
}

- (NSArray<AIAssistantSession *> *)allSessionsSorted {
    NSArray *all = self.byId.allValues;
    return [all sortedArrayUsingComparator:^NSComparisonResult(AIAssistantSession *a, AIAssistantSession *b) {
        if (a.updatedAt > b.updatedAt) return NSOrderedAscending;
        if (a.updatedAt < b.updatedAt) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (AIAssistantSession *)sessionForId:(NSString *)sessionId {
    if (sessionId.length == 0) return nil;
    return self.byId[sessionId];
}

- (AIAssistantSession *)currentSession {
    return [self sessionForId:self.currentSessionIdInternal];
}

- (AIAssistantSession *)createSessionWithProviderId:(NSString *)providerId
                                          bindingId:(NSString *)bindingId
                                            modelId:(NSString *)modelId
                                              title:(NSString *)title {
    AIAssistantSession *s = [[AIAssistantSession alloc] init];
    s.sessionId = [[NSUUID UUID] UUIDString];
    s.providerId = providerId.length ? providerId : @"deepseek";
    s.bindingId = bindingId;
    s.modelId = modelId;
    s.title = title.length ? title : @"新对话";
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    s.createdAt = now;
    s.updatedAt = now;
    s.connection = bindingId.length ? AIAssistantSessionConnectionReady : AIAssistantSessionConnectionOpening;
    self.byId[s.sessionId] = s;
    self.currentSessionIdInternal = s.sessionId;
    [NSUserDefaults.standardUserDefaults setObject:s.sessionId forKey:kCurrentSessionKey];
    [self persistToDisk];
    [self notify];
    return s;
}

- (void)saveSession:(AIAssistantSession *)session {
    if (!session.sessionId.length) return;
    self.byId[session.sessionId] = session;
    [self persistToDisk];
    [self notify];
}

- (void)touchAndPersist:(AIAssistantSession *)session {
    if (!session) return;
    session.updatedAt = [NSDate date].timeIntervalSince1970;
    [self saveSession:session];
}

- (void)deleteSessionId:(NSString *)sessionId {
    if (sessionId.length == 0) return;
    [self.byId removeObjectForKey:sessionId];
    if ([self.currentSessionIdInternal isEqualToString:sessionId]) {
        AIAssistantSession *next = [self allSessionsSorted].firstObject;
        self.currentSessionIdInternal = next.sessionId;
        if (next.sessionId) {
            [NSUserDefaults.standardUserDefaults setObject:next.sessionId forKey:kCurrentSessionKey];
        } else {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:kCurrentSessionKey];
        }
    }
    [self persistToDisk];
    [self notify];
}

- (void)deleteAllSessions {
    [self.byId removeAllObjects];
    self.currentSessionIdInternal = nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kCurrentSessionKey];
    [self persistToDisk];
    [self notify];
}

- (NSArray<AIAssistantSession *> *)sessionsMatchingQuery:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (q.length == 0) {
        return [self allSessionsSorted];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (AIAssistantSession *s in [self allSessionsSorted]) {
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@",
                          s.title ?: @"", s.providerId ?: @"", s.previewText ?: @""] lowercaseString];
        if ([hay containsString:q]) {
            [out addObject:s];
        }
    }
    return out;
}

@end
