#import "AIBridgePreferences.h"

NSNotificationName const AIBridgePreferencesDidChangeNotification = @"AIBridgePreferencesDidChangeNotification";

static NSString * const kPortKey = @"AIBridge.port";
static NSString * const kTokenKey = @"AIBridge.bearerToken";
static NSString * const kEnabledKey = @"AIBridge.serverEnabled";
static NSString * const kOllamaKey = @"AIBridge.ollamaBaseURL";
static NSString * const kOpenAIBaseKey = @"AIBridge.openaiBaseURL";
static NSString * const kOpenAIKeyKey = @"AIBridge.openaiApiKey";

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
        NSString *ollama = [ud stringForKey:kOllamaKey];
        _ollamaBaseURL = ollama.length ? ollama : @"http://127.0.0.1:11434/v1";
        _openaiBaseURL = [ud stringForKey:kOpenAIBaseKey] ?: @"";
        _openaiApiKey = [ud stringForKey:kOpenAIKeyKey] ?: @"";
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

- (void)setOllamaBaseURL:(NSString *)ollamaBaseURL {
    NSString *t = ollamaBaseURL ?: @"";
    if ([_ollamaBaseURL isEqualToString:t]) {
        return;
    }
    _ollamaBaseURL = [t copy];
    [NSUserDefaults.standardUserDefaults setObject:_ollamaBaseURL forKey:kOllamaKey];
    [self notify];
}

- (void)setOpenaiBaseURL:(NSString *)openaiBaseURL {
    NSString *t = openaiBaseURL ?: @"";
    if ([_openaiBaseURL isEqualToString:t]) {
        return;
    }
    _openaiBaseURL = [t copy];
    [NSUserDefaults.standardUserDefaults setObject:_openaiBaseURL forKey:kOpenAIBaseKey];
    [self notify];
}

- (void)setOpenaiApiKey:(NSString *)openaiApiKey {
    NSString *t = openaiApiKey ?: @"";
    if ([_openaiApiKey isEqualToString:t]) {
        return;
    }
    _openaiApiKey = [t copy];
    [NSUserDefaults.standardUserDefaults setObject:_openaiApiKey forKey:kOpenAIKeyKey];
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
