#import <Foundation/Foundation.h>

@class SyncRecord;

NS_ASSUME_NONNULL_BEGIN

@interface SyncMerger : NSObject

/// 若 incoming 应覆盖 local（或 local 为 nil）返回 YES。
+ (BOOL)incomingWins:(SyncRecord *)incoming local:(nullable SyncRecord *)local;

/// 将 incoming 数组合并进以 recordID 为键的本地映射；返回合并后的全部记录。
+ (NSArray<SyncRecord *> *)mergeIncoming:(NSArray<SyncRecord *> *)incoming
                              intoLocal:(NSArray<SyncRecord *> *)local;

/// 去掉 updatedAt 早于 now-30d 的 tombstone；返回保留列表。
+ (NSArray<SyncRecord *> *)purgeExpiredTombstones:(NSArray<SyncRecord *> *)records
                                              now:(long long)nowUnix;

@end

NS_ASSUME_NONNULL_END
