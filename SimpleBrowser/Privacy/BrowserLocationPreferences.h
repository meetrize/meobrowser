#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserLocationPreferencesDidChangeNotification;

/// 浏览器地理定位总开关（UserDefaults，默认关）。
@interface BrowserLocationPreferences : NSObject

+ (instancetype)sharedPreferences;

/// 是否允许网站请求定位（默认 NO）。
@property (nonatomic, assign) BOOL geolocationEnabled;

@end

NS_ASSUME_NONNULL_END
