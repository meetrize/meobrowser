#import "BrowsingPreferences.h"

static NSString * const kLastVisitedURLKey = @"lastVisitedURL";
static NSString * const kTabSessionKey = @"tabSession";
static NSString * const kTabSessionTabsKey = @"tabs";
static NSString * const kTabSessionSelectedIndexKey = @"selectedIndex";
static NSString * const kDefaultURLString = @"https://example.com";

NSString * const BrowserTabSessionNewTabMarker = @"about:newtab";

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

@end
