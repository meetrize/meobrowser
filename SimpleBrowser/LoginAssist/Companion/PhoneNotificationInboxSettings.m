#import "PhoneNotificationInboxSettings.h"

static NSString * const kInboxEnabledKey = @"MeoPhoneNotificationInboxEnabled";
static NSString * const kOTPToInboxKey = @"MeoPhoneNotificationOTPToInbox";
static NSString * const kRetentionDaysKey = @"MeoPhoneNotificationInboxRetentionDays";
static NSString * const kAutoMarkReadKey = @"MeoPhoneNotificationInboxAutoMarkRead";
static NSString * const kSidebarWidthKey = @"MeoPhoneNotificationInboxSidebarWidth";

static const CGFloat kDefaultSidebarWidth = 360.0;
static const CGFloat kMinSidebarWidth = 320.0;
static const CGFloat kMaxSidebarWidth = 560.0;

@implementation PhoneNotificationInboxSettings

+ (instancetype)sharedSettings {
    static PhoneNotificationInboxSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (BOOL)inboxEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kInboxEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kInboxEnabledKey];
}

- (void)setInboxEnabled:(BOOL)inboxEnabled {
    [NSUserDefaults.standardUserDefaults setBool:inboxEnabled forKey:kInboxEnabledKey];
}

- (BOOL)otpToInbox {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kOTPToInboxKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kOTPToInboxKey];
}

- (void)setOtpToInbox:(BOOL)otpToInbox {
    [NSUserDefaults.standardUserDefaults setBool:otpToInbox forKey:kOTPToInboxKey];
}

- (NSInteger)retentionDays {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kRetentionDaysKey] == nil) {
        return 7;
    }
    NSInteger days = [defaults integerForKey:kRetentionDaysKey];
    return days < 0 ? 7 : days;
}

- (void)setRetentionDays:(NSInteger)retentionDays {
    [NSUserDefaults.standardUserDefaults setInteger:MAX(0, retentionDays) forKey:kRetentionDaysKey];
}

- (BOOL)autoMarkReadOnVisible {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kAutoMarkReadKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kAutoMarkReadKey];
}

- (void)setAutoMarkReadOnVisible:(BOOL)autoMarkReadOnVisible {
    [NSUserDefaults.standardUserDefaults setBool:autoMarkReadOnVisible forKey:kAutoMarkReadKey];
}

- (CGFloat)sidebarWidth {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kSidebarWidthKey] == nil) {
        return kDefaultSidebarWidth;
    }
    CGFloat width = [defaults doubleForKey:kSidebarWidthKey];
    // 超出新范围时钳制到边界，避免旧值被整段重置成默认
    return MIN(kMaxSidebarWidth, MAX(kMinSidebarWidth, width));
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat clamped = MIN(kMaxSidebarWidth, MAX(kMinSidebarWidth, sidebarWidth));
    [NSUserDefaults.standardUserDefaults setDouble:clamped forKey:kSidebarWidthKey];
}

@end
