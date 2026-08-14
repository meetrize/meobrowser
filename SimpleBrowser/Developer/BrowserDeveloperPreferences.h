#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserDeveloperPreferencesDidChangeNotification;

/// 开发者相关偏好（UserDefaults）。
@interface BrowserDeveloperPreferences : NSObject

+ (instancetype)sharedPreferences;

/// 是否允许网页检查（WKWebView.inspectable）。默认 NO。
@property (nonatomic, assign) BOOL allowWebInspection;

@end

NS_ASSUME_NONNULL_END
