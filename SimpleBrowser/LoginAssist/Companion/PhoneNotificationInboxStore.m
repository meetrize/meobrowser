#import "PhoneNotificationInboxStore.h"
#import "PhoneNotificationInboxSettings.h"
#import <os/log.h>

NSNotificationName const PhoneNotificationInboxDidChangeNotification = @"PhoneNotificationInboxDidChangeNotification";

static const NSUInteger kInboxHardCap = 2000;
static const NSTimeInterval kOTPTimeBucketSeconds = 120.0;

@interface PhoneNotificationInboxStore ()
@property (nonatomic, strong) NSMutableArray<PhoneNotificationItem *> *items;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutedPackageSet;
@property (nonatomic, copy) NSString *storePath;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PhoneNotificationInboxStore

+ (instancetype)sharedStore {
    static PhoneNotificationInboxStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _mutedPackageSet = [NSMutableSet set];
        _storePath = [[self class] inboxFilePath];
        _queue = dispatch_queue_create("com.meobrowser.phoneNotificationInbox", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_queue, ^{
            [self loadFromDiskLocked];
            [self enforceRetentionAndCapLocked];
            [self persistLocked];
        });
    }
    return self;
}

+ (NSString *)inboxFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"]
                     stringByAppendingPathComponent:@"PhoneNotificationInbox"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [dir stringByAppendingPathComponent:@"inbox.json"];
}

#pragma mark - Public mutating

