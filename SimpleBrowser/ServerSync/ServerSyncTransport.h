#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

@interface ServerSyncTransport : NSObject

+ (instancetype)sharedTransport;

- (void)fetchAllRecordsWithCompletion:(void (^)(NSArray<SyncRecord *> * _Nullable records, NSError * _Nullable error))completion;

- (void)upsertRecords:(NSArray<SyncRecord *> *)records
           completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
