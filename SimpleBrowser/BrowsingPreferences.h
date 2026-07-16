#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserTabSessionNewTabMarker;

extern NSString * const BrowserSearchEngineDuckDuckGo;
extern NSString * const BrowserSearchEngineGoogle;
extern NSString * const BrowserSearchEngineBing;
extern NSString * const BrowserSearchEngineBaidu;

/// 窗口会话字典键（tabs / selectedIndex / pinnedCount / frame）。
extern NSString * const BrowserWindowSessionTabsKey;
extern NSString * const BrowserWindowSessionSelectedIndexKey;
extern NSString * const BrowserWindowSessionPinnedCountKey;
extern NSString * const BrowserWindowSessionFrameKey;

@interface BrowsingPreferences : NSObject

+ (nullable NSURL *)lastVisitedURL;
+ (void)setLastVisitedURL:(nullable NSURL *)url;
+ (NSURL *)initialURL;

+ (BOOL)isPersistableURL:(nullable NSURL *)url;
+ (nullable NSArray<NSString *> *)savedTabEntries;
+ (NSInteger)savedSelectedTabIndex;
/// 会话中前 N 个标签为固定标签；旧会话缺省为 0。
+ (NSUInteger)savedPinnedTabCount;
+ (void)saveTabEntries:(NSArray<NSString *> *)entries
         selectedIndex:(NSInteger)selectedIndex
           pinnedCount:(NSUInteger)pinnedCount;

/// 多窗口会话：每项为窗口字典。无 `windowSession` 时从旧 `tabSession` 迁移为单窗数组。
+ (NSArray<NSDictionary *> *)savedWindowSessions;
+ (void)saveWindowSessions:(NSArray<NSDictionary *> *)sessions;

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSearchEngines;
+ (NSString *)defaultSearchEngineID;
+ (void)setDefaultSearchEngineID:(NSString *)engineID;
+ (NSString *)displayNameForSearchEngineID:(NSString *)engineID;
+ (nullable NSURL *)searchURLForQuery:(NSString *)query;

+ (BOOL)isDefaultBrowser;
+ (void)requestSetAsDefaultBrowserWithCompletion:(void (^)(NSError * _Nullable error))completion;

/// 清除 WebKit 网站数据与共享 URL 缓存；completion 在主线程。
+ (void)clearWebsiteDataWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;

/// 仅清除与 host 匹配的网站数据记录（不删 Recipe/Keychain）；completion 在主线程。
+ (void)clearWebsiteDataForHost:(NSString *)host
                     completion:(void (^ _Nullable)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