- (void)upsertMirrorPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }
    if (![PhoneNotificationInboxSettings sharedSettings].inboxEnabled) {
        return;
    }

    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        NSString *packageName = [self stringFrom:payload[@"packageName"]];
        if (packageName.length == 0) {
            return;
        }
        if ([self.mutedPackageSet containsObject:packageName]) {
            os_log_info(OS_LOG_DEFAULT, "inbox skip muted pkg=%{public}@", packageName);
            return;
        }
        NSString *itemID = [self stringFrom:payload[@"id"]];
        if (itemID.length == 0) {
            return;
        }

        NSString *appLabel = [self stringFrom:payload[@"appLabel"]];
        NSString *title = [self stringFrom:payload[@"title"]];
        NSString *body = [self dedupeRepeatedBody:[self stringFrom:payload[@"body"]]];
        long long postTimeMs = 0;
        if ([payload[@"postTimeMs"] respondsToSelector:@selector(longLongValue)]) {
            postTimeMs = [payload[@"postTimeMs"] longLongValue];
        } else if ([payload[@"ts"] respondsToSelector:@selector(doubleValue)]) {
            postTimeMs = (long long)([payload[@"ts"] doubleValue] * 1000.0);
        }
        if (postTimeMs <= 0) {
            postTimeMs = (long long)([NSDate date].timeIntervalSince1970 * 1000.0);
        }

        PhoneNotificationItem *existing = [self itemForIDLocked:itemID];
        if (existing) {
            existing.packageName = packageName;
            existing.appLabel = appLabel;
            existing.title = title;
            existing.body = body;
            existing.postTimeMs = postTimeMs;
            existing.source = PhoneNotificationItemSourceMirror;
            // 保留 read / pinned
        } else {
            PhoneNotificationItem *item = [[PhoneNotificationItem alloc] init];
            item.itemID = itemID;
            item.packageName = packageName;
            item.appLabel = appLabel;
            item.title = title;
            item.body = body;
            item.kind = PhoneNotificationItemKindGeneral;
            item.postTimeMs = postTimeMs;
            item.receivedAt = [NSDate date];
            item.read = NO;
            item.pinned = NO;
            item.source = PhoneNotificationItemSourceMirror;
            [self.items insertObject:item atIndex:0];
        }

        [self enforceRetentionAndCapLocked];
        [self persistLocked];
        changed = YES;
        os_log_info(OS_LOG_DEFAULT,
                    "inbox upsert mirror pkg=%{public}@ titleLen=%lu bodyLen=%lu count=%lu",
                    packageName,
                    (unsigned long)title.length,
                    (unsigned long)body.length,
                    (unsigned long)self.items.count);
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)upsertOTPCode:(NSString *)code {
    NSString *trimmed = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    if (![PhoneNotificationInboxSettings sharedSettings].inboxEnabled ||
        ![PhoneNotificationInboxSettings sharedSettings].otpToInbox) {
        return;
    }

    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        // OTP 绕过 App 静音
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        long long bucket = (long long)(now / kOTPTimeBucketSeconds);
        NSString *itemID = [NSString stringWithFormat:@"otp:%@:%lld", [self stableHash:trimmed], bucket];

        PhoneNotificationItem *existing = [self itemForIDLocked:itemID];
        if (existing) {
            existing.otpCode = trimmed;
            existing.body = trimmed;
            existing.title = @"验证码";
            existing.postTimeMs = (long long)(now * 1000.0);
        } else {
            PhoneNotificationItem *item = [[PhoneNotificationItem alloc] init];
            item.itemID = itemID;
            item.packageName = @"otp";
            item.appLabel = @"验证码";
            item.title = @"验证码";
            item.body = trimmed;
            item.kind = PhoneNotificationItemKindOTP;
            item.otpCode = trimmed;
            item.postTimeMs = (long long)(now * 1000.0);
            item.receivedAt = [NSDate date];
            item.read = NO;
            item.pinned = NO;
            item.source = PhoneNotificationItemSourceOTPSynthetic;
            [self.items insertObject:item atIndex:0];
        }

        [self enforceRetentionAndCapLocked];
        [self persistLocked];
        changed = YES;
        os_log_info(OS_LOG_DEFAULT, "inbox upsert otp codeLen=%lu count=%lu",
                    (unsigned long)trimmed.length,
                    (unsigned long)self.items.count);
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)setRead:(BOOL)read forId:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        PhoneNotificationItem *item = [self itemForIDLocked:itemID];
        if (!item || item.read == read) {
            return;
        }
        item.read = read;
        [self persistLocked];
        changed = YES;
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)setPinned:(BOOL)pinned forId:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        PhoneNotificationItem *item = [self itemForIDLocked:itemID];
        if (!item || item.pinned == pinned) {
            return;
        }
        item.pinned = pinned;
        [self persistLocked];
        changed = YES;
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)deleteId:(NSString *)itemID {
    if (itemID.length == 0) {
        return;
    }
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        NSUInteger idx = [self indexOfIDLocked:itemID];
        if (idx == NSNotFound) {
            return;
        }
        [self.items removeObjectAtIndex:idx];
        [self persistLocked];
        changed = YES;
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)markAllRead {
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        for (PhoneNotificationItem *item in self.items) {
            if (!item.read) {
                item.read = YES;
                changed = YES;
            }
        }
        if (changed) {
            [self persistLocked];
        }
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)purgeRead {
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        NSIndexSet *toRemove = [self.items indexesOfObjectsPassingTest:^BOOL(PhoneNotificationItem *item, NSUInteger idx, BOOL *stop) {
            (void)idx;
            (void)stop;
            return item.read && !item.pinned;
        }];
        if (toRemove.count == 0) {
            return;
        }
        [self.items removeObjectsAtIndexes:toRemove];
        [self persistLocked];
        changed = YES;
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)purgeAll {
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        if (self.items.count == 0) {
            return;
        }
        [self.items removeAllObjects];
        [self persistLocked];
        changed = YES;
    });
    if (changed) {
        [self postDidChange];
    }
}

- (void)setMuted:(BOOL)muted forPackage:(NSString *)packageName {
    NSString *pkg = [packageName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pkg.length == 0) {
        return;
    }
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        BOOL contains = [self.mutedPackageSet containsObject:pkg];
        if (muted && !contains) {
            [self.mutedPackageSet addObject:pkg];
            changed = YES;
        } else if (!muted && contains) {
            [self.mutedPackageSet removeObject:pkg];
            changed = YES;
        }
        if (changed) {
            [self persistLocked];
        }
    });
    if (changed) {
        [self postDidChange];
    }
}

