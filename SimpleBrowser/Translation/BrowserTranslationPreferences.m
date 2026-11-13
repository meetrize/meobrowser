#import "BrowserTranslationPreferences.h"

NSNotificationName const BrowserTranslationPreferencesDidChangeNotification =
    @"BrowserTranslationPreferencesDidChangeNotification";

NSString * const BrowserTranslationProviderMTran = @"mtran";
NSString * const BrowserTranslationProviderGoogle = @"google";
NSString * const BrowserTranslationDefaultMTranBaseURL = @"http://192.168.31.111:8989";

static NSString * const kProviderKey = @"MeoBrowser.Translation.provider";
static NSString * const kAPIBaseURLKey = @"MeoBrowser.Translation.apiBaseURL";
static NSString * const kAPITokenKey = @"MeoBrowser.Translation.apiToken";

@implementation BrowserTranslationPreferences

+ (instancetype)sharedPreferences {
    static BrowserTranslationPreferences *prefs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[self alloc] init];
    });
    return prefs;
}

+ (NSArray<NSString *> *)availableProviders {
    return @[ BrowserTranslationProviderMTran, BrowserTranslationProviderGoogle ];
}

+ (NSString *)displayNameForProvider:(NSString *)provider {
    if ([provider isEqualToString:BrowserTranslationProviderGoogle]) {
        return @"Google（在线）";
    }
    return @"MTranServer";
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        NSString *provider = [ud stringForKey:kProviderKey];
        if (![provider isEqualToString:BrowserTranslationProviderGoogle] &&
            ![provider isEqualToString:BrowserTranslationProviderMTran]) {
            provider = BrowserTranslationProviderMTran;
        }
        _provider = [provider copy];

        NSString *base = [ud stringForKey:kAPIBaseURLKey];
        if (base.length == 0) {
            base = BrowserTranslationDefaultMTranBaseURL;
        }
        _apiBaseURL = [base copy];
        _apiToken = [ud stringForKey:kAPITokenKey] ?: @"";
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserTranslationPreferencesDidChangeNotification
                                                        object:self];
}

- (void)setProvider:(NSString *)provider {
    NSString *normalized = BrowserTranslationProviderMTran;
    if ([provider isEqualToString:BrowserTranslationProviderGoogle]) {
        normalized = BrowserTranslationProviderGoogle;
    } else if ([provider isEqualToString:BrowserTranslationProviderMTran]) {
        normalized = BrowserTranslationProviderMTran;
    }
    if ([_provider isEqualToString:normalized]) {
        return;
    }
    _provider = [normalized copy];
    [NSUserDefaults.standardUserDefaults setObject:_provider forKey:kProviderKey];
    [self notify];
}

- (void)setApiBaseURL:(NSString *)apiBaseURL {
    NSString *trimmed = [[apiBaseURL ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    if (trimmed.length == 0) {
        trimmed = BrowserTranslationDefaultMTranBaseURL;
    }
    if ([_apiBaseURL isEqualToString:trimmed]) {
        return;
    }
    _apiBaseURL = trimmed;
    [NSUserDefaults.standardUserDefaults setObject:_apiBaseURL forKey:kAPIBaseURLKey];
    [self notify];
}

- (void)setApiToken:(NSString *)apiToken {
    NSString *t = apiToken ?: @"";
    if ([_apiToken isEqualToString:t]) {
        return;
    }
    _apiToken = [t copy];
    [NSUserDefaults.standardUserDefaults setObject:_apiToken forKey:kAPITokenKey];
    [self notify];
}

- (NSString *)normalizedAPIBaseURL {
    NSString *base = self.apiBaseURL;
    if (base.length == 0) {
        return BrowserTranslationDefaultMTranBaseURL;
    }
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    return base.length > 0 ? base : BrowserTranslationDefaultMTranBaseURL;
}

@end
