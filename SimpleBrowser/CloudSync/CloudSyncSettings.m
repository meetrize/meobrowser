#import "CloudSyncSettings.h"

NSNotificationName const CloudSyncSettingsDidChangeNotification = @"CloudSyncSettingsDidChangeNotification";
NSNotificationName const CloudSyncEngineStateDidChangeNotification = @"CloudSyncEngineStateDidChangeNotification";
NSString * const CloudSyncContainerIdentifier = @"iCloud.com.example.MeoBrowser";

static NSString * const kEnabledKey = @"meo.icloudSync.enabled";
static NSString * const kShortcutKey = @"meo.icloudSync.shortcutEnabled";
static NSString * const kFormMemoKey = @"meo.icloudSync.formMemoEnabled";
static NSString * const kLastSyncKey = @"meo.icloudSync.lastSyncAt";
static NSString * const kLastErrorKey = @"meo.icloudSync.lastErrorMessage";
static NSString * const kDidApplyDefaultsKey = @"meo.icloudSync.didApplyDefaultKinds";

@implementation CloudSyncSettings

+ (instancetype)sharedSettings {
    static CloudSyncSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (NSUserDefaults *)defaults {
    return NSUserDefaults.standardUserDefaults;
}

- (BOOL)enabled {
    return [self.defaults boolForKey:kEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    if (self.enabled == enabled) {
        return;
    }
    [self.defaults setBool:enabled forKey:kEnabledKey];
    if (enabled) {
        [self enableWithDefaultKindsIfNeeded];
    }
    [self postChange];
}

- (BOOL)shortcutEnabled {
    if (![self.defaults objectForKey:kShortcutKey]) {
        return YES;
    }
    return [self.defaults boolForKey:kShortcutKey];
}

- (void)setShortcutEnabled:(BOOL)shortcutEnabled {
    if (self.shortcutEnabled == shortcutEnabled) {
        return;
    }
    [self.defaults setBool:shortcutEnabled forKey:kShortcutKey];
    [self postChange];
}

- (BOOL)formMemoEnabled {
    if (![self.defaults objectForKey:kFormMemoKey]) {
        return YES;
    }
    return [self.defaults boolForKey:kFormMemoKey];
}

- (void)setFormMemoEnabled:(BOOL)formMemoEnabled {
    if (self.formMemoEnabled == formMemoEnabled) {
        return;
    }
    [self.defaults setBool:formMemoEnabled forKey:kFormMemoKey];
    [self postChange];
}

- (NSTimeInterval)lastSyncAt {
    return [self.defaults doubleForKey:kLastSyncKey];
}

- (void)setLastSyncAt:(NSTimeInterval)lastSyncAt {
    [self.defaults setDouble:lastSyncAt forKey:kLastSyncKey];
    // 不广播 SettingsDidChange，避免 Engine 重入同步
}

- (NSString *)lastErrorMessage {
    return [self.defaults stringForKey:kLastErrorKey];
}

- (void)setLastErrorMessage:(NSString *)lastErrorMessage {
    if (lastErrorMessage.length == 0) {
        [self.defaults removeObjectForKey:kLastErrorKey];
    } else {
        [self.defaults setObject:lastErrorMessage forKey:kLastErrorKey];
    }
}

- (BOOL)didApplyDefaultKinds {
    return [self.defaults boolForKey:kDidApplyDefaultsKey];
}

- (void)setDidApplyDefaultKinds:(BOOL)didApplyDefaultKinds {
    [self.defaults setBool:didApplyDefaultKinds forKey:kDidApplyDefaultsKey];
}

- (void)enableWithDefaultKindsIfNeeded {
    if (self.didApplyDefaultKinds) {
        return;
    }
    [self.defaults setBool:YES forKey:kShortcutKey];
    [self.defaults setBool:YES forKey:kFormMemoKey];
    self.didApplyDefaultKinds = YES;
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:CloudSyncSettingsDidChangeNotification object:self];
}

@end
