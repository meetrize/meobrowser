#import "BrowserHistoryStore.h"
#import "BrowserHistoryEntry.h"
#import "BrowsingPreferences.h"
#import "SyncDevice.h"

NSNotificationName const BrowserHistoryStoreDidChangeNotification = @"BrowserHistoryStoreDidChangeNotification";
NSString * const BrowserHistoryClearOnQuitDefaultsKey = @"BrowserHistoryClearOnQuit";

static const NSUInteger kMaxActiveEntries = 500;
static const NSUInteger kMaxTitleLength = 200;
static const NSTimeInterval kVisitCountDebounceInterval = 2.0;
static const NSTimeInterval kPersistDebounceInterval = 0.3;
static const NSTimeInterval kTombstoneRetentionSeconds = 30.0 * 24.0 * 60.0 * 60.0;
static const NSUInteger kMaxTombstones = 200;

@interface BrowserHistoryStore ()
@property (nonatomic, strong) NSMutableArray<BrowserHistoryEntry *> *entries;
@property (nonatomic, copy) NSString *storePath;
@property (nonatomic, strong, nullable) dispatch_block_t pendingPersistBlock;
@property (nonatomic, copy, nullable) NSString *lastRecordedURLString;
@property (nonatomic, assign) NSTimeInterval lastRecordedAt;
@end

@implementation BrowserHistoryStore

+ (instancetype)sharedStore {
    static BrowserHistoryStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (BOOL)clearOnQuitEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BrowserHistoryClearOnQuitDefaultsKey];
}

+ (void)setClearOnQuitEnabled:(BOOL)clearOnQuitEnabled {
    [[NSUserDefaults standardUserDefaults] setBool:clearOnQuitEnabled forKey:BrowserHistoryClearOnQuitDefaultsKey];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _storePath = [[self class] historyFilePath];
        [self loadFromDisk];
    }
    return self;
}

+ (NSString *)historyFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"History"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"history.json"];
}

+ (NSString *)normalizedURLString:(NSURL *)url {
    if (!url) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) {
        return url.absoluteString;
    }
    // 去掉 fragment，避免 SPA hash 噪声分叉。
    components.fragment = nil;
    NSString *string = components.string;
    return string.length > 0 ? string : url.absoluteString;
}

+ (NSString *)truncatedTitle:(NSString *)title fallbackURL:(NSString *)url {
    NSString *value = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        value = url ?: @"";
    }
    if (value.length > kMaxTitleLength) {
        value = [value substringToIndex:kMaxTitleLength];
    }
    return value;
}

- (void)loadFromDisk {
    [self.entries removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *rawList = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        rawList = json[@"entries"];
    } else if ([json isKindOfClass:[NSArray class]]) {
        rawList = json;
    }
    if (![rawList isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in rawList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        BrowserHistoryEntry *entry = [[BrowserHistoryEntry alloc] initWithDictionary:item];
        if (entry) {
            [self.entries addObject:entry];
        }
    }
    [self pruneInMemory];
}

- (BOOL)persistNow {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.entries.count];
    for (BrowserHistoryEntry *entry in self.entries) {
        [list addObject:[entry dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"entries": list,
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
    if (!data) {
        return NO;
    }
    return [data writeToFile:self.storePath options:NSDataWritingAtomic error:nil];
}

- (void)schedulePersist {
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        BrowserHistoryStore *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingPersistBlock = nil;
        [strongSelf persistNow];
    });
    self.pendingPersistBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPersistDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)flushSynchronously {
    if (self.pendingPersistBlock) {
        dispatch_block_cancel(self.pendingPersistBlock);
        self.pendingPersistBlock = nil;
    }
    [self persistNow];
}

- (void)notifyDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserHistoryStoreDidChangeNotification object:self];
}

