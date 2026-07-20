#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 轻量历史/书签同步存储（UserDefaults JSON），供 V3 sync 使用。
@interface CompanionBrowseSyncStore : NSObject

+ (instancetype)sharedStore;

- (void)mergeRecords:(NSArray<NSDictionary *> *)records kind:(NSString *)kind;
- (NSArray<NSDictionary *> *)exportRecordsForKind:(NSString *)kind;

@end

NS_ASSUME_NONNULL_END
