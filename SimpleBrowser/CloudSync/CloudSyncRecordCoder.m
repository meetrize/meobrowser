#import "CloudSyncRecordCoder.h"
#import "SyncRecord.h"

NSString * const CloudSyncRecordType = @"MeoSyncRecord";

@implementation CloudSyncRecordCoder

+ (CKRecord *)cloudKitRecordFromSyncRecord:(SyncRecord *)syncRecord {
    if (syncRecord.recordID.length == 0 || syncRecord.kind.length == 0) {
        return nil;
    }
    CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:syncRecord.recordID];
    CKRecord *record = [[CKRecord alloc] initWithRecordType:CloudSyncRecordType recordID:rid];
    record[@"kind"] = syncRecord.kind;
    record[@"updatedAt"] = @(syncRecord.updatedAt);
    record[@"deviceId"] = syncRecord.deviceId ?: @"";
    record[@"deleted"] = @(syncRecord.deleted ? 1 : 0);
    record[@"schemaVersion"] = @(syncRecord.schemaVersion);
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(syncRecord.payload ?: @{})
                                                   options:0
                                                     error:&jsonError];
    if (!data) {
        return nil;
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    record[@"payloadJSON"] = json ?: @"{}";
    return record;
}

+ (SyncRecord *)syncRecordFromCloudKitRecord:(CKRecord *)ckRecord {
    if (![ckRecord.recordType isEqualToString:CloudSyncRecordType]) {
        return nil;
    }
    NSString *kind = ckRecord[@"kind"];
    if (![kind isKindOfClass:[NSString class]] || kind.length == 0) {
        return nil;
    }
    SyncRecord *record = [[SyncRecord alloc] init];
    record.recordID = ckRecord.recordID.recordName;
    record.kind = kind;
    record.updatedAt = [ckRecord[@"updatedAt"] longLongValue];
    NSString *deviceId = ckRecord[@"deviceId"];
    record.deviceId = [deviceId isKindOfClass:[NSString class]] ? deviceId : @"";
    record.deleted = [ckRecord[@"deleted"] integerValue] != 0;
    record.schemaVersion = [ckRecord[@"schemaVersion"] integerValue] ?: 1;
    NSString *json = ckRecord[@"payloadJSON"];
    if ([json isKindOfClass:[NSString class]] && json.length > 0) {
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            record.payload = obj;
        } else {
            record.payload = @{};
        }
    } else {
        record.payload = @{};
    }
    return record;
}

@end
