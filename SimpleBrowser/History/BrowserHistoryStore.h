#import <Foundation/Foundation.h>

@class BrowserHistoryEntry;

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BrowserHistoryStoreDidChangeNotification;

extern NSString * const BrowserHistoryClearOnQuitDefaultsKey;

@interface BrowserHistoryStore : NSObject

+ (instancetype)sharedStore;

/// 记录一次访问。同 URL 合并；2 秒内重复 finish 不增加 visitCount。
- (void)recordURL:(NSURL *)url title:(nullable NSString *)title;

/// SPA 标题晚到时补写（不增加 visitCount）。
- (void)updateTitle:(NSString *)title forURL:(NSURL *)url;

- (NSArray<BrowserHistoryEntry *> *)activeEntriesSortedByVisitTime;

/// 标题 / URL / host 子串匹配；按 visitTime 降序。
- (NSArray<BrowserHistoryEntry *> *)entriesMatchingQuery:(NSString *)query limit:(NSUInteger)limit;

/// 地址栏补全：按匹配度 + visitCount + 近因排序。
- (NSArray<BrowserHistoryEntry *> *)suggestionsMatchingQuery:(NSString *)query limit:(NSUInteger)limit;

- (void)deleteEntryWithID:(NSString *)entryID;
- (void)deleteEntriesForHost:(NSString *)host;
- (void)clearAll;
- (void)clearVisitedSince:(NSTimeInterval)sinceUnix;
- (void)clearVisitedToday;

- (void)flushSynchronously;
- (void)clearIfConfiguredOnQuit;

@property (nonatomic, class, assign) BOOL clearOnQuitEnabled;

@end

NS_ASSUME_NONNULL_END
