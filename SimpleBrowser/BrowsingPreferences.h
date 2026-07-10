#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowsingPreferences : NSObject

+ (nullable NSURL *)lastVisitedURL;
+ (void)setLastVisitedURL:(nullable NSURL *)url;
+ (NSURL *)initialURL;

@end

NS_ASSUME_NONNULL_END
