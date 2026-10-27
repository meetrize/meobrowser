#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

/// 登录助手 Recipe + 帐号密码 → SyncRecord（两种 kind，同一设置开关）。
@interface SyncLoginAssistBridge : NSObject

+ (instancetype)sharedBridge;

- (NSArray<SyncRecord *> *)exportRecords;
- (void)applyMergedRecords:(NSArray<SyncRecord *> *)records;
- (void)touchLocalRecordsForUpload;

@end

NS_ASSUME_NONNULL_END
