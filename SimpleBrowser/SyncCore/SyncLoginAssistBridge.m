#import "SyncLoginAssistBridge.h"
#import "SyncRecord.h"
#import "SyncKind.h"
#import "SyncDevice.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"

static NSString * const kSyncLoginRecipeMetaKey = @"meo.sync.loginRecipeMeta";
static NSString * const kSyncLoginCredentialMetaKey = @"meo.sync.loginCredentialMeta";
/// PocketBase 唯一索引不含 kind，凭证 record_id 必须与 recipe id 区分。
static NSString * const kCredentialRecordIDPrefix = @"cred:";

@implementation SyncLoginAssistBridge

+ (instancetype)sharedBridge {
    static SyncLoginAssistBridge *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

+ (NSString *)credentialRecordIDForRecipeID:(NSString *)recipeID {
    if (recipeID.length == 0) {
        return @"";
    }
    return [kCredentialRecordIDPrefix stringByAppendingString:recipeID];
}

+ (NSString *)recipeIDFromCredentialRecordID:(NSString *)recordID {
    if (![recordID hasPrefix:kCredentialRecordIDPrefix]) {
        return recordID ?: @"";
    }
    return [recordID substringFromIndex:kCredentialRecordIDPrefix.length];
}

#pragma mark - Meta

- (NSMutableDictionary *)loadMetaForKey:(NSString *)key {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:key];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveMeta:(NSDictionary *)meta forKey:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setObject:meta forKey:key];
}

#pragma mark - Recipe records

- (SyncRecord *)recordFromRecipe:(LoginRecipe *)recipe meta:(NSDictionary *)meta {
    NSDictionary *m = meta[recipe.recipeID];
    long long updatedAt = (long long)recipe.updatedAt;
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
    record.recordID = recipe.recipeID;
    record.kind = SyncKindLoginRecipe;
    record.updatedAt = updatedAt;
    record.deviceId = deviceId;
    record.deleted = deleted;
    record.schemaVersion = 1;
    record.payload = [recipe dictionaryRepresentation];
    return record;
}

- (LoginRecipe *)recipeFromRecord:(SyncRecord *)record {
    NSMutableDictionary *payload = [(record.payload ?: @{}) mutableCopy];
    if (![payload[@"id"] isKindOfClass:[NSString class]] || [payload[@"id"] length] == 0) {
        payload[@"id"] = record.recordID;
    }
    if (payload[@"updatedAt"] == nil) {
        payload[@"updatedAt"] = @(record.updatedAt);
    }
    return [LoginRecipe recipeWithDictionary:payload];
}

#pragma mark - Credential records

- (SyncRecord *)recordFromCredentials:(LoginCredentials *)credentials
                             recipeID:(NSString *)recipeID
                                 meta:(NSDictionary *)meta {
    NSString *recordID = [[self class] credentialRecordIDForRecipeID:recipeID];
    NSDictionary *m = meta[recordID] ?: meta[recipeID];
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
    record.recordID = recordID;
    record.kind = SyncKindLoginCredential;
    record.updatedAt = updatedAt;
    record.deviceId = deviceId;
    record.deleted = deleted;
    record.schemaVersion = 1;
    record.payload = @{
        @"recipeID": recipeID ?: @"",
        @"username": credentials.username ?: @"",
        @"password": credentials.password ?: @"",
        @"phone": credentials.phone ?: @"",
    };
    return record;
}

- (LoginCredentials *)credentialsFromRecord:(SyncRecord *)record {
    NSDictionary *p = record.payload ?: @{};
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = [p[@"username"] isKindOfClass:[NSString class]] ? p[@"username"] : @"";
    credentials.password = [p[@"password"] isKindOfClass:[NSString class]] ? p[@"password"] : @"";
    credentials.phone = [p[@"phone"] isKindOfClass:[NSString class]] ? p[@"phone"] : @"";
    return credentials;
}

#pragma mark - Export / touch / apply

- (NSArray<SyncRecord *> *)exportRecipeRecords {
    NSDictionary *meta = [self loadMetaForKey:kSyncLoginRecipeMetaKey];
    NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LoginRecipe *recipe in [[LoginRecipeStore sharedStore] allRecipes]) {
        [out addObject:[self recordFromRecipe:recipe meta:meta]];
        [seen addObject:recipe.recipeID];
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
        tomb.kind = SyncKindLoginRecipe;
        tomb.updatedAt = [obj[@"updatedAt"] longLongValue];
        tomb.deviceId = [obj[@"deviceId"] isKindOfClass:[NSString class]] ? obj[@"deviceId"] : [SyncDevice deviceId];
        tomb.deleted = YES;
        tomb.schemaVersion = 1;
        tomb.payload = @{@"_tombstone": @YES};
        [out addObject:tomb];
    }];
    return out;
}

