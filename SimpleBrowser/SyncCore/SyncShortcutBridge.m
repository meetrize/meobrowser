#import "SyncShortcutBridge.h"
#import "SyncRecord.h"
#import "SyncKind.h"
#import "SyncDevice.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"

static NSString * const kSyncShortcutMetaKey = @"meo.sync.shortcutMeta";

@implementation SyncShortcutBridge

+ (instancetype)sharedBridge {
    static SyncShortcutBridge *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (NSMutableDictionary *)loadMeta {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSyncShortcutMetaKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveMeta:(NSDictionary *)meta {
    [NSUserDefaults.standardUserDefaults setObject:meta forKey:kSyncShortcutMetaKey];
}

- (SyncRecord *)recordFromItem:(BrowserShortcutItem *)item meta:(NSDictionary *)meta {
    NSDictionary *m = meta[item.itemID];
    long long updatedAt = 0;
    NSString *deviceId = [SyncDevice deviceId];
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
    SyncRecord *record = [[SyncRecord alloc] init];
    record.recordID = item.itemID ?: @"";
    record.kind = SyncKindShortcut;
    record.updatedAt = updatedAt;
    record.deviceId = deviceId;
    record.deleted = deleted;
    record.schemaVersion = 1;
    record.payload = @{
        @"title": item.title ?: @"",
        @"url": item.urlString ?: @"",
        @"order": @(item.sortOrder),
        @"kind": item.isFolder ? @"folder" : @"link",
        @"folderId": item.folderID ?: @"",
        @"iconURL": item.iconURLString ?: @"",
    };
    return record;
}

- (NSArray<SyncRecord *> *)exportRecords {
    NSDictionary *meta = [self loadMeta];
    NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (BrowserShortcutItem *item in [BrowserShortcutStore loadShortcuts]) {
        [out addObject:[self recordFromItem:item meta:meta]];
        [seen addObject:item.itemID];
    }
    [meta enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        (void)stop;
        if ([seen containsObject:key]) {
            return;
        }
        if (![obj isKindOfClass:[NSDictionary class]]) {
            return;
        }
        if (![obj[@"deleted"] boolValue]) {
            return;
        }
        SyncRecord *tomb = [[SyncRecord alloc] init];
        tomb.recordID = key;
        tomb.kind = SyncKindShortcut;
        tomb.updatedAt = [obj[@"updatedAt"] longLongValue];
        tomb.deviceId = [obj[@"deviceId"] isKindOfClass:[NSString class]] ? obj[@"deviceId"] : [SyncDevice deviceId];
        tomb.deleted = YES;
        tomb.schemaVersion = 1;
        tomb.payload = @{};
        [out addObject:tomb];
    }];
    return out;
}

- (void)touchLocalRecordsForUpload {
    NSMutableDictionary *meta = [self loadMeta];
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    NSString *deviceId = [SyncDevice deviceId];
    NSMutableSet *alive = [NSMutableSet set];
    for (BrowserShortcutItem *item in [BrowserShortcutStore loadShortcuts]) {
        [alive addObject:item.itemID];
        meta[item.itemID] = @{
            @"updatedAt": @(now),
            @"deviceId": deviceId,
            @"deleted": @NO,
        };
    }
    // 本地已删除但 meta 仍存活 → tombstone
    NSArray *keys = meta.allKeys;
    for (NSString *key in keys) {
        if ([alive containsObject:key]) {
            continue;
        }
        NSDictionary *m = meta[key];
        if (![m isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if ([m[@"deleted"] boolValue]) {
            continue;
        }
        meta[key] = @{
            @"updatedAt": @(now),
            @"deviceId": deviceId,
            @"deleted": @YES,
        };
    }
    [self saveMeta:meta];
}

- (void)applyMergedRecords:(NSArray<SyncRecord *> *)records {
    NSMutableArray<BrowserShortcutItem *> *active = [NSMutableArray array];
    NSMutableDictionary *newMeta = [NSMutableDictionary dictionary];
    NSArray *sorted = [records sortedArrayUsingComparator:^NSComparisonResult(SyncRecord *a, SyncRecord *b) {
        NSInteger oa = [a.payload[@"order"] respondsToSelector:@selector(integerValue)] ? [a.payload[@"order"] integerValue] : 0;
        NSInteger ob = [b.payload[@"order"] respondsToSelector:@selector(integerValue)] ? [b.payload[@"order"] integerValue] : 0;
        if (oa < ob) {
            return NSOrderedAscending;
        }
        if (oa > ob) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    for (SyncRecord *rec in sorted) {
        if (![rec.kind isEqualToString:SyncKindShortcut]) {
            continue;
        }
        newMeta[rec.recordID] = @{
            @"updatedAt": @(rec.updatedAt),
            @"deviceId": rec.deviceId ?: @"",
            @"deleted": @(rec.deleted),
        };
        if (rec.deleted) {
            continue;
        }
        NSDictionary *p = rec.payload ?: @{};
        NSString *itemKind = [p[@"kind"] description] ?: @"link";
        BrowserShortcutItem *item = nil;
        if ([itemKind isEqualToString:@"folder"]) {
            item = [BrowserShortcutItem folderWithTitle:p[@"title"] ?: @"文件夹"
                                             sortOrder:[p[@"order"] integerValue]];
            item.itemID = rec.recordID;
        } else {
            item = [BrowserShortcutItem itemWithTitle:p[@"title"] ?: @""
                                            urlString:p[@"url"] ?: @""
                                        iconURLString:p[@"iconURL"] ?: @""
                                            sortOrder:[p[@"order"] integerValue]];
            item.itemID = rec.recordID;
            item.folderID = p[@"folderId"] ?: @"";
        }
        if (item) {
            [active addObject:item];
        }
    }
    [BrowserShortcutStore saveShortcuts:active];
    [self saveMeta:newMeta];
}

@end
