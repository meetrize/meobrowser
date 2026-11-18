#import "BrowserTranslationPreferences.h"

NSNotificationName const BrowserTranslationPreferencesDidChangeNotification =
    @"BrowserTranslationPreferencesDidChangeNotification";

NSString * const BrowserTranslationProviderIndexTranslate = @"indexTranslate";
NSString * const BrowserTranslationProviderMTran = @"mtran";
NSString * const BrowserTranslationProviderGoogle = @"google";
NSString * const BrowserTranslationDefaultIndexTranslateBaseURL = @"https://index-translate.bilibili.com/v1";
NSString * const BrowserTranslationDefaultMTranBaseURL = @"http://192.168.31.111:8989";
NSString * const BrowserTranslationDefaultIndexTranslateModel = @"Index-Translate-2B";

static NSString * const kProviderKey = @"MeoBrowser.Translation.provider";
static NSString * const kAPIBaseURLKey = @"MeoBrowser.Translation.apiBaseURL";
static NSString * const kAPITokenKey = @"MeoBrowser.Translation.apiToken";
static NSString * const kModelKey = @"MeoBrowser.Translation.model";
static NSString * const kMigratedDefaultToIndexKey = @"MeoBrowser.Translation.migratedDefaultToIndexTranslate";

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
    return @[
        BrowserTranslationProviderIndexTranslate,
        BrowserTranslationProviderMTran,
        BrowserTranslationProviderGoogle,
    ];
}

+ (NSString *)displayNameForProvider:(NSString *)provider {
    if ([provider isEqualToString:BrowserTranslationProviderGoogle]) {
        return @"Google（在线）";
    }
    if ([provider isEqualToString:BrowserTranslationProviderMTran]) {
        return @"MTranServer";
    }
    return @"Index-Translate（默认）";
}

+ (NSString *)defaultAPIBaseURLForProvider:(NSString *)provider {
    if ([provider isEqualToString:BrowserTranslationProviderMTran]) {
        return BrowserTranslationDefaultMTranBaseURL;
    }
    if ([provider isEqualToString:BrowserTranslationProviderIndexTranslate]) {
        return BrowserTranslationDefaultIndexTranslateBaseURL;
    }
    return BrowserTranslationDefaultIndexTranslateBaseURL;
}

+ (NSArray<NSString *> *)availableIndexTranslateModels {
    return @[
        @"Index-Translate-2B",
        @"Index-Translate-9B",
        @"Index-Translate-35B-A3B",
    ];
}

+ (NSString *)displayNameForIndexTranslateModel:(NSString *)model {
    if ([model isEqualToString:@"Index-Translate-9B"]) {
        return @"Index-Translate-9B（均衡）";
    }
    if ([model isEqualToString:@"Index-Translate-35B-A3B"]) {
        return @"Index-Translate-35B（旗舰）";
    }
    return @"Index-Translate-2B（快速）";
}

+ (BOOL)isValidProvider:(NSString *)provider {
    return [provider isEqualToString:BrowserTranslationProviderIndexTranslate]
        || [provider isEqualToString:BrowserTranslationProviderMTran]
        || [provider isEqualToString:BrowserTranslationProviderGoogle];
}

