#import "BrowserLocationPreferences.h"

NSNotificationName const BrowserLocationPreferencesDidChangeNotification =
    @"BrowserLocationPreferencesDidChangeNotification";

static NSString * const kGeolocationEnabledKey = @"MeoGeolocationEnabled";

@implementation BrowserLocationPreferences

+ (instancetype)sharedPreferences {
    static BrowserLocationPreferences *prefs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[self alloc] init];
    });
    return prefs;
}

- (BOOL)geolocationEnabled {
    NSNumber *value = [NSUserDefaults.standardUserDefaults objectForKey:kGeolocationEnabledKey];
    // 未配置时默认开启，避免闲鱼等站只查 permissions.query 就提示「请开启地理位置」。
    if (value == nil) {
        return YES;
    }
    return value.boolValue;
}

- (void)setGeolocationEnabled:(BOOL)geolocationEnabled {
    [NSUserDefaults.standardUserDefaults setBool:geolocationEnabled forKey:kGeolocationEnabledKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserLocationPreferencesDidChangeNotification
                                                        object:self];
}

@end
