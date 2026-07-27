#import "FormMemoPreferences.h"

NSNotificationName const FormMemoPreferencesDidChangeNotification = @"FormMemoPreferencesDidChangeNotification";

static NSString * const kInlineSaveEnabledKey = @"FormMemoInlineSaveEnabled";
static NSString * const kHasCompletedInlineSaveOnceKey = @"FormMemoHasCompletedInlineSaveOnce";

@implementation FormMemoPreferences

+ (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:FormMemoPreferencesDidChangeNotification object:nil];
}

+ (BOOL)inlineSaveEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kInlineSaveEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kInlineSaveEnabledKey];
}

+ (void)setInlineSaveEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kInlineSaveEnabledKey];
    [self notifyChanged];
}

+ (BOOL)hasCompletedInlineSaveOnce {
    return [NSUserDefaults.standardUserDefaults boolForKey:kHasCompletedInlineSaveOnceKey];
}

+ (void)setHasCompletedInlineSaveOnce:(BOOL)done {
    [NSUserDefaults.standardUserDefaults setBool:done forKey:kHasCompletedInlineSaveOnceKey];
}

@end
