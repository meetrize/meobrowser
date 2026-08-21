#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserChromeActionLayoutDidChangeNotification;

/// Chrome 动作区顺序 / 条上可见性（应用级）。不含 moreMenu。
@interface BrowserChromeActionLayoutStore : NSObject

+ (NSArray<NSString *> *)defaultOrderedCustomActionIDs;

/// 默认隐藏（地址栏迁入项）；冷启动 / 首次扩目录时写入。
+ (NSArray<NSString *> *)defaultHiddenCustomActionIDs;

/// 完整用户序（含 hidden）；自动合并目录新增 id、清洗未知 id。
+ (NSArray<NSString *> *)orderedCustomActionIDs;
+ (void)setOrderedCustomActionIDs:(NSArray<NSString *> *)orderedIDs;

+ (NSSet<NSString *> *)hiddenActionIDSet;
+ (BOOL)isActionIDHidden:(NSString *)itemID;
+ (void)setActionID:(NSString *)itemID hidden:(BOOL)hidden;

/// 按 order 过滤后的可见 id（不含 moreMenu）。
+ (NSArray<NSString *> *)visibleCustomActionIDs;

/// 用新的可见子序列替换完整 order 中的可见槽位（hidden 槽位 id 不动）。
+ (NSArray<NSString *> *)orderedIDsByReplacingVisibleSubsequence:(NSArray<NSString *> *)visibleIDs;

/// 将旧地址栏 order/hidden 迁入 Chrome LayoutStore（一次性）。
+ (void)migrateFromAddressBarPreferencesIfNeeded;

@end

NS_ASSUME_NONNULL_END
