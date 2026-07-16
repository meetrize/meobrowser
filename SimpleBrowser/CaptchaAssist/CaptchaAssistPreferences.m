#import "CaptchaAssistPreferences.h"

static NSString * const kCaptchaAssistEnabledKey = @"MeoBrowser.CaptchaAssist.enabled";
static NSString * const kCaptchaAssistMaxSessionsKey = @"MeoBrowser.CaptchaAssist.maxSessions";

@implementation CaptchaAssistPreferences

+ (BOOL)assistEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kCaptchaAssistEnabledKey] == nil) {
        return NO; // 默认关
    }
    return [defaults boolForKey:kCaptchaAssistEnabledKey];
}

+ (void)setAssistEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kCaptchaAssistEnabledKey];
}

+ (NSInteger)maxSessionCount {
    NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:kCaptchaAssistMaxSessionsKey];
    return n > 0 ? n : 20;
}

+ (void)setMaxSessionCount:(NSInteger)count {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(1, count) forKey:kCaptchaAssistMaxSessionsKey];
}

@end