+ (BOOL)isValidIndexTranslateModel:(NSString *)model {
    return [[self availableIndexTranslateModels] containsObject:model ?: @""];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        NSString *provider = [ud stringForKey:kProviderKey];
        NSString *base = [ud stringForKey:kAPIBaseURLKey];
        NSString *token = [ud stringForKey:kAPITokenKey] ?: @"";
        NSString *model = [ud stringForKey:kModelKey];

        // 一次性：仍停在出厂 MTran 默认时，切到更快的 Index-Translate-2B 公开 API。
        if (![ud boolForKey:kMigratedDefaultToIndexKey]) {
            [ud setBool:YES forKey:kMigratedDefaultToIndexKey];
            BOOL stockMTran = (provider.length == 0
                               || [provider isEqualToString:BrowserTranslationProviderMTran])
                && (base.length == 0
                    || [base isEqualToString:BrowserTranslationDefaultMTranBaseURL]);
            if (stockMTran) {
                provider = BrowserTranslationProviderIndexTranslate;
                base = BrowserTranslationDefaultIndexTranslateBaseURL;
                [ud setObject:provider forKey:kProviderKey];
                [ud setObject:base forKey:kAPIBaseURLKey];
            }
        }

        if (![BrowserTranslationPreferences isValidProvider:provider]) {
            provider = BrowserTranslationProviderIndexTranslate;
        }
        _provider = [provider copy];

        if (base.length == 0) {
            base = [BrowserTranslationPreferences defaultAPIBaseURLForProvider:_provider];
        }
        _apiBaseURL = [base copy];
        _apiToken = [token copy];

        if (![BrowserTranslationPreferences isValidIndexTranslateModel:model]) {
            model = BrowserTranslationDefaultIndexTranslateModel;
        }
        _model = [model copy];
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserTranslationPreferencesDidChangeNotification
                                                        object:self];
}

- (void)setProvider:(NSString *)provider {
    NSString *normalized = BrowserTranslationProviderIndexTranslate;
    if ([provider isEqualToString:BrowserTranslationProviderGoogle]) {
        normalized = BrowserTranslationProviderGoogle;
    } else if ([provider isEqualToString:BrowserTranslationProviderMTran]) {
        normalized = BrowserTranslationProviderMTran;
    } else if ([provider isEqualToString:BrowserTranslationProviderIndexTranslate]) {
        normalized = BrowserTranslationProviderIndexTranslate;
    }

    NSString *oldProvider = _provider;
    if ([oldProvider isEqualToString:normalized]) {
        return;
    }

    // 若地址仍是旧后端默认值，切到新后端默认，避免把 MTran 局域网地址带给 Index。
    NSString *oldDefault = [BrowserTranslationPreferences defaultAPIBaseURLForProvider:oldProvider];
    BOOL shouldSwapBase = [_apiBaseURL isEqualToString:oldDefault]
        || _apiBaseURL.length == 0
        || ([oldProvider isEqualToString:BrowserTranslationProviderGoogle]);
    _provider = [normalized copy];
    [NSUserDefaults.standardUserDefaults setObject:_provider forKey:kProviderKey];

    if (shouldSwapBase
        && ([normalized isEqualToString:BrowserTranslationProviderIndexTranslate]
            || [normalized isEqualToString:BrowserTranslationProviderMTran])) {
        NSString *newDefault = [BrowserTranslationPreferences defaultAPIBaseURLForProvider:normalized];
        if (![newDefault isEqualToString:_apiBaseURL]) {
            _apiBaseURL = [newDefault copy];
            [NSUserDefaults.standardUserDefaults setObject:_apiBaseURL forKey:kAPIBaseURLKey];
        }
    }
    [self notify];
}

- (void)setApiBaseURL:(NSString *)apiBaseURL {
    NSString *trimmed = [[apiBaseURL ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    if (trimmed.length == 0) {
        trimmed = [BrowserTranslationPreferences defaultAPIBaseURLForProvider:self.provider];
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

- (void)setModel:(NSString *)model {
    NSString *normalized = BrowserTranslationDefaultIndexTranslateModel;
    if ([BrowserTranslationPreferences isValidIndexTranslateModel:model]) {
        normalized = model;
    }
    if ([_model isEqualToString:normalized]) {
        return;
    }
    _model = [normalized copy];
    [NSUserDefaults.standardUserDefaults setObject:_model forKey:kModelKey];
    [self notify];
}

- (NSString *)normalizedAPIBaseURL {
    NSString *base = self.apiBaseURL;
    NSString *fallback = [BrowserTranslationPreferences defaultAPIBaseURLForProvider:self.provider];
    if (base.length == 0) {
        return fallback;
    }
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    return base.length > 0 ? base : fallback;
}

@end
