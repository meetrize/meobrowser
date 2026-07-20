#import "CompanionShortcutSync.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"

static NSString * const kSyncMetaKey = @"meo.sync.shortcutMeta";

@implementation CompanionShortcutSync

+ (instancetype)sharedSync {
    static CompanionShortcutSync *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSString *)macDeviceId {
    return [NSString stringWithFormat:@"mac-%@", NSHost.currentHost.localizedName ?: @"host"];
}

- (NSMutableDictionary *)loadMeta {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSyncMetaKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveMeta:(NSDictionary *)meta {
    [NSUserDefaults.standardUserDefaults setObject:meta forKey:kSyncMetaKey];
}

- (NSDictionary *)recordFromItem:(BrowserShortcutItem *)item meta:(NSDictionary *)meta {
    NSDictionary *m = meta[item.itemID];
    long long updatedAt = 0;
    NSString *deviceId = [self macDeviceId];
    BOOL deleted = NO;
    if ([m isKindOfClass:[NSDictionary class]]) {
        updatedAt = [m[@"updatedAt"] longLongValue];
        if ([m[@"deviceId"] isKindOfClass:[NSString class]] && [m[@"deviceId"] length]) {
            deviceId = m[@"deviceId"];
        }
        deleted = [m[@"deleted"] boolValue];
    }
    if (updatedAt <= 0) {
        updatedAt = (long long)[[NSDate date] timeIntervalSince1970];
    }
    NSString *kind = item.isFolder ? @"folder" : @"link";
    return @{
        @"id": item.itemID ?: @"",
        @"title": item.title ?: @"",
        @"url": item.urlString ?: @"",
        @"order": @(item.sortOrder),
        @"kind": kind,
        @"folderId": item.folderID ?: @"",
        @"iconURL": item.iconURLString ?: @"",
        @"updatedAt": @(updatedAt),
        @"deviceId": deviceId,
        @"deleted": @(deleted),
    };
}

- (BOOL)incomingWins:(NSDictionary *)incoming local:(NSDictionary *)local {
    long long iu = [incoming[@"updatedAt"] longLongValue];
    long long lu = [local[@"updatedAt"] longLongValue];
    if (iu > lu) return YES;
    if (iu < lu) return NO;
    NSString *idIn = [incoming[@"deviceId"] description] ?: @"";
    NSString *idLo = [local[@"deviceId"] description] ?: @"";
    return [idIn compare:idLo] == NSOrderedDescending;
}

- (void)mergeShortcutRecords:(NSArray<NSDictionary *> *)records {
    if (records.count == 0) return;
    NSMutableDictionary *meta = [self loadMeta];
    NSMutableDictionary<NSString *, NSDictionary *> *merged = [NSMutableDictionary dictionary];

    // seed from local
    for (BrowserShortcutItem *item in [BrowserShortcutStore loadShortcuts]) {
        NSDictionary *rec = [self recordFromItem:item meta:meta];
        merged[item.itemID] = rec;
    }
    // also keep tombstones only in meta
    [meta enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        (void)stop;
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        if ([obj[@"deleted"] boolValue] && !merged[key]) {
            NSMutableDictionary *tomb = [obj mutableCopy];
            tomb[@"id"] = key;
            merged[key] = tomb;
        }
    }];

    for (NSDictionary *incoming in records) {
        if (![incoming isKindOfClass:[NSDictionary class]]) continue;
        NSString *rid = incoming[@"id"];
        if (![rid isKindOfClass:[NSString class]] || rid.length == 0) continue;
        NSDictionary *local = merged[rid];
        if (!local || [self incomingWins:incoming local:local]) {
            merged[rid] = incoming;
        }
    }

    NSMutableArray<BrowserShortcutItem *> *active = [NSMutableArray array];
    NSMutableDictionary *newMeta = [NSMutableDictionary dictionary];
    NSArray *sorted = [merged.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger oa = [a[@"order"] respondsToSelector:@selector(integerValue)] ? [a[@"order"] integerValue] : 0;
        NSInteger ob = [b[@"order"] respondsToSelector:@selector(integerValue)] ? [b[@"order"] integerValue] : 0;
        if (oa < ob) return NSOrderedAscending;
        if (oa > ob) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (NSDictionary *rec in sorted) {
        NSString *rid = rec[@"id"];
        BOOL deleted = [rec[@"deleted"] boolValue];
        newMeta[rid] = @{
            @"updatedAt": rec[@"updatedAt"] ?: @0,
            @"deviceId": rec[@"deviceId"] ?: @"",
            @"deleted": @(deleted),
        };
        if (deleted) continue;
        NSString *kind = [rec[@"kind"] description] ?: @"link";
        BrowserShortcutItem *item = nil;
        if ([kind isEqualToString:@"folder"]) {
            item = [BrowserShortcutItem folderWithTitle:rec[@"title"] ?: @"文件夹"
                                             sortOrder:[rec[@"order"] integerValue]];
            item.itemID = rid;
        } else {
            item = [BrowserShortcutItem itemWithTitle:rec[@"title"] ?: @""
                                            urlString:rec[@"url"] ?: @""
                                        iconURLString:rec[@"iconURL"] ?: @""
                                            sortOrder:[rec[@"order"] integerValue]];
            item.itemID = rid;
            item.folderID = rec[@"folderId"] ?: @"";
        }
        if (item) [active addObject:item];
    }
    [BrowserShortcutStore saveShortcuts:active];
    [self saveMeta:newMeta];
}

- (NSArray<NSDictionary *> *)exportShortcutRecords {
    NSDictionary *meta = [self loadMeta];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (BrowserShortcutItem *item in [BrowserShortcutStore loadShortcuts]) {
        [out addObject:[self recordFromItem:item meta:meta]];
        [seen addObject:item.itemID];
    }
    [meta enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        (void)stop;
        if ([seen containsObject:key]) return;
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        if (![obj[@"deleted"] boolValue]) return;
        NSMutableDictionary *tomb = [@{
            @"id": key,
            @"title": @"",
            @"url": @"",
            @"order": @0,
            @"kind": @"link",
            @"folderId": @"",
            @"iconURL": @"",
            @"updatedAt": obj[@"updatedAt"] ?: @0,
            @"deviceId": obj[@"deviceId"] ?: [self macDeviceId],
            @"deleted": @YES,
        } mutableCopy];
        [out addObject:tomb];
    }];
    return out;
}

@end
