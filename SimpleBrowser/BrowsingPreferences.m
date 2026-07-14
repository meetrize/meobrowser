#import "BrowsingPreferences.h"
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#import <WebKit/WebKit.h>

static NSString * const kLastVisitedURLKey = @"lastVisitedURL";
static NSString * const kTabSessionKey = @"tabSession";
static NSString * const kTabSessionTabsKey = @"tabs";
static NSString * const kTabSessionSelectedIndexKey = @"selectedIndex";
static NSString * const kTabSessionPinnedCountKey = @"pinnedCount";
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

+ (NSUInteger)savedPinnedTabCount {
    NSDictionary *session = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kTabSessionKey];
    NSNumber *count = session[kTabSessionPinnedCountKey];
    if (![count isKindOfClass:[NSNumber class]]) {
        return 0;
    }
    NSArray *tabs = session[kTabSessionTabsKey];
    NSUInteger tabCount = [tabs isKindOfClass:[NSArray class]] ? tabs.count : 0;
    return (NSUInteger)MAX(0, MIN(count.integerValue, (NSInteger)tabCount));
}

+ (void)saveTabEntries:(NSArray<NSString *> *)entries
         selectedIndex:(NSInteger)selectedIndex
           pinnedCount:(NSUInteger)pinnedCount {
    if (entries.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTabSessionKey];
        return;
    }

    NSInteger clampedIndex = MAX(0, MIN(selectedIndex, (NSInteger)entries.count - 1));
    NSUInteger clampedPinned = MIN(pinnedCount, entries.count);
    NSDictionary *session = @{
        kTabSessionTabsKey: entries,
        kTabSessionSelectedIndexKey: @(clampedIndex),
        kTabSessionPinnedCountKey: @(clampedPinned),
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

+ (BOOL)isDefaultBrowser {
    NSString *ourID = [[NSBundle mainBundle] bundleIdentifier];
    if (ourID.length == 0) {
        return NO;
    }

    NSArray<NSURL *> *probes = @[
        [NSURL URLWithString:@"http://example.com"],
        [NSURL URLWithString:@"https://example.com"],
    ];
    for (NSURL *probe in probes) {
        NSURL *handlerURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:probe];
        if (!handlerURL) {
            return NO;
        }
        NSString *handlerID = [[NSBundle bundleWithURL:handlerURL] bundleIdentifier];
        if (handlerID.length == 0 || ![handlerID isEqualToString:ourID]) {
            return NO;
        }
    }
    return YES;
}

+ (void)requestSetAsDefaultBrowserWithCompletion:(void (^)(NSError * _Nullable error))completion {
    void (^finish)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        if (!completion) {
            return;
        }
        if ([NSThread isMainThread]) {
            completion(error);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    };

    NSURL *appURL = [[NSBundle mainBundle] bundleURL];
    if (@available(macOS 12.0, *)) {
        [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:appURL
                                           toOpenURLsWithScheme:@"http"
                                              completionHandler:^(NSError * _Nullable httpError) {
            if (httpError) {
                finish(httpError);
                return;
            }
            [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:appURL
                                               toOpenURLsWithScheme:@"https"
                                                  completionHandler:^(NSError * _Nullable httpsError) {
                finish(httpsError);
            }];
        }];
        return;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length == 0) {
        finish([NSError errorWithDomain:NSCocoaErrorDomain
                                   code:NSFileReadUnknownError
                               userInfo:@{NSLocalizedDescriptionKey: @"无法读取应用标识符"}]);
        return;
    }

    OSStatus httpStatus = LSSetDefaultHandlerForURLScheme(CFSTR("http"), (__bridge CFStringRef)bundleID);
    if (httpStatus != noErr) {
        finish([NSError errorWithDomain:NSOSStatusErrorDomain code:httpStatus userInfo:nil]);
        return;
    }
    OSStatus httpsStatus = LSSetDefaultHandlerForURLScheme(CFSTR("https"), (__bridge CFStringRef)bundleID);
    if (httpsStatus == noErr) {
        finish(nil);
    } else {
        finish([NSError errorWithDomain:NSOSStatusErrorDomain code:httpsStatus userInfo:nil]);
    }
}

+ (void)clearWebsiteDataWithCompletion:(void (^)(NSError * _Nullable error))completion {
    void (^finish)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        if (!completion) {
            return;
        }
        if ([NSThread isMainThread]) {
            completion(error);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    };

    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSSet<NSString *> *types = [WKWebsiteDataStore allWebsiteDataTypes];
    NSDate *since = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                               modifiedSince:since
                                           completionHandler:^{
        finish(nil);
    }];
}

@end