- (void)pruneInMemory {
    NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - kTombstoneRetentionSeconds;
    NSMutableArray<BrowserHistoryEntry *> *active = [NSMutableArray array];
    NSMutableArray<BrowserHistoryEntry *> *tombstones = [NSMutableArray array];
    for (BrowserHistoryEntry *entry in self.entries) {
        if (entry.deleted) {
            if (entry.updatedAt >= cutoff) {
                [tombstones addObject:entry];
            }
        } else {
            [active addObject:entry];
        }
    }
    [active sortUsingComparator:^NSComparisonResult(BrowserHistoryEntry *a, BrowserHistoryEntry *b) {
        if (a.visitTime == b.visitTime) {
            return NSOrderedSame;
        }
        return a.visitTime > b.visitTime ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (active.count > kMaxActiveEntries) {
        [active removeObjectsInRange:NSMakeRange(kMaxActiveEntries, active.count - kMaxActiveEntries)];
    }
    [tombstones sortUsingComparator:^NSComparisonResult(BrowserHistoryEntry *a, BrowserHistoryEntry *b) {
        if (a.updatedAt == b.updatedAt) {
            return NSOrderedSame;
        }
        return a.updatedAt > b.updatedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (tombstones.count > kMaxTombstones) {
        [tombstones removeObjectsInRange:NSMakeRange(kMaxTombstones, tombstones.count - kMaxTombstones)];
    }
    [self.entries removeAllObjects];
    [self.entries addObjectsFromArray:active];
    [self.entries addObjectsFromArray:tombstones];
}

- (nullable BrowserHistoryEntry *)activeEntryForURLString:(NSString *)urlString {
    for (BrowserHistoryEntry *entry in self.entries) {
        if (!entry.deleted && [entry.url isEqualToString:urlString]) {
            return entry;
        }
    }
    return nil;
}

- (void)recordURL:(NSURL *)url title:(NSString *)title {
    if (![BrowsingPreferences isPersistableURL:url]) {
        return;
    }
    NSString *urlString = [[self class] normalizedURLString:url];
    if (urlString.length == 0) {
        return;
    }
    NSString *safeTitle = [[self class] truncatedTitle:title fallbackURL:urlString];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL withinDebounce = [urlString isEqualToString:self.lastRecordedURLString]
        && (now - self.lastRecordedAt) < kVisitCountDebounceInterval;

    BrowserHistoryEntry *existing = [self activeEntryForURLString:urlString];
    if (existing) {
        existing.visitTime = now;
        existing.updatedAt = now;
        existing.deviceId = [SyncDevice deviceId];
        if (!withinDebounce) {
            existing.visitCount += 1;
        }
        if (safeTitle.length > 0 && ![safeTitle isEqualToString:urlString]) {
            existing.title = safeTitle;
        } else if (existing.title.length == 0) {
            existing.title = safeTitle;
        }
    } else {
        BrowserHistoryEntry *entry = [BrowserHistoryEntry entryWithURL:urlString
                                                                 title:safeTitle
                                                              deviceId:[SyncDevice deviceId]];
        [self.entries addObject:entry];
    }

    self.lastRecordedURLString = urlString;
    self.lastRecordedAt = now;
    [self pruneInMemory];
    [self schedulePersist];
    [self notifyDidChange];
}

- (void)updateTitle:(NSString *)title forURL:(NSURL *)url {
    if (title.length == 0 || !url) {
        return;
    }
    NSString *urlString = [[self class] normalizedURLString:url];
    if (urlString.length == 0) {
        return;
    }
    BrowserHistoryEntry *existing = [self activeEntryForURLString:urlString];
    if (!existing) {
        return;
    }
    NSString *safeTitle = [[self class] truncatedTitle:title fallbackURL:urlString];
    if ([existing.title isEqualToString:safeTitle]) {
        return;
    }
    existing.title = safeTitle;
    existing.updatedAt = [[NSDate date] timeIntervalSince1970];
    [self schedulePersist];
    [self notifyDidChange];
}

- (NSArray<BrowserHistoryEntry *> *)activeEntriesSortedByVisitTime {
    NSMutableArray<BrowserHistoryEntry *> *active = [NSMutableArray array];
    for (BrowserHistoryEntry *entry in self.entries) {
        if (!entry.deleted) {
            [active addObject:[entry copy]];
        }
    }
    [active sortUsingComparator:^NSComparisonResult(BrowserHistoryEntry *a, BrowserHistoryEntry *b) {
        if (a.visitTime == b.visitTime) {
            return NSOrderedSame;
        }
        return a.visitTime > b.visitTime ? NSOrderedAscending : NSOrderedDescending;
    }];
    return active;
}

- (BOOL)entry:(BrowserHistoryEntry *)entry matchesQuery:(NSString *)query {
    NSString *q = query.lowercaseString;
    if (q.length == 0) {
        return YES;
    }
    if ([entry.title.lowercaseString containsString:q]) {
        return YES;
    }
    if ([entry.url.lowercaseString containsString:q]) {
        return YES;
    }
    if ([entry.displayHost.lowercaseString containsString:q]) {
        return YES;
    }
    return NO;
}

- (NSInteger)matchScoreForEntry:(BrowserHistoryEntry *)entry query:(NSString *)query {
    NSString *q = query.lowercaseString;
    NSString *title = entry.title.lowercaseString;
    NSString *host = entry.displayHost.lowercaseString;
    NSString *url = entry.url.lowercaseString;
    if ([host hasPrefix:q] || [title hasPrefix:q]) {
        return 300;
    }
    if ([host containsString:q] || [title containsString:q]) {
        return 200;
    }
    if ([url containsString:q]) {
        return 100;
    }
    return NSNotFound;
}

- (NSArray<BrowserHistoryEntry *> *)entriesMatchingQuery:(NSString *)query limit:(NSUInteger)limit {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<BrowserHistoryEntry *> *all = [self activeEntriesSortedByVisitTime];
    if (trimmed.length == 0) {
        if (limit > 0 && all.count > limit) {
            return [all subarrayWithRange:NSMakeRange(0, limit)];
        }
        return all;
    }
    NSMutableArray<BrowserHistoryEntry *> *matches = [NSMutableArray array];
    for (BrowserHistoryEntry *entry in all) {
        if ([self entry:entry matchesQuery:trimmed]) {
            [matches addObject:entry];
            if (limit > 0 && matches.count >= limit) {
                break;
            }
        }
    }
    return matches;
}

- (NSArray<BrowserHistoryEntry *> *)suggestionsMatchingQuery:(NSString *)query limit:(NSUInteger)limit {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || limit == 0) {
        return @[];
    }
    NSMutableArray<BrowserHistoryEntry *> *matches = [NSMutableArray array];
    for (BrowserHistoryEntry *entry in self.entries) {
        if (entry.deleted) {
            continue;
        }
        if ([self matchScoreForEntry:entry query:trimmed] != NSNotFound) {
            [matches addObject:[entry copy]];
        }
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [matches sortUsingComparator:^NSComparisonResult(BrowserHistoryEntry *a, BrowserHistoryEntry *b) {
        NSInteger scoreA = [self matchScoreForEntry:a query:trimmed];
        NSInteger scoreB = [self matchScoreForEntry:b query:trimmed];
        // 近因加权：7 天内额外加分体现在 visitCount 比较前的综合分。
        double recencyA = MAX(0.0, 1.0 - ((now - a.visitTime) / (7.0 * 24.0 * 3600.0)));
        double recencyB = MAX(0.0, 1.0 - ((now - b.visitTime) / (7.0 * 24.0 * 3600.0)));
        double rankA = scoreA + a.visitCount * 2.0 + recencyA * 50.0;
        double rankB = scoreB + b.visitCount * 2.0 + recencyB * 50.0;
        if (fabs(rankA - rankB) > 0.01) {
            return rankA > rankB ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.visitTime != b.visitTime) {
            return a.visitTime > b.visitTime ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.title compare:b.title];
    }];
    if (matches.count > limit) {
        return [matches subarrayWithRange:NSMakeRange(0, limit)];
    }
    return matches;
}

- (void)softDeleteEntry:(BrowserHistoryEntry *)entry {
    entry.deleted = YES;
    entry.updatedAt = [[NSDate date] timeIntervalSince1970];
}

- (void)deleteEntryWithID:(NSString *)entryID {
    if (entryID.length == 0) {
        return;
    }
    for (BrowserHistoryEntry *entry in self.entries) {
        if ([entry.entryID isEqualToString:entryID] && !entry.deleted) {
            [self softDeleteEntry:entry];
            [self pruneInMemory];
            [self schedulePersist];
            [self notifyDidChange];
            return;
        }
    }
}

- (void)deleteEntriesForHost:(NSString *)host {
    if (host.length == 0) {
        return;
    }
    NSString *needle = host.lowercaseString;
    if ([needle hasPrefix:@"www."]) {
        needle = [needle substringFromIndex:4];
    }
    BOOL changed = NO;
    for (BrowserHistoryEntry *entry in self.entries) {
        if (entry.deleted) {
            continue;
        }
        NSString *entryHost = entry.displayHost.lowercaseString;
        if ([entryHost isEqualToString:needle] || [entryHost hasSuffix:[@"." stringByAppendingString:needle]]) {
            [self softDeleteEntry:entry];
            changed = YES;
        }
    }
    if (changed) {
        [self pruneInMemory];
        [self schedulePersist];
        [self notifyDidChange];
    }
}

- (void)clearAll {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (BrowserHistoryEntry *entry in self.entries) {
        if (!entry.deleted) {
            entry.deleted = YES;
            entry.updatedAt = now;
        }
    }
    [self pruneInMemory];
    [self schedulePersist];
    [self notifyDidChange];
}

- (void)clearVisitedSince:(NSTimeInterval)sinceUnix {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL changed = NO;
    for (BrowserHistoryEntry *entry in self.entries) {
        if (!entry.deleted && entry.visitTime >= sinceUnix) {
            entry.deleted = YES;
            entry.updatedAt = now;
            changed = YES;
        }
    }
    if (changed) {
        [self pruneInMemory];
        [self schedulePersist];
        [self notifyDidChange];
    }
}

- (void)clearVisitedToday {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *startOfDay = [calendar startOfDayForDate:[NSDate date]];
    [self clearVisitedSince:[startOfDay timeIntervalSince1970]];
}

- (void)clearIfConfiguredOnQuit {
    if ([[self class] clearOnQuitEnabled]) {
        [self.entries removeAllObjects];
        [self persistNow];
    } else {
        [self flushSynchronously];
    }
}

@end
