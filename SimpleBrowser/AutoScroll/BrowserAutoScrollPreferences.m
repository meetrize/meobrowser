#import "BrowserAutoScrollPreferences.h"

NSNotificationName const BrowserAutoScrollPreferencesDidChangeNotification =
    @"BrowserAutoScrollPreferencesDidChangeNotification";

static NSString * const kSpeedKey = @"BrowserAutoScrollSpeedPxPerSec";
static const CGFloat kDefaultSpeed = 80.0;
static const CGFloat kMinSpeed = 20.0;
static const CGFloat kMaxSpeed = 500.0;

@implementation BrowserAutoScrollPreferences

+ (CGFloat)clampSpeed:(CGFloat)speed {
    if (!(speed == speed)) {
        return kDefaultSpeed;
    }
    return MAX(kMinSpeed, MIN(kMaxSpeed, speed));
}

+ (CGFloat)speedPxPerSec {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kSpeedKey]) {
        return kDefaultSpeed;
    }
    return [self clampSpeed:[defaults doubleForKey:kSpeedKey]];
}

+ (void)setSpeedPxPerSec:(CGFloat)speed {
    CGFloat clamped = [self clampSpeed:speed];
    [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:kSpeedKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserAutoScrollPreferencesDidChangeNotification
                                                        object:nil];
}

@end
