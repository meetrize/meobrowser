#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CompanionShortcutSync : NSObject

+ (instancetype)sharedSync;

/// 将 Android/Mac sync records 合并进本地 Launchpad，并返回导出用 records（含 tombstone）
- (void)mergeShortcutRecords:(NSArray<NSDictionary *> *)records;
- (NSArray<NSDictionary *> *)exportShortcutRecords;

@end

NS_ASSUME_NONNULL_END
