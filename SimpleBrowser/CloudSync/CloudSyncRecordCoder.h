#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CloudSyncRecordType;

@interface CloudSyncRecordCoder : NSObject

+ (nullable CKRecord *)cloudKitRecordFromSyncRecord:(SyncRecord *)syncRecord;
+ (nullable SyncRecord *)syncRecordFromCloudKitRecord:(CKRecord *)ckRecord;

@end

NS_ASSUME_NONNULL_END
