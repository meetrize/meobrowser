#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserTabSessionNewTabMarker;

extern NSString * const BrowserSearchEngineDuckDuckGo;
extern NSString * const BrowserSearchEngineGoogle;
extern NSString * const BrowserSearchEngineBing;
extern NSString * const BrowserSearchEngineBaidu;

@interface BrowsingPreferences : NSObject

+ (nullable NSURL *)lastVisitedURL;
+ (void)setLastVisitedURL:(nullable NSURL *)url;
+ (NSURL *)initialURL;

+ (BOOL)isPersistableURL:(nullable NSURL *)url;
+ (nullable NSArray<NSString *> *)savedTabEntries;
+ (NSInteger)savedSelectedTabIndex;
+ (void)saveTabEntries:(NSArray<NSString *> *)entries selectedIndex:(NSInteger)selectedIndex;

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSearchEngines;
+ (NSString *)defaultSearchEngineID;
+ (void)setDefaultSearchEngineID:(NSString *)engineID;
+ (NSString *)displayNameForSearchEngineID:(NSString *)engineID;
+ (nullable NSURL *)searchURLForQuery:(NSString *)query;

+ (BOOL)isDefaultBrowser;
+ (void)requestSetAsDefaultBrowserWithCompletion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
