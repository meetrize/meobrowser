#import "LoginAssistPreferences.h"

NSNotificationName const LoginAssistPreferencesDidChangeNotification = @"LoginAssistPreferencesDidChangeNotification";

static NSString * const kInlineAssistEnabledKey = @"LoginAssistInlineAssistEnabled";
static NSString * const kPromptSaveOnSuccessKey = @"LoginAssistPromptSaveOnSuccess";
static NSString * const kSuppressHostsKey = @"LoginAssistSavePromptSuppressHosts";

@implementation LoginAssistPreferences

+ (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LoginAssistPreferencesDidChangeNotification object:nil];
}

+ (BOOL)inlineAssistEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kInlineAssistEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kInlineAssistEnabledKey];
}

+ (void)setInlineAssistEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kInlineAssistEnabledKey];
    [self notifyChanged];
}

+ (BOOL)promptSaveOnSuccess {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kPromptSaveOnSuccessKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kPromptSaveOnSuccessKey];
}

+ (void)setPromptSaveOnSuccess:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kPromptSaveOnSuccessKey];
    [self notifyChanged];
}

+ (NSMutableSet<NSString *> *)suppressHostSet {
    NSArray *arr = [NSUserDefaults.standardUserDefaults arrayForKey:kSuppressHostsKey];
    NSMutableSet *set = [NSMutableSet set];
    if ([arr isKindOfClass:[NSArray class]]) {
        for (id item in arr) {
            if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
                [set addObject:[(NSString *)item lowercaseString]];
            }
        }
    }
    return set;
}

+ (BOOL)shouldSuppressSavePromptForHost:(NSString *)host {
    if (host.length == 0) {
        return NO;
    }
    return [[self suppressHostSet] containsObject:host.lowercaseString];
}

+ (void)setSuppressSavePrompt:(BOOL)suppress forHost:(NSString *)host {
    if (host.length == 0) {
        return;
    }
    NSMutableSet *set = [self suppressHostSet];
    NSString *key = host.lowercaseString;
    if (suppress) {
        [set addObject:key];
    } else {
        [set removeObject:key];
    }
    [NSUserDefaults.standardUserDefaults setObject:set.allObjects forKey:kSuppressHostsKey];
    [self notifyChanged];
}

@end
