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
    return [NSUserDefaults.standardUserDefaults boolForKey:kGeolocationEnabledKey];
}

- (void)setGeolocationEnabled:(BOOL)geolocationEnabled {
    [NSUserDefaults.standardUserDefaults setBool:geolocationEnabled forKey:kGeolocationEnabledKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserLocationPreferencesDidChangeNotification
                                                        object:self];
}

@end
