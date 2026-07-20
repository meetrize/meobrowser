#import "PhoneNotificationSettings.h"

static NSString * const kPhoneNotifMirrorEnabledKey = @"MeoPhoneNotificationMirrorEnabled";
static NSString * const kPhoneNotifOTPBannerEnabledKey = @"MeoPhoneNotificationOTPBannerEnabled";

@implementation PhoneNotificationSettings

+ (instancetype)sharedSettings {
    static PhoneNotificationSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (BOOL)mirrorEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kPhoneNotifMirrorEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kPhoneNotifMirrorEnabledKey];
}

- (void)setMirrorEnabled:(BOOL)mirrorEnabled {
    [NSUserDefaults.standardUserDefaults setBool:mirrorEnabled forKey:kPhoneNotifMirrorEnabledKey];
}

- (BOOL)otpBannerEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kPhoneNotifOTPBannerEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kPhoneNotifOTPBannerEnabledKey];
}

- (void)setOtpBannerEnabled:(BOOL)otpBannerEnabled {
    [NSUserDefaults.standardUserDefaults setBool:otpBannerEnabled forKey:kPhoneNotifOTPBannerEnabledKey];
}

@end
