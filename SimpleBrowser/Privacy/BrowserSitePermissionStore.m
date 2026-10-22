#import "BrowserSitePermissionStore.h"

static NSString * const kGeolocationPermissionsKey = @"MeoSiteGeolocationPermissions";
static NSString * const kNotificationPermissionsKey = @"MeoSiteNotificationPermissions";
static NSString * const kDecisionAllow = @"allow";
static NSString * const kDecisionDeny = @"deny";

@implementation BrowserSitePermissionStore

+ (instancetype)sharedStore {
    static BrowserSitePermissionStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (nullable NSString *)normalizedHostFromString:(nullable NSString *)host {
    NSString *trimmed = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    NSString *normalized = trimmed.lowercaseString;
    if ([normalized hasPrefix:@"www."]) {
        normalized = [normalized substringFromIndex:4];
    }
    return normalized;
}

- (NSMutableDictionary<NSString *, NSString *> *)geolocationMap {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kGeolocationPermissionsKey];
    if (![stored isKindOfClass:[NSDictionary class]]) {
        return [NSMutableDictionary dictionary];
    }
    return [stored mutableCopy];
}

- (void)saveGeolocationMap:(NSDictionary<NSString *, NSString *> *)map {
    [NSUserDefaults.standardUserDefaults setObject:map forKey:kGeolocationPermissionsKey];
}

- (BrowserSitePermissionDecision)geolocationDecisionForHost:(NSString *)host {
    NSString *normalized = [[self class] normalizedHostFromString:host];
    if (normalized.length == 0) {
        return BrowserSitePermissionDecisionUnknown;
    }
    NSString *value = [self geolocationMap][normalized];
    if ([value isEqualToString:kDecisionAllow]) {
        return BrowserSitePermissionDecisionAllow;
    }
    if ([value isEqualToString:kDecisionDeny]) {
        return BrowserSitePermissionDecisionDeny;
    }
    return BrowserSitePermissionDecisionUnknown;
}

- (void)setGeolocationDecision:(BrowserSitePermissionDecision)decision forHost:(NSString *)host {
    NSString *normalized = [[self class] normalizedHostFromString:host];
    if (normalized.length == 0) {
        return;
    }
    NSMutableDictionary *map = [self geolocationMap];
    switch (decision) {
        case BrowserSitePermissionDecisionAllow:
            map[normalized] = kDecisionAllow;
            break;
        case BrowserSitePermissionDecisionDeny:
            map[normalized] = kDecisionDeny;
            break;
        case BrowserSitePermissionDecisionUnknown:
            [map removeObjectForKey:normalized];
            break;
    }
    [self saveGeolocationMap:map];
}

- (void)removeGeolocationDecisionForHost:(NSString *)host {
    [self setGeolocationDecision:BrowserSitePermissionDecisionUnknown forHost:host];
}

- (void)removeAllGeolocationDecisions {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kGeolocationPermissionsKey];
}

#pragma mark - Notification

- (NSMutableDictionary<NSString *, NSString *> *)notificationMap {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kNotificationPermissionsKey];
    if (![stored isKindOfClass:[NSDictionary class]]) {
        return [NSMutableDictionary dictionary];
    }
    return [stored mutableCopy];
}

- (void)saveNotificationMap:(NSDictionary<NSString *, NSString *> *)map {
    [NSUserDefaults.standardUserDefaults setObject:map forKey:kNotificationPermissionsKey];
}

- (BrowserSitePermissionDecision)notificationDecisionForHost:(NSString *)host {
    NSString *normalized = [[self class] normalizedHostFromString:host];
    if (normalized.length == 0) {
        return BrowserSitePermissionDecisionUnknown;
    }
    NSString *value = [self notificationMap][normalized];
    if ([value isEqualToString:kDecisionAllow]) {
        return BrowserSitePermissionDecisionAllow;
    }
    if ([value isEqualToString:kDecisionDeny]) {
        return BrowserSitePermissionDecisionDeny;
    }
    return BrowserSitePermissionDecisionUnknown;
}

- (void)setNotificationDecision:(BrowserSitePermissionDecision)decision forHost:(NSString *)host {
    NSString *normalized = [[self class] normalizedHostFromString:host];
    if (normalized.length == 0) {
        return;
    }
    NSMutableDictionary *map = [self notificationMap];
    switch (decision) {
        case BrowserSitePermissionDecisionAllow:
            map[normalized] = kDecisionAllow;
            break;
        case BrowserSitePermissionDecisionDeny:
            map[normalized] = kDecisionDeny;
            break;
        case BrowserSitePermissionDecisionUnknown:
            [map removeObjectForKey:normalized];
            break;
    }
    [self saveNotificationMap:map];
}

- (void)removeNotificationDecisionForHost:(NSString *)host {
    [self setNotificationDecision:BrowserSitePermissionDecisionUnknown forHost:host];
}

- (void)removeAllNotificationDecisions {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kNotificationPermissionsKey];
}

@end
