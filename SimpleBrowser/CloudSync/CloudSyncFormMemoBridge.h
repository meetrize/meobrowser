#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

@interface CloudSyncFormMemoBridge : NSObject

+ (instancetype)sharedBridge;

- (NSArray<SyncRecord *> *)exportRecords;
- (void)applyMergedRecords:(NSArray<SyncRecord *> *)records;
- (void)touchLocalRecordsForUpload;

@end

NS_ASSUME_NONNULL_END
