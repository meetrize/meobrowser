#import "SyncRecord.h"

@implementation SyncRecord

- (instancetype)init {
    self = [super init];
    if (self) {
        _recordID = @"";
        _kind = @"";
        _updatedAt = 0;
        _deviceId = @"";
        _deleted = NO;
        _schemaVersion = 1;
        _payload = @{};
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    SyncRecord *copy = [[SyncRecord alloc] init];
    copy.recordID = self.recordID;
    copy.kind = self.kind;
    copy.updatedAt = self.updatedAt;
    copy.deviceId = self.deviceId;
    copy.deleted = self.deleted;
    copy.schemaVersion = self.schemaVersion;
    copy.payload = self.payload;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.recordID ?: @"",
        @"kind": self.kind ?: @"",
        @"updatedAt": @(self.updatedAt),
        @"deviceId": self.deviceId ?: @"",
        @"deleted": @(self.deleted),
        @"schemaVersion": @(self.schemaVersion),
        @"payload": self.payload ?: @{},
    };
}

+ (instancetype)recordWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *recordID = dictionary[@"id"];
    if (![recordID isKindOfClass:[NSString class]] || recordID.length == 0) {
        return nil;
    }
    NSString *kind = dictionary[@"kind"];
    if (![kind isKindOfClass:[NSString class]] || kind.length == 0) {
        return nil;
    }
    SyncRecord *record = [[self alloc] init];
    record.recordID = recordID;
    record.kind = kind;
    record.updatedAt = [dictionary[@"updatedAt"] longLongValue];
    NSString *deviceId = dictionary[@"deviceId"];
    record.deviceId = [deviceId isKindOfClass:[NSString class]] ? deviceId : @"";
    record.deleted = [dictionary[@"deleted"] boolValue];
    if (dictionary[@"schemaVersion"] != nil) {
        record.schemaVersion = [dictionary[@"schemaVersion"] integerValue];
    }
    id payload = dictionary[@"payload"];
    if ([payload isKindOfClass:[NSDictionary class]]) {
        record.payload = payload;
    } else {
        // 兼容 Companion 扁平 shortcut 字典：除同步头外的字段作为 payload
        NSMutableDictionary *flat = [dictionary mutableCopy];
        [flat removeObjectForKey:@"id"];
        [flat removeObjectForKey:@"kind"];
        [flat removeObjectForKey:@"updatedAt"];
        [flat removeObjectForKey:@"deviceId"];
        [flat removeObjectForKey:@"deleted"];
        [flat removeObjectForKey:@"schemaVersion"];
        [flat removeObjectForKey:@"payload"];
        // kind 字段在 shortcut payload 里是 link/folder，与 SyncRecord.kind 冲突时：
        // 若顶层 kind 是 shortcut/form_memo，扁平里可能另有 item kind — 上面已移除顶层 kind。
        // Companion export 把 link/folder 放在 @"kind"；此时 SyncRecord.kind 应为 shortcut。
        record.payload = flat;
    }
    return record;
}

@end
