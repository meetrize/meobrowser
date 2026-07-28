#import "ServerSyncTransport.h"
#import "ServerSyncAPIClient.h"
#import "ServerSyncSettings.h"
#import "ServerSyncKeychain.h"
#import "SyncRecord.h"

@implementation ServerSyncTransport

+ (instancetype)sharedTransport {
    static ServerSyncTransport *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (SyncRecord *)syncRecordFromPB:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *recordId = item[@"record_id"];
    NSString *kind = item[@"kind"];
    if (![recordId isKindOfClass:[NSString class]] || recordId.length == 0 ||
        ![kind isKindOfClass:[NSString class]] || kind.length == 0) {
        return nil;
    }
    SyncRecord *rec = [[SyncRecord alloc] init];
    rec.recordID = recordId;
    rec.kind = kind;
    rec.updatedAt = [item[@"updated_at"] longLongValue];
    NSString *deviceId = item[@"device_id"];
    rec.deviceId = [deviceId isKindOfClass:[NSString class]] ? deviceId : @"";
    rec.deleted = [item[@"deleted"] boolValue];
    rec.schemaVersion = [item[@"schema_version"] integerValue] ?: 1;
    id payload = item[@"payload"];
    if ([payload isKindOfClass:[NSDictionary class]]) {
        rec.payload = payload;
    } else if ([payload isKindOfClass:[NSString class]]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        rec.payload = [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    } else {
        rec.payload = @{};
    }
    return rec;
}

- (NSDictionary *)pbBodyFromSyncRecord:(SyncRecord *)rec userId:(NSString *)userId {
    return @{
        @"user": userId ?: @"",
        @"app_id": ServerSyncAppId,
        @"record_id": rec.recordID ?: @"",
        @"kind": rec.kind ?: @"",
        @"updated_at": @(rec.updatedAt),
        @"device_id": rec.deviceId ?: @"",
        @"deleted": @(rec.deleted),
        @"schema_version": @(rec.schemaVersion > 0 ? rec.schemaVersion : 1),
        @"payload": rec.payload ?: @{},
    };
}

- (void)fetchPage:(NSInteger)page
      accumulated:(NSMutableArray<SyncRecord *> *)accumulated
            token:(NSString *)token
       completion:(void (^)(NSArray<SyncRecord *> *, NSError *))completion {
    NSString *filter = [NSString stringWithFormat:@"(app_id='%@')", ServerSyncAppId];
    NSString *encoded = [filter stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *path = [NSString stringWithFormat:@"/api/collections/sync_records/records?filter=%@&perPage=200&page=%ld&skipTotal=1",
                      encoded, (long)page];
    [[ServerSyncAPIClient sharedClient] getJSON:path token:token completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSArray *items = json[@"items"];
        if (![items isKindOfClass:[NSArray class]]) {
            completion([accumulated copy], nil);
            return;
        }
        for (id item in items) {
            SyncRecord *rec = [self syncRecordFromPB:item];
            if (rec) {
                [accumulated addObject:rec];
            }
        }
        NSInteger perPage = [json[@"perPage"] integerValue] ?: 200;
        if ((NSInteger)items.count < perPage) {
            completion([accumulated copy], nil);
            return;
        }
        [self fetchPage:page + 1 accumulated:accumulated token:token completion:completion];
    }];
}

- (void)fetchAllRecordsWithCompletion:(void (^)(NSArray<SyncRecord *> *, NSError *))completion {
    NSString *token = [ServerSyncKeychain token];
    if (token.length == 0) {
        completion(nil, [NSError errorWithDomain:@"ServerSyncTransport"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"未登录"}]);
        return;
    }
    [self fetchPage:1 accumulated:[NSMutableArray array] token:token completion:completion];
}

- (void)lookupPBIdForRecordId:(NSString *)recordId
                        token:(NSString *)token
                   completion:(void (^)(NSString * _Nullable pbId, NSError * _Nullable error))completion {
    NSString *filter = [NSString stringWithFormat:@"(app_id='%@' && record_id='%@')", ServerSyncAppId, recordId];
    NSString *encoded = [filter stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *path = [NSString stringWithFormat:@"/api/collections/sync_records/records?filter=%@&perPage=1", encoded];
    [[ServerSyncAPIClient sharedClient] getJSON:path token:token completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSArray *items = json[@"items"];
        if ([items isKindOfClass:[NSArray class]] && items.count > 0) {
            NSDictionary *first = items.firstObject;
            NSString *pbId = first[@"id"];
            completion([pbId isKindOfClass:[NSString class]] ? pbId : nil, nil);
            return;
        }
        completion(nil, nil);
    }];
}

- (void)upsertRecords:(NSArray<SyncRecord *> *)records
           completion:(void (^)(NSError *))completion {
    NSString *token = [ServerSyncKeychain token];
    NSString *userId = ServerSyncSettings.sharedSettings.userId;
    if (token.length == 0 || userId.length == 0) {
        completion([NSError errorWithDomain:@"ServerSyncTransport"
                                       code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"未登录"}]);
        return;
    }
    if (records.count == 0) {
        completion(nil);
        return;
    }
    [self upsertRecords:records index:0 token:token userId:userId completion:completion];
}

- (void)upsertRecords:(NSArray<SyncRecord *> *)records
                index:(NSUInteger)index
                token:(NSString *)token
               userId:(NSString *)userId
           completion:(void (^)(NSError *))completion {
    if (index >= records.count) {
        completion(nil);
        return;
    }
    SyncRecord *rec = records[index];
    NSDictionary *body = [self pbBodyFromSyncRecord:rec userId:userId];
    [self lookupPBIdForRecordId:rec.recordID token:token completion:^(NSString *pbId, NSError *lookupError) {
        if (lookupError) {
            completion(lookupError);
            return;
        }
        void (^next)(NSError *) = ^(NSError *err) {
            if (err) {
                completion(err);
                return;
            }
            [self upsertRecords:records index:index + 1 token:token userId:userId completion:completion];
        };
        if (pbId.length > 0) {
            NSString *path = [NSString stringWithFormat:@"/api/collections/sync_records/records/%@", pbId];
            [[ServerSyncAPIClient sharedClient] patchJSON:path body:body token:token completion:^(NSDictionary *json, NSError *error) {
                (void)json;
                next(error);
            }];
        } else {
            [[ServerSyncAPIClient sharedClient] postJSON:@"/api/collections/sync_records/records"
                                                    body:body
                                                   token:token
                                              completion:^(NSDictionary *json, NSError *error) {
                (void)json;
                next(error);
            }];
        }
    }];
}

@end