#pragma mark - Public querying

- (NSArray<PhoneNotificationItem *> *)itemsMatchingFilter:(PhoneNotificationFilter *)filter {
    __block NSArray<PhoneNotificationItem *> *result = @[];
    dispatch_sync(self.queue, ^{
        NSMutableArray<PhoneNotificationItem *> *out = [NSMutableArray array];
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *startOfToday = [cal startOfDayForDate:[NSDate date]];
        PhoneNotificationInboxBucket bucket = PhoneNotificationInboxBucketAll;
        NSString *query = nil;
        NSString *packageFilter = nil;
        if (filter) {
            bucket = filter.bucket;
            if (filter.query.length > 0) {
                query = filter.query.lowercaseString;
            }
            packageFilter = filter.packageName;
        }

        for (PhoneNotificationItem *item in self.items) {
            if (packageFilter.length > 0 && ![item.packageName isEqualToString:packageFilter]) {
                continue;
            }
            switch (bucket) {
                case PhoneNotificationInboxBucketUnread:
                    if (item.read) continue;
                    break;
                case PhoneNotificationInboxBucketOTP:
                    if (item.kind != PhoneNotificationItemKindOTP) continue;
                    break;
                case PhoneNotificationInboxBucketToday: {
                    NSDate *post = [NSDate dateWithTimeIntervalSince1970:item.postTimeMs / 1000.0];
                    if ([post compare:startOfToday] == NSOrderedAscending) continue;
                    break;
                }
                case PhoneNotificationInboxBucketPinned:
                    if (!item.pinned) continue;
                    break;
                case PhoneNotificationInboxBucketAll:
                default:
                    break;
            }
            if (query.length > 0) {
                NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@",
                                  item.appLabel ?: @"",
                                  item.title ?: @"",
                                  item.body ?: @"",
                                  item.packageName ?: @""] lowercaseString];
                if (![hay containsString:query]) {
                    continue;
                }
            }
            [out addObject:item];
        }
        result = [out copy];
    });
    return result;
}

- (nullable PhoneNotificationItem *)itemForID:(NSString *)itemID {
    if (itemID.length == 0) {
        return nil;
    }
    __block PhoneNotificationItem *found = nil;
    dispatch_sync(self.queue, ^{
        found = [self itemForIDLocked:itemID];
    });
    return found;
}

- (NSUInteger)unreadCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
        for (PhoneNotificationItem *item in self.items) {
            if (!item.read) {
                count++;
            }
        }
    });
    return count;
}

- (NSUInteger)itemCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
        count = self.items.count;
    });
    return count;
}

- (BOOL)isMutedPackage:(NSString *)packageName {
    if (packageName.length == 0) {
        return NO;
    }
    __block BOOL muted = NO;
    dispatch_sync(self.queue, ^{
        muted = [self.mutedPackageSet containsObject:packageName];
    });
    return muted;
}

