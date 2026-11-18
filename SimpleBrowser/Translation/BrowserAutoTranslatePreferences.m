#import "BrowserAutoTranslatePreferences.h"

NSNotificationName const BrowserAutoTranslatePreferencesDidChangeNotification =
    @"BrowserAutoTranslatePreferencesDidChangeNotification";

static NSString * const kAlwaysEnglishKey = @"MeoBrowser.AutoTranslate.alwaysTranslateEnglish";
static NSString * const kEnabledHostsKey = @"MeoBrowser.AutoTranslate.enabledHosts";
static NSString * const kDisabledHostsKey = @"MeoBrowser.AutoTranslate.disabledHosts";

@interface BrowserAutoTranslatePreferences ()
@property (nonatomic, strong) NSMutableSet<NSString *> *enabledHosts;
@property (nonatomic, strong) NSMutableSet<NSString *> *disabledHosts;
@end

@implementation BrowserAutoTranslatePreferences

+ (instancetype)sharedPreferences {
    static BrowserAutoTranslatePreferences *prefs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[self alloc] init];
    });
    return prefs;
}

+ (nullable NSString *)normalizedHostFromURL:(NSURL *)url {
    NSString *host = url.host;
    if (host.length == 0) {
        return nil;
    }
    host = host.lowercaseString;
    if ([host hasPrefix:@"www."] && host.length > 4) {
        host = [host substringFromIndex:4];
    }
    return host.length > 0 ? host : nil;
}

+ (BOOL)isForeignLanguageWorthAutoTranslating:(NSString *)pageLanguage {
    if (pageLanguage.length == 0) {
        return NO;
    }
    NSString *primary = [[pageLanguage componentsSeparatedByString:@"-"].firstObject lowercaseString] ?: @"";
    if (primary.length == 0) {
        return NO;
    }
    // 中文页面不自动译。
    if ([primary isEqualToString:@"zh"] || [primary hasPrefix:@"zh"]) {
        return NO;
    }
    // 常见应译语言；未知短码也当作外语（用户开了「所有英文」时由调用方配合）。
    static NSSet<NSString *> *known = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        known = [NSSet setWithArray:@[
            @"en", @"ja", @"ko", @"fr", @"de", @"es", @"it", @"pt", @"ru",
            @"ar", @"vi", @"th", @"id", @"ms", @"nl", @"pl", @"tr", @"sv",
            @"da", @"fi", @"no", @"nb", @"cs", @"el", @"he", @"hi", @"uk",
        ]];
    });
    return [known containsObject:primary];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        _alwaysTranslateEnglish = [ud boolForKey:kAlwaysEnglishKey];
        NSArray *enabled = [ud arrayForKey:kEnabledHostsKey];
        NSArray *disabled = [ud arrayForKey:kDisabledHostsKey];
        _enabledHosts = [NSMutableSet setWithArray:([enabled isKindOfClass:[NSArray class]] ? enabled : @[])];
        _disabledHosts = [NSMutableSet setWithArray:([disabled isKindOfClass:[NSArray class]] ? disabled : @[])];
    }
    return self;
}

- (void)persist {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:self.alwaysTranslateEnglish forKey:kAlwaysEnglishKey];
    [ud setObject:self.enabledHosts.allObjects forKey:kEnabledHostsKey];
    [ud setObject:self.disabledHosts.allObjects forKey:kDisabledHostsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserAutoTranslatePreferencesDidChangeNotification
                                                        object:self];
}

- (void)setAlwaysTranslateEnglish:(BOOL)alwaysTranslateEnglish {
    if (_alwaysTranslateEnglish == alwaysTranslateEnglish) {
        return;
    }
    _alwaysTranslateEnglish = alwaysTranslateEnglish;
    [self persist];
}

- (BOOL)isHostExplicitlyEnabled:(NSString *)host {
    return host.length > 0 && [self.enabledHosts containsObject:host];
}

- (BOOL)isHostExplicitlyDisabled:(NSString *)host {
    return host.length > 0 && [self.disabledHosts containsObject:host];
}

- (BOOL)shouldAutoTranslateURL:(NSURL *)url pageLanguage:(NSString *)pageLanguage {
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:url];
    if (host.length == 0) {
        return NO;
    }
    if ([self.disabledHosts containsObject:host]) {
        return NO;
    }
    if ([self.enabledHosts containsObject:host]) {
        return YES;
    }
    if (self.alwaysTranslateEnglish) {
        // 明确英文，或启发式判为外语（非中文）。
        NSString *primary = [[pageLanguage componentsSeparatedByString:@"-"].firstObject lowercaseString] ?: @"";
        if ([primary isEqualToString:@"en"]) {
            return YES;
        }
        return [BrowserAutoTranslatePreferences isForeignLanguageWorthAutoTranslating:pageLanguage];
    }
    return NO;
}

- (BOOL)isAutoTranslateCheckedForURL:(NSURL *)url pageLanguage:(NSString *)pageLanguage {
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:url];
    if (host.length == 0) {
        return NO;
    }
    if ([self.disabledHosts containsObject:host]) {
        return NO;
    }
    if ([self.enabledHosts containsObject:host]) {
        return YES;
    }
    // 勾选展示：全英文开启时，对已知英文/外语页显示已勾；语言未知时不勾，避免误导。
    if (self.alwaysTranslateEnglish) {
        NSString *primary = [[pageLanguage componentsSeparatedByString:@"-"].firstObject lowercaseString] ?: @"";
        if ([primary isEqualToString:@"en"]) {
            return YES;
        }
        return [BrowserAutoTranslatePreferences isForeignLanguageWorthAutoTranslating:pageLanguage];
    }
    return NO;
}

- (void)enableAutoTranslateForURL:(NSURL *)url {
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:url];
    if (host.length == 0) {
        return;
    }
    [self.disabledHosts removeObject:host];
    [self.enabledHosts addObject:host];
    [self persist];
}

- (void)disableAutoTranslateForURL:(NSURL *)url {
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:url];
    if (host.length == 0) {
        return;
    }
    [self.enabledHosts removeObject:host];
    [self.disabledHosts addObject:host];
    [self persist];
}

@end
