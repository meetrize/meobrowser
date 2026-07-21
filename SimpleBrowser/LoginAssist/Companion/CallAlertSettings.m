#import "CallAlertSettings.h"

static NSString * const kCallAlertEnabledKey = @"MeoCallAlertEnabled";
static NSString * const kCallAlertBannerEnabledKey = @"MeoCallAlertBannerEnabled";
static NSString * const kCallAlertSystemNotifEnabledKey = @"MeoCallAlertSystemNotificationEnabled";

@implementation CallAlertSettings

+ (instancetype)sharedSettings {
    static CallAlertSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (BOOL)alertEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:kCallAlertEnabledKey];
}

- (void)setAlertEnabled:(BOOL)alertEnabled {
    [NSUserDefaults.standardUserDefaults setBool:alertEnabled forKey:kCallAlertEnabledKey];
}

- (BOOL)bannerEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kCallAlertBannerEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kCallAlertBannerEnabledKey];
}

- (void)setBannerEnabled:(BOOL)bannerEnabled {
    [NSUserDefaults.standardUserDefaults setBool:bannerEnabled forKey:kCallAlertBannerEnabledKey];
}

- (BOOL)systemNotificationEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kCallAlertSystemNotifEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kCallAlertSystemNotifEnabledKey];
}

- (void)setSystemNotificationEnabled:(BOOL)systemNotificationEnabled {
    [NSUserDefaults.standardUserDefaults setBool:systemNotificationEnabled
                                          forKey:kCallAlertSystemNotifEnabledKey];
}

@end
