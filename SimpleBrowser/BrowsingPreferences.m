#import "BrowsingPreferences.h"

static NSString * const kLastVisitedURLKey = @"lastVisitedURL";
static NSString * const kTabSessionKey = @"tabSession";
static NSString * const kTabSessionTabsKey = @"tabs";
static NSString * const kTabSessionSelectedIndexKey = @"selectedIndex";
static NSString * const kDefaultURLString = @"https://example.com";
static NSString * const kDefaultSearchEngineKey = @"defaultSearchEngineID";

NSString * const BrowserTabSessionNewTabMarker = @"about:newtab";
NSString * const BrowserSearchEngineDuckDuckGo = @"duckduckgo";
NSString * const BrowserSearchEngineGoogle = @"google";
NSString * const BrowserSearchEngineBing = @"bing";
NSString * const BrowserSearchEngineBaidu = @"baidu";

@implementation BrowsingPreferences

+ (NSURL *)initialURL {
    NSURL *lastURL = [self lastVisitedURL];
    return lastURL ?: [NSURL URLWithString:kDefaultURLString];
}

+ (nullable NSURL *)lastVisitedURL {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kLastVisitedURLKey];
    if (value.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:value];
}

+ (void)setLastVisitedURL:(nullable NSURL *)url {
    if (![self isPersistableURL:url]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:url.absoluteString forKey:kLastVisitedURLKey];
}

+ (BOOL)isPersistableURL:(nullable NSURL *)url {
    if (!url) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    return url.host.length > 0;
}

+ (nullable NSArray<NSString *> *)savedTabEntries {
    NSDictionary *session = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kTabSessionKey];
    NSArray *tabs = session[kTabSessionTabsKey];
    if ([tabs isKindOfClass:[NSArray class]] && tabs.count > 0) {
        return tabs;
    }

    NSString *legacyURL = [[NSUserDefaults standardUserDefaults] stringForKey:kLastVisitedURLKey];
    if (legacyURL.length > 0) {
        return @[legacyURL];
    }
    return nil;
}

+ (NSInteger)savedSelectedTabIndex {
    NSDictionary *session = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kTabSessionKey];
    NSNumber *index = session[kTabSessionSelectedIndexKey];
    if ([index isKindOfClass:[NSNumber class]]) {
        return index.integerValue;
    }
    return 0;
}

+ (void)saveTabEntries:(NSArray<NSString *> *)entries selectedIndex:(NSInteger)selectedIndex {
    if (entries.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTabSessionKey];
        return;
    }

    NSInteger clampedIndex = MAX(0, MIN(selectedIndex, (NSInteger)entries.count - 1));
    NSDictionary *session = @{
        kTabSessionTabsKey: entries,
        kTabSessionSelectedIndexKey: @(clampedIndex),
    };
    [[NSUserDefaults standardUserDefaults] setObject:session forKey:kTabSessionKey];

    NSString *selectedEntry = entries[(NSUInteger)clampedIndex];
    if (![selectedEntry isEqualToString:BrowserTabSessionNewTabMarker]) {
        NSURL *url = [NSURL URLWithString:selectedEntry];
        [self setLastVisitedURL:url];
    }
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSearchEngines {
    return @[
        @{@"id": BrowserSearchEngineDuckDuckGo, @"name": @"DuckDuckGo"},
        @{@"id": BrowserSearchEngineGoogle, @"name": @"Google"},
        @{@"id": BrowserSearchEngineBing, @"name": @"Bing"},
        @{@"id": BrowserSearchEngineBaidu, @"name": @"百度"},
    ];
}

+ (NSDictionary<NSString *, NSString *> *)searchURLTemplates {
    return @{
        BrowserSearchEngineDuckDuckGo: @"https://duckduckgo.com/?q=%@",
        BrowserSearchEngineGoogle: @"https://www.google.com/search?q=%@",
        BrowserSearchEngineBing: @"https://www.bing.com/search?q=%@",
        BrowserSearchEngineBaidu: @"https://www.baidu.com/s?wd=%@",
    };
}

+ (NSString *)defaultSearchEngineID {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultSearchEngineKey];
    if (stored.length == 0) {
        return BrowserSearchEngineDuckDuckGo;
    }
    if ([self searchURLTemplates][stored]) {
        return stored;
    }
    return BrowserSearchEngineDuckDuckGo;
}

+ (void)setDefaultSearchEngineID:(NSString *)engineID {
    if (![self searchURLTemplates][engineID]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:engineID forKey:kDefaultSearchEngineKey];
}

+ (NSString *)displayNameForSearchEngineID:(NSString *)engineID {
    for (NSDictionary *engine in [self availableSearchEngines]) {
        if ([engine[@"id"] isEqualToString:engineID]) {
            return engine[@"name"];
        }
    }
    return @"DuckDuckGo";
}

+ (nullable NSURL *)searchURLForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    NSString *encoded = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!encoded) {
        return nil;
    }
    NSString *template = [self searchURLTemplates][[self defaultSearchEngineID]];
    if (!template) {
        template = [self searchURLTemplates][BrowserSearchEngineDuckDuckGo];
    }
    return [NSURL URLWithString:[NSString stringWithFormat:template, encoded]];
}

@end
