#import "PagePackMatcher.h"
#import "PagePackModels.h"

@implementation PagePackMatcher

+ (NSString *)defaultMatchForURL:(NSURL *)url {
    if (!url) {
        return @"*://*/*";
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return @"*://*/*";
    }
    NSString *host = url.host;
    if (host.length == 0) {
        return @"*://*/*";
    }
    NSNumber *port = url.port;
    if (port != nil) {
        NSInteger defaultPort = [scheme isEqualToString:@"https"] ? 443 : 80;
        if (port.integerValue != defaultPort) {
            return [NSString stringWithFormat:@"%@://%@:%@/*", scheme, host, port];
        }
    }
    return [NSString stringWithFormat:@"%@://%@/*", scheme, host];
}

+ (BOOL)URL:(NSURL *)url matchesPattern:(NSString *)pattern {
    if (!url || pattern.length == 0) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.length > 0 ? url.path : @"/";
    if (url.query.length > 0) {
        // Chrome match 含 path，不含 query；忽略 query
    }

    NSString *normalized = [pattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0) {
        return NO;
    }

    // scheme://host/path
    NSRange schemeSep = [normalized rangeOfString:@"://"];
    if (schemeSep.location == NSNotFound) {
        return NO;
    }
    NSString *patScheme = [[normalized substringToIndex:schemeSep.location] lowercaseString];
    NSString *rest = [normalized substringFromIndex:schemeSep.location + schemeSep.length];
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *patHost;
    NSString *patPath;
    if (slash.location == NSNotFound) {
        patHost = rest.lowercaseString;
        patPath = @"/*";
    } else {
        patHost = [[rest substringToIndex:slash.location] lowercaseString];
        patPath = [rest substringFromIndex:slash.location];
    }

    if (![self scheme:scheme matchesPattern:patScheme]) {
        return NO;
    }
    if (![self host:host matchesPattern:patHost url:url]) {
        return NO;
    }
    return [self path:path matchesPattern:patPath];
}

+ (BOOL)scheme:(NSString *)scheme matchesPattern:(NSString *)patScheme {
    if ([patScheme isEqualToString:@"*"]) {
        return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
    }
    return [scheme isEqualToString:patScheme];
}

+ (BOOL)host:(NSString *)host matchesPattern:(NSString *)patHost url:(NSURL *)url {
    if (patHost.length == 0) {
        return NO;
    }
    // host may include :port in pattern
    NSString *hostOnly = host;
    NSString *patHostOnly = patHost;
    NSNumber *urlPort = url.port;
    NSInteger patPort = -1;
    NSRange colon = [patHost rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        patHostOnly = [patHost substringToIndex:colon.location];
        patPort = [[patHost substringFromIndex:colon.location + 1] integerValue];
    }
    if (patPort >= 0) {
        if (urlPort == nil || urlPort.integerValue != patPort) {
            return NO;
        }
    }

    if ([patHostOnly isEqualToString:@"*"]) {
        return hostOnly.length > 0;
    }
    if ([patHostOnly hasPrefix:@"*."]) {
        NSString *suffix = [patHostOnly substringFromIndex:2];
        if ([hostOnly isEqualToString:suffix]) {
            return YES;
        }
        NSString *dotSuffix = [@"." stringByAppendingString:suffix];
        return [hostOnly hasSuffix:dotSuffix];
    }
    return [hostOnly isEqualToString:patHostOnly];
}

+ (BOOL)path:(NSString *)path matchesPattern:(NSString *)patPath {
    if (patPath.length == 0) {
        patPath = @"/";
    }
    // Convert glob * to regex; path patterns are simple.
    NSMutableString *regex = [NSMutableString stringWithString:@"^"];
    for (NSUInteger i = 0; i < patPath.length; i++) {
        unichar c = [patPath characterAtIndex:i];
        if (c == '*') {
            [regex appendString:@".*"];
        } else if (c == '?' || c == '+' || c == '.' || c == '(' || c == ')' || c == '[' || c == ']' ||
                   c == '{' || c == '}' || c == '|' || c == '\\' || c == '^' || c == '$') {
            [regex appendFormat:@"\\%C", c];
        } else {
            [regex appendFormat:@"%C", c];
        }
    }
    [regex appendString:@"$"];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:nil];
    if (!re) {
        return NO;
    }
    NSRange full = NSMakeRange(0, path.length);
    return [re numberOfMatchesInString:path options:0 range:full] > 0;
}

+ (BOOL)URL:(NSURL *)url matchesPack:(PagePack *)pack {
    if (!pack || !url) {
        return NO;
    }
    BOOL anyMatch = NO;
    for (NSString *pattern in pack.matches) {
        if ([self URL:url matchesPattern:pattern]) {
            anyMatch = YES;
            break;
        }
    }
    if (!anyMatch) {
        return NO;
    }
    for (NSString *pattern in pack.excludes) {
        if ([self URL:url matchesPattern:pattern]) {
            return NO;
        }
    }
    return YES;
}

@end
