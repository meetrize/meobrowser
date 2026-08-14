#import "BrowserDeveloperPreferences.h"

NSNotificationName const BrowserDeveloperPreferencesDidChangeNotification =
    @"BrowserDeveloperPreferencesDidChangeNotification";

static NSString * const kAllowWebInspectionKey = @"MeoBrowserAllowWebInspection";

@implementation BrowserDeveloperPreferences

+ (instancetype)sharedPreferences {
    static BrowserDeveloperPreferences *prefs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[self alloc] init];
    });
    return prefs;
}

- (BOOL)allowWebInspection {
    return [NSUserDefaults.standardUserDefaults boolForKey:kAllowWebInspectionKey];
}

- (void)setAllowWebInspection:(BOOL)allowWebInspection {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kAllowWebInspectionKey] == allowWebInspection &&
        [defaults objectForKey:kAllowWebInspectionKey] != nil) {
        return;
    }
    [defaults setBool:allowWebInspection forKey:kAllowWebInspectionKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserDeveloperPreferencesDidChangeNotification
                                                        object:self];
}

@end
