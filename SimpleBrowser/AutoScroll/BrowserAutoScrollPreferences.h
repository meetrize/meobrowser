#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserAutoScrollPreferencesDidChangeNotification;

@interface BrowserAutoScrollPreferences : NSObject

/// 像素/秒，范围 20～500，默认 80。
+ (CGFloat)speedPxPerSec;
+ (void)setSpeedPxPerSec:(CGFloat)speed;

@end

NS_ASSUME_NONNULL_END
