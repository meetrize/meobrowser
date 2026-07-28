#import "CloudSyncFormMemoBridge.h"
#import "SyncRecord.h"
#import "SyncKind.h"
#import "SyncDevice.h"
#import "FormMemo.h"
#import "FormMemoStore.h"

static NSString * const kICloudFormMemoMetaKey = @"meo.icloud.formMemoMeta";

@implementation CloudSyncFormMemoBridge

+ (instancetype)sharedBridge {
    static CloudSyncFormMemoBridge *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (NSMutableDictionary *)loadMeta {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kICloudFormMemoMetaKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveMeta:(NSDictionary *)meta {
    [NSUserDefaults.standardUserDefaults setObject:meta forKey:kICloudFormMemoMetaKey];
}

- (NSDictionary *)payloadFromMemo:(FormMemo *)memo {
    NSMutableArray *fields = [NSMutableArray array];
    for (FormMemoField *field in memo.fields) {
        [fields addObject:[field dictionaryRepresentation]];
    }
    return @{
        @"title": memo.title ?: @"",
        @"host": memo.host ?: @"",
        @"pathPrefix": memo.pathPrefix ?: @"",
        @"isDefault": @(memo.isDefault),
        @"waitTimeoutMs": @(memo.waitTimeoutMs),
        @"fields": fields,
    };
}

- (SyncRecord *)recordFromMemo:(FormMemo *)memo meta:(NSDictionary *)meta {
    NSDictionary *m = meta[memo.memoID];
    long long updatedAt = (long long)memo.updatedAt;
    NSString *deviceId = [SyncDevice deviceId];
    BOOL deleted = NO;
    if ([m isKindOfClass:[NSDictionary class]]) {
        long long metaUpdated = [m[@"updatedAt"] longLongValue];
        if (metaUpdated > updatedAt) {
            updatedAt = metaUpdated;
        }
        if ([m[@"deviceId"] isKindOfClass:[NSString class]] && [m[@"deviceId"] length]) {
            deviceId = m[@"deviceId"];
        }
        deleted = [m[@"deleted"] boolValue];
    }
    if (updatedAt <= 0) {
        updatedAt = (long long)[[NSDate date] timeIntervalSince1970];
    }
    SyncRecord *record = [[SyncRecord alloc] init];
    record.recordID = memo.memoID;
    record.kind = SyncKindFormMemo;
    record.updatedAt = updatedAt;
    record.deviceId = deviceId;
    record.deleted = deleted;
    record.schemaVersion = 1;
    record.payload = [self payloadFromMemo:memo];
    return record;
}

- (FormMemo *)memoFromRecord:(SyncRecord *)record {
    FormMemo *memo = [[FormMemo alloc] init];
    memo.memoID = record.recordID;
    NSDictionary *p = record.payload ?: @{};
    NSString *title = p[@"title"];
    memo.title = [title isKindOfClass:[NSString class]] ? title : @"";
    NSString *host = p[@"host"];
    memo.host = [host isKindOfClass:[NSString class]] ? host.lowercaseString : @"";
    NSString *pathPrefix = p[@"pathPrefix"];
    memo.pathPrefix = [pathPrefix isKindOfClass:[NSString class]] && pathPrefix.length > 0 ? pathPrefix : nil;
    memo.isDefault = [p[@"isDefault"] boolValue];
    if (p[@"waitTimeoutMs"] != nil) {
        memo.waitTimeoutMs = [p[@"waitTimeoutMs"] integerValue];
    }
    memo.updatedAt = (NSTimeInterval)record.updatedAt;
    NSArray *rawFields = p[@"fields"];
    NSMutableArray<FormMemoField *> *fields = [NSMutableArray array];
    if ([rawFields isKindOfClass:[NSArray class]]) {
        for (id item in rawFields) {
            FormMemoField *field = [FormMemoField fieldWithDictionary:item];
            if (field) {
                [fields addObject:field];
            }
        }
    }
    memo.fields = fields;
    return memo;
}

- (NSArray<SyncRecord *> *)exportRecords {
    NSDictionary *meta = [self loadMeta];
    NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (FormMemo *memo in [[FormMemoStore sharedStore] allMemos]) {
        [out addObject:[self recordFromMemo:memo meta:meta]];
        [seen addObject:memo.memoID];
    }
    [meta enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        (void)stop;
        if ([seen containsObject:key]) {
            return;
        }
        if (![obj isKindOfClass:[NSDictionary class]] || ![obj[@"deleted"] boolValue]) {
            return;
        }
        SyncRecord *tomb = [[SyncRecord alloc] init];
        tomb.recordID = key;
        tomb.kind = SyncKindFormMemo;
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
    for (FormMemo *memo in [[FormMemoStore sharedStore] allMemos]) {
        [alive addObject:memo.memoID];
        meta[memo.memoID] = @{
            @"updatedAt": @(MAX(now, (long long)memo.updatedAt)),
            @"deviceId": deviceId,
            @"deleted": @NO,
        };
    }
    NSArray *keys = meta.allKeys;
    for (NSString *key in keys) {
        if ([alive containsObject:key]) {
            continue;
        }
        NSDictionary *m = meta[key];
        if (![m isKindOfClass:[NSDictionary class]] || [m[@"deleted"] boolValue]) {
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
    NSMutableArray<FormMemo *> *active = [NSMutableArray array];
    NSMutableDictionary *newMeta = [NSMutableDictionary dictionary];
    for (SyncRecord *rec in records) {
        if (![rec.kind isEqualToString:SyncKindFormMemo]) {
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
        FormMemo *memo = [self memoFromRecord:rec];
        if (memo.host.length == 0) {
            continue;
        }
        [active addObject:memo];
    }
    NSError *error = nil;
    [[FormMemoStore sharedStore] replaceAllMemos:active error:&error];
    if (error) {
        NSLog(@"[CloudSync] form_memo apply failed: %@", error.localizedDescription);
    }
    [self saveMeta:newMeta];
}

@end
