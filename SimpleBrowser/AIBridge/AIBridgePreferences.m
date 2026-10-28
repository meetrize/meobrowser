#import "AIBridgePreferences.h"

NSNotificationName const AIBridgePreferencesDidChangeNotification = @"AIBridgePreferencesDidChangeNotification";

static NSString * const kPortKey = @"AIBridge.port";
static NSString * const kTokenKey = @"AIBridge.bearerToken";
static NSString * const kEnabledKey = @"AIBridge.serverEnabled";

@implementation AIBridgePreferences

+ (AIBridgePreferences *)sharedPreferences {
    static AIBridgePreferences *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[AIBridgePreferences alloc] init];
    });
    return prefs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        NSInteger port = [ud integerForKey:kPortKey];
        _port = (port > 0 && port <= 65535) ? port : 3921;
        _bearerToken = [ud stringForKey:kTokenKey] ?: @"";
        _serverEnabled = [ud boolForKey:kEnabledKey];
        [self ensureToken];
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:AIBridgePreferencesDidChangeNotification object:self];
}

- (void)setPort:(NSInteger)port {
    if (port < 1 || port > 65535) {
        port = 3921;
    }
    if (_port == port) {
        return;
    }
    _port = port;
    [NSUserDefaults.standardUserDefaults setInteger:port forKey:kPortKey];
    [self notify];
}

- (void)setBearerToken:(NSString *)bearerToken {
    NSString *t = bearerToken ?: @"";
    if ([_bearerToken isEqualToString:t]) {
        return;
    }
    _bearerToken = [t copy];
    [NSUserDefaults.standardUserDefaults setObject:_bearerToken forKey:kTokenKey];
    [self notify];
}

- (void)setServerEnabled:(BOOL)serverEnabled {
    if (_serverEnabled == serverEnabled) {
        return;
    }
    _serverEnabled = serverEnabled;
    [NSUserDefaults.standardUserDefaults setBool:serverEnabled forKey:kEnabledKey];
    [self notify];
}

- (void)ensureToken {
    if (self.bearerToken.length >= 16) {
        return;
    }
    [self regenerateToken];
}

- (void)regenerateToken {
    NSUUID *u1 = [NSUUID UUID];
    NSUUID *u2 = [NSUUID UUID];
    NSString *raw = [[NSString stringWithFormat:@"%@%@", u1.UUIDString, u2.UUIDString]
        stringByReplacingOccurrencesOfString:@"-" withString:@""];
    self.bearerToken = [raw lowercaseString];
}

@end
