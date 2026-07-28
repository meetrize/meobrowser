#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

/// CloudKit 私有库传输。macOS 14+ 使用 CKDatabase 拉取/写入 MeoSyncRecord（与 CKSyncEngine 同库，实现更适合 ObjC Makefile 工程）。
@interface CloudSyncTransport : NSObject

+ (instancetype)sharedTransport;

@property (nonatomic, readonly, getter=isAvailable) BOOL available;

- (void)fetchAllSyncRecordsWithCompletion:(void (^)(NSArray<SyncRecord *> * _Nullable records, NSError * _Nullable error))completion;

- (void)saveSyncRecords:(NSArray<SyncRecord *> *)records
             completion:(void (^)(NSError * _Nullable error))completion;

- (void)deleteAllMeoSyncRecordsWithCompletion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
