#import "CloudSyncTransport.h"
#import "CloudSyncSettings.h"
#import "CloudSyncRecordCoder.h"
#import "CloudSyncCapability.h"
#import "SyncRecord.h"
#import <CloudKit/CloudKit.h>

static NSString * const kIndexRecordType = @"MeoSyncIndex";
static NSString * const kIndexRecordName = @"meo-sync-index-v1";

@implementation CloudSyncTransport

+ (instancetype)sharedTransport {
    static CloudSyncTransport *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (BOOL)isAvailable {
    return [CloudSyncCapability isCloudKitEntitled];
}

- (NSError *)unavailableError {
    return [NSError errorWithDomain:@"CloudSyncTransport"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: [CloudSyncCapability unavailableReason]}];
}

- (CKDatabase *)privateDatabase API_AVAILABLE(macos(10.10)) {
    CKContainer *container = [CKContainer containerWithIdentifier:CloudSyncContainerIdentifier];
    return container.privateCloudDatabase;
}

- (CKRecordID *)indexRecordID {
    return [[CKRecordID alloc] initWithRecordName:kIndexRecordName];
}

- (void)fetchAllSyncRecordsWithCompletion:(void (^)(NSArray<SyncRecord *> *, NSError *))completion {
    if (![self isAvailable]) {
        completion(nil, [self unavailableError]);
        return;
    }
    if (@available(macOS 14.0, *)) {
        CKDatabase *db = [self privateDatabase];
        [db fetchRecordWithID:[self indexRecordID] completionHandler:^(CKRecord *indexRecord, NSError *error) {
            if (error) {
                // 尚无索引：视为空库
                if ([error.domain isEqualToString:CKErrorDomain] && error.code == CKErrorUnknownItem) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(@[], nil);
                    });
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }
            NSArray<NSString *> *names = [self recordNamesFromIndexRecord:indexRecord];
            if (names.count == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@[], nil);
                });
                return;
            }
            NSMutableArray<CKRecordID *> *ids = [NSMutableArray arrayWithCapacity:names.count];
            for (NSString *name in names) {
                [ids addObject:[[CKRecordID alloc] initWithRecordName:name]];
            }
            CKFetchRecordsOperation *fetchOp = [[CKFetchRecordsOperation alloc] initWithRecordIDs:ids];
            NSMutableDictionary<CKRecordID *, CKRecord *> *recordsByID = [NSMutableDictionary dictionary];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            fetchOp.perRecordCompletionBlock = ^(CKRecord *record, CKRecordID *recordID, NSError *error) {
                (void)error;
                if (record && recordID) {
                    recordsByID[recordID] = record;
                }
            };
            fetchOp.fetchRecordsCompletionBlock = ^(NSDictionary<CKRecordID *, CKRecord *> *records, NSError *operationError) {
                if (records.count > 0) {
                    [recordsByID addEntriesFromDictionary:records];
                }
                NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
                [recordsByID enumerateKeysAndObjectsUsingBlock:^(CKRecordID *key, CKRecord *obj, BOOL *stop) {
                    (void)key;
                    (void)stop;
                    SyncRecord *sync = [CloudSyncRecordCoder syncRecordFromCloudKitRecord:obj];
                    if (sync) {
                        [out addObject:sync];
                    }
                }];
                if (operationError && out.count == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, operationError);
                    });
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(out, nil);
                });
            };
#pragma clang diagnostic pop
            [db addOperation:fetchOp];
        }];
    } else {
        completion(nil, [self unavailableError]);
    }
}

- (NSArray<NSString *> *)recordNamesFromIndexRecord:(CKRecord *)indexRecord {
    NSString *json = indexRecord[@"recordNamesJSON"];
    if (![json isKindOfClass:[NSString class]] || json.length == 0) {
        return @[];
    }
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id item in (NSArray *)obj) {
        if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
            [names addObject:item];
        }
    }
    return names;
}

- (CKRecord *)indexRecordWithNames:(NSArray<NSString *> *)names {
    CKRecord *record = [[CKRecord alloc] initWithRecordType:kIndexRecordType recordID:[self indexRecordID]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:names ?: @[] options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
    record[@"recordNamesJSON"] = json;
    return record;
}

- (void)saveSyncRecords:(NSArray<SyncRecord *> *)records
             completion:(void (^)(NSError *))completion {
    if (![self isAvailable]) {
        completion([self unavailableError]);
        return;
    }
    if (@available(macOS 14.0, *)) {
        NSMutableArray<CKRecord *> *ckRecords = [NSMutableArray array];
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (SyncRecord *rec in records) {
            CKRecord *ck = [CloudSyncRecordCoder cloudKitRecordFromSyncRecord:rec];
            if (ck) {
                [ckRecords addObject:ck];
                [names addObject:rec.recordID];
            }
        }
        [ckRecords addObject:[self indexRecordWithNames:names]];

        CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:ckRecords
                                                                             recordIDsToDelete:nil];
        op.savePolicy = CKRecordSaveAllKeys;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        op.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> *savedRecords, NSArray<CKRecordID *> *deletedRecordIDs, NSError *operationError) {
            (void)savedRecords;
            (void)deletedRecordIDs;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(operationError);
            });
        };
#pragma clang diagnostic pop
        [[self privateDatabase] addOperation:op];
    } else {
        completion([self unavailableError]);
    }
}

- (void)deleteAllMeoSyncRecordsWithCompletion:(void (^)(NSError *))completion {
    if (![self isAvailable]) {
        completion([self unavailableError]);
        return;
    }
    if (@available(macOS 14.0, *)) {
        [self fetchAllSyncRecordsWithCompletion:^(NSArray<SyncRecord *> *records, NSError *error) {
            if (error) {
                completion(error);
                return;
            }
            NSMutableArray<CKRecordID *> *ids = [NSMutableArray array];
            for (SyncRecord *rec in records) {
                [ids addObject:[[CKRecordID alloc] initWithRecordName:rec.recordID]];
            }
            [ids addObject:[self indexRecordID]];
            if (ids.count == 0) {
                completion(nil);
                return;
            }
            CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:nil
                                                                                 recordIDsToDelete:ids];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            op.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> *savedRecords, NSArray<CKRecordID *> *deletedRecordIDs, NSError *operationError) {
                (void)savedRecords;
                (void)deletedRecordIDs;
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(operationError);
                });
            };
#pragma clang diagnostic pop
            [[self privateDatabase] addOperation:op];
        }];
    } else {
        completion([self unavailableError]);
    }
}

@end