- (NSArray<SyncRecord *> *)exportCredentialRecords {
    NSDictionary *meta = [self loadMetaForKey:kSyncLoginCredentialMetaKey];
    NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSDictionary<NSString *, LoginCredentials *> *all = [[LoginCredentialStore sharedStore] allCredentials];
    [all enumerateKeysAndObjectsUsingBlock:^(NSString *recipeID, LoginCredentials *credentials, BOOL *stop) {
        (void)stop;
        SyncRecord *rec = [self recordFromCredentials:credentials recipeID:recipeID meta:meta];
        [out addObject:rec];
        [seen addObject:rec.recordID];
    }];
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
        tomb.kind = SyncKindLoginCredential;
        tomb.updatedAt = [obj[@"updatedAt"] longLongValue];
        tomb.deviceId = [obj[@"deviceId"] isKindOfClass:[NSString class]] ? obj[@"deviceId"] : [SyncDevice deviceId];
        tomb.deleted = YES;
        tomb.schemaVersion = 1;
        tomb.payload = @{@"_tombstone": @YES};
        [out addObject:tomb];
    }];
    return out;
}

- (NSArray<SyncRecord *> *)exportRecords {
    NSMutableArray<SyncRecord *> *out = [NSMutableArray array];
    [out addObjectsFromArray:[self exportRecipeRecords]];
    [out addObjectsFromArray:[self exportCredentialRecords]];
    return out;
}

- (void)touchMetaForAliveIDs:(NSSet<NSString *> *)alive
                     metaKey:(NSString *)metaKey
                   updatedAt:(long long)now
                    deviceId:(NSString *)deviceId {
    NSMutableDictionary *meta = [self loadMetaForKey:metaKey];
    for (NSString *recordID in alive) {
        meta[recordID] = @{
            @"updatedAt": @(now),
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
    [self saveMeta:meta forKey:metaKey];
}

- (void)touchLocalRecordsForUpload {
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    NSString *deviceId = [SyncDevice deviceId];

    NSMutableSet *recipeIDs = [NSMutableSet set];
    for (LoginRecipe *recipe in [[LoginRecipeStore sharedStore] allRecipes]) {
        [recipeIDs addObject:recipe.recipeID];
    }
    [self touchMetaForAliveIDs:recipeIDs metaKey:kSyncLoginRecipeMetaKey updatedAt:now deviceId:deviceId];

    NSMutableSet *credentialRecordIDs = [NSMutableSet set];
    [[[LoginCredentialStore sharedStore] allCredentials] enumerateKeysAndObjectsUsingBlock:^(NSString *recipeID, LoginCredentials *credentials, BOOL *stop) {
        (void)credentials;
        (void)stop;
        NSString *recordID = [[self class] credentialRecordIDForRecipeID:recipeID];
        if (recordID.length > 0) {
            [credentialRecordIDs addObject:recordID];
        }
    }];
    [self touchMetaForAliveIDs:credentialRecordIDs metaKey:kSyncLoginCredentialMetaKey updatedAt:now deviceId:deviceId];
}

- (void)applyMergedRecipeRecords:(NSArray<SyncRecord *> *)records {
    NSMutableArray<LoginRecipe *> *active = [NSMutableArray array];
    NSMutableDictionary *newMeta = [NSMutableDictionary dictionary];
    for (SyncRecord *rec in records) {
        if (![rec.kind isEqualToString:SyncKindLoginRecipe]) {
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
        LoginRecipe *recipe = [self recipeFromRecord:rec];
        if (!recipe || recipe.host.length == 0) {
            continue;
        }
        [active addObject:recipe];
    }
    NSError *error = nil;
    [[LoginRecipeStore sharedStore] replaceAllRecipes:active error:&error];
    if (error) {
        NSLog(@"[Sync] login_recipe apply failed: %@", error.localizedDescription);
    }
    [self saveMeta:newMeta forKey:kSyncLoginRecipeMetaKey];
}

- (void)applyMergedCredentialRecords:(NSArray<SyncRecord *> *)records {
    NSMutableDictionary<NSString *, LoginCredentials *> *active = [NSMutableDictionary dictionary];
    NSMutableDictionary *newMeta = [NSMutableDictionary dictionary];
    for (SyncRecord *rec in records) {
        if (![rec.kind isEqualToString:SyncKindLoginCredential]) {
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
        NSString *recipeID = rec.payload[@"recipeID"];
        if (![recipeID isKindOfClass:[NSString class]] || recipeID.length == 0) {
            recipeID = [[self class] recipeIDFromCredentialRecordID:rec.recordID];
        }
        if (recipeID.length == 0) {
            continue;
        }
        active[recipeID] = [self credentialsFromRecord:rec];
    }
    NSError *error = nil;
    [[LoginCredentialStore sharedStore] replaceAllCredentials:active error:&error];
    if (error) {
        NSLog(@"[Sync] login_credential apply failed: %@", error.localizedDescription);
    }
    [self saveMeta:newMeta forKey:kSyncLoginCredentialMetaKey];
}

- (void)applyMergedRecords:(NSArray<SyncRecord *> *)records {
    // 调用方须传入本模块两种 kind 的完整合并结果；缺省 kind 会清空对应本地表。
    [self applyMergedRecipeRecords:records];
    [self applyMergedCredentialRecords:records];
}

@end
