#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserTabSessionNewTabMarker;

@interface BrowsingPreferences : NSObject

+ (nullable NSURL *)lastVisitedURL;
+ (void)setLastVisitedURL:(nullable NSURL *)url;
+ (NSURL *)initialURL;

+ (BOOL)isPersistableURL:(nullable NSURL *)url;
+ (nullable NSArray<NSString *> *)savedTabEntries;
+ (NSInteger)savedSelectedTabIndex;
+ (void)saveTabEntries:(NSArray<NSString *> *)entries selectedIndex:(NSInteger)selectedIndex;

@end

NS_ASSUME_NONNULL_END
