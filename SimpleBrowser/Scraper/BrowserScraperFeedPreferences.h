#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserScraperFeedPreferencesDidChangeNotification;

@interface BrowserScraperFeedPreferences : NSObject

@property (class, readonly, strong) BrowserScraperFeedPreferences *sharedPreferences;

/// 默认 YES：浏览器启动时自动开启本机 RSS API
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
/// 默认 3922
@property (nonatomic, assign) NSInteger port;

@end

NS_ASSUME_NONNULL_END