- (NSArray<NSString *> *)mutedPackages {
    __block NSArray<NSString *> *list = @[];
    dispatch_sync(self.queue, ^{
        list = [[self.mutedPackageSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    });
    return list;
}

#pragma mark - Locked helpers

- (nullable PhoneNotificationItem *)itemForIDLocked:(NSString *)itemID {
    NSUInteger idx = [self indexOfIDLocked:itemID];
    return idx == NSNotFound ? nil : self.items[idx];
}

- (NSUInteger)indexOfIDLocked:(NSString *)itemID {
    return [self.items indexOfObjectPassingTest:^BOOL(PhoneNotificationItem *item, NSUInteger idx, BOOL *stop) {
        (void)idx;
        (void)stop;
        return [item.itemID isEqualToString:itemID];
    }];
}

- (void)enforceRetentionAndCapLocked {
    NSInteger days = [PhoneNotificationInboxSettings sharedSettings].retentionDays;
    if (days > 0) {
        NSTimeInterval cutoff = [NSDate date].timeIntervalSince1970 - (days * 24.0 * 3600.0);
        NSIndexSet *expired = [self.items indexesOfObjectsPassingTest:^BOOL(PhoneNotificationItem *item, NSUInteger idx, BOOL *stop) {
            (void)idx;
            (void)stop;
            if (item.pinned) {
                return NO;
            }
            return [item.receivedAt timeIntervalSince1970] < cutoff;
        }];
        if (expired.count > 0) {
            [self.items removeObjectsAtIndexes:expired];
        }
    }

    if (self.items.count <= kInboxHardCap) {
        return;
    }
    // 已按插入序大致新→旧；淘汰最旧的非钉选
    NSMutableIndexSet *remove = [NSMutableIndexSet indexSet];
    for (NSInteger i = (NSInteger)self.items.count - 1; i >= 0 && self.items.count - remove.count > kInboxHardCap; i--) {
        PhoneNotificationItem *item = self.items[(NSUInteger)i];
        if (!item.pinned) {
            [remove addIndex:(NSUInteger)i];
        }
    }
    if (remove.count > 0) {
        [self.items removeObjectsAtIndexes:remove];
    }
}

- (void)loadFromDiskLocked {
    [self.items removeAllObjects];
    [self.mutedPackageSet removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *root = (NSDictionary *)json;
    NSArray *rawItems = root[@"items"];
    if ([rawItems isKindOfClass:[NSArray class]]) {
        for (id raw in rawItems) {
            PhoneNotificationItem *item = [PhoneNotificationItem itemWithDictionary:raw];
            if (item) {
                [self.items addObject:item];
            }
        }
    }
    NSArray *muted = root[@"mutedPackages"];
    if ([muted isKindOfClass:[NSArray class]]) {
        for (id pkg in muted) {
            if ([pkg isKindOfClass:[NSString class]] && [(NSString *)pkg length] > 0) {
                [self.mutedPackageSet addObject:pkg];
            }
        }
    }
}

- (void)persistLocked {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.items.count];
    for (PhoneNotificationItem *item in self.items) {
        [list addObject:[item dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"items": list,
        @"mutedPackages": [[self.mutedPackageSet allObjects] sortedArrayUsingSelector:@selector(compare:)],
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
    if (!data) {
        os_log_error(OS_LOG_DEFAULT, "inbox persist encode failed: %{public}@", error.localizedDescription);
        return;
    }
    if (![data writeToFile:self.storePath options:NSDataWritingAtomic error:&error]) {
        os_log_error(OS_LOG_DEFAULT, "inbox persist write failed: %{public}@", error.localizedDescription);
    }
}

- (void)postDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PhoneNotificationInboxDidChangeNotification
                                                            object:self];
    });
}

- (NSString *)stringFrom:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

/// 折叠 Android 把 EXTRA_TEXT / BIG_TEXT 拼成的重复行（同文案两遍）。
- (NSString *)dedupeRepeatedBody:(NSString *)body {
    if (body.length == 0) {
        return body ?: @"";
    }
    NSArray<NSString *> *rawLines = [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *raw in rawLines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) {
            continue;
        }
        BOOL skip = NO;
        for (NSUInteger i = 0; i < kept.count; i++) {
            NSString *existing = kept[i];
            if ([existing isEqualToString:line] || [existing containsString:line]) {
                skip = YES;
                break;
            }
            if ([line containsString:existing] && line.length > existing.length) {
                kept[i] = line;
                skip = YES;
                break;
            }
        }
        if (!skip) {
            [kept addObject:line];
        }
    }
    return [kept componentsJoinedByString:@"\n"];
}

- (NSString *)stableHash:(NSString *)string {
    NSUInteger hash = string.hash;
    return [NSString stringWithFormat:@"%08lx", (unsigned long)(hash & 0xffffffff)];
}

@end
