#import "ServerSyncSettings.h"

NSNotificationName const ServerSyncSettingsDidChangeNotification = @"ServerSyncSettingsDidChangeNotification";
NSNotificationName const ServerSyncEngineStateDidChangeNotification = @"ServerSyncEngineStateDidChangeNotification";
NSString * const ServerSyncAppId = @"meobrowser";

static NSString * const kBaseURLKey = @"meo.serverSync.baseURL";
static NSString * const kEmailKey = @"meo.serverSync.email";
static NSString * const kEnabledKey = @"meo.serverSync.enabled";
static NSString * const kShortcutKey = @"meo.serverSync.shortcutEnabled";
static NSString * const kFormMemoKey = @"meo.serverSync.formMemoEnabled";
static NSString * const kLastSyncKey = @"meo.serverSync.lastSyncAt";
static NSString * const kLastErrorKey = @"meo.serverSync.lastErrorMessage";
static NSString * const kDidApplyDefaultsKey = @"meo.serverSync.didApplyDefaultKinds";
static NSString * const kUserIdKey = @"meo.serverSync.userId";

@implementation ServerSyncSettings

+ (instancetype)sharedSettings {
    static ServerSyncSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (NSUserDefaults *)defaults {
    return NSUserDefaults.standardUserDefaults;
}

- (NSString *)baseURL {
    return [self.defaults stringForKey:kBaseURLKey] ?: @"";
}

- (void)setBaseURL:(NSString *)baseURL {
    NSString *v = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    while ([v hasSuffix:@"/"]) {
        v = [v substringToIndex:v.length - 1];
    }
    if ([v isEqualToString:self.baseURL]) {
        return;
    }
    [self.defaults setObject:v forKey:kBaseURLKey];
    [self postChange];
}

- (NSString *)email {
    return [self.defaults stringForKey:kEmailKey] ?: @"";
}

- (void)setEmail:(NSString *)email {
    NSString *v = email ?: @"";
    if ([v isEqualToString:self.email]) {
        return;
    }
    [self.defaults setObject:v forKey:kEmailKey];
    [self postChange];
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
    [self.defaults setBool:formMemoEnabled forKey:kFormMemoKey];
    [self postChange];
}

- (NSTimeInterval)lastSyncAt {
    return [self.defaults doubleForKey:kLastSyncKey];
}

- (void)setLastSyncAt:(NSTimeInterval)lastSyncAt {
    [self.defaults setDouble:lastSyncAt forKey:kLastSyncKey];
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

- (NSString *)userId {
    return [self.defaults stringForKey:kUserIdKey];
}

- (void)setUserId:(NSString *)userId {
    if (userId.length == 0) {
        [self.defaults removeObjectForKey:kUserIdKey];
    } else {
        [self.defaults setObject:userId forKey:kUserIdKey];
    }
}

- (void)enableWithDefaultKindsIfNeeded {
    if (self.didApplyDefaultKinds) {
        return;
    }
    [self.defaults setBool:YES forKey:kShortcutKey];
    [self.defaults setBool:YES forKey:kFormMemoKey];
    self.didApplyDefaultKinds = YES;
}

- (NSURL *)normalizedBaseURL {
    NSString *raw = [self.baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (raw.length == 0) {
        return nil;
    }
    if (![raw containsString:@"://"]) {
        raw = [@"http://" stringByAppendingString:raw];
    }
    return [NSURL URLWithString:raw];
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:ServerSyncSettingsDidChangeNotification object:self];
}

@end
