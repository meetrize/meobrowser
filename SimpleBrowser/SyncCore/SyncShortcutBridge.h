#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

@interface SyncShortcutBridge : NSObject

+ (instancetype)sharedBridge;

/// 导出本地快捷方式（含 tombstone）为 SyncRecord。
- (NSArray<SyncRecord *> *)exportRecords;

/// 用合并后的记录写回 BrowserShortcutStore；applyingRemote 时由 Engine 抑制回环。
- (void)applyMergedRecords:(NSArray<SyncRecord *> *)records;

/// 本地变更后刷新 meta 的 updatedAt / deviceId。
- (void)touchLocalRecordsForUpload;

@end

NS_ASSUME_NONNULL_END
