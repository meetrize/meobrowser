#import "BrowsingPreferences.h"

static NSString * const kLastVisitedURLKey = @"lastVisitedURL";
static NSString * const kDefaultURLString = @"https://example.com";

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
    if (![self shouldPersistURL:url]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:url.absoluteString forKey:kLastVisitedURLKey];
}

+ (BOOL)shouldPersistURL:(nullable NSURL *)url {
    if (!url) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    return url.host.length > 0;
}

@end
