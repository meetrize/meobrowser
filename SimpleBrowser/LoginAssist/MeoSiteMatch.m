#import "MeoSiteMatch.h"

MeoSitePathMatchMode const MeoSitePathMatchModePrefix = @"prefix";
MeoSitePathMatchMode const MeoSitePathMatchModeWildcard = @"wildcard";

@implementation MeoSiteMatch

+ (NSString *)normalizedHostForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    if (url.isFileURL) {
        return @"file";
    }
    NSString *host = url.host.lowercaseString;
    return host.length > 0 ? host : nil;
}

+ (NSNumber *)portNumberForURL:(NSURL *)url {
    if (!url || url.isFileURL) {
        return nil;
    }
    NSNumber *port = url.port;
    if (port == nil) {
        return nil;
    }
    NSInteger value = port.integerValue;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] && value == 80) {
        return nil;
    }
    if ([scheme isEqualToString:@"https"] && value == 443) {
        return nil;
    }
    return port;
}

+ (NSString *)pathPatternForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    if (url.isFileURL) {
        NSString *last = url.lastPathComponent;
        return last.length > 0 ? last : nil;
    }
    NSString *path = url.path ?: @"";
    if (path.length == 0 || [path isEqualToString:@"/"]) {
        return nil;
    }
    return path;
}

+ (NSString *)scopeDisplayStringForHost:(NSString *)host port:(NSNumber *)port {
    NSString *h = host.length > 0 ? host : @"";
    if (port != nil) {
        return [NSString stringWithFormat:@"%@:%@", h, port];
    }
    return h;
}

+ (NSString *)sitePatternForHost:(NSString *)host
                            port:(NSNumber *)port
                     pathPattern:(NSString *)pathPattern {
    NSString *scope = [self scopeDisplayStringForHost:host ?: @"" port:port];
    if (pathPattern.length == 0) {
        return scope;
    }
    if ([pathPattern hasPrefix:@"/"]) {
        return [scope stringByAppendingString:pathPattern];
    }
    return [NSString stringWithFormat:@"%@/%@", scope, pathPattern];
}

+ (BOOL)authority:(NSString *)authority
             host:(NSString * _Nullable * _Nonnull)outHost
             port:(NSNumber * _Nullable * _Nonnull)outPort {
    *outHost = nil;
    *outPort = nil;
    if (authority.length == 0) {
        return NO;
    }
    if ([authority hasPrefix:@"["]) {
        NSRange close = [authority rangeOfString:@"]"];
        if (close.location == NSNotFound) {
            return NO;
        }
        NSString *ipv6 = [authority substringWithRange:NSMakeRange(1, close.location - 1)];
        NSString *rest = [authority substringFromIndex:NSMaxRange(close)];
        if ([rest hasPrefix:@":"] && rest.length > 1) {
            NSString *portStr = [rest substringFromIndex:1];
            NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if (portStr.length > 0 && [portStr rangeOfCharacterFromSet:nonDigit].location == NSNotFound) {
                *outPort = @([portStr integerValue]);
            } else {
                return NO;
            }
        } else if (rest.length > 0) {
            return NO;
        }
        *outHost = ipv6.lowercaseString;
        return (*outHost).length > 0;
    }

    NSRange colon = [authority rangeOfString:@":" options:NSBackwardsSearch];
    if (colon.location != NSNotFound && colon.location > 0) {
        NSString *portStr = [authority substringFromIndex:colon.location + 1];
        NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (portStr.length > 0 && [portStr rangeOfCharacterFromSet:nonDigit].location == NSNotFound) {
            *outPort = @([portStr integerValue]);
            *outHost = [[authority substringToIndex:colon.location] lowercaseString];
            return (*outHost).length > 0;
        }
    }
    *outHost = authority.lowercaseString;
    return YES;
}

+ (BOOL)parseSitePattern:(NSString *)pattern
                    host:(NSString * _Nullable * _Nonnull)outHost
                    port:(NSNumber * _Nullable * _Nonnull)outPort
             pathPattern:(NSString * _Nullable * _Nonnull)outPathPattern {
    *outHost = nil;
    *outPort = nil;
    *outPathPattern = nil;
    NSString *raw = [pattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        return NO;
    }

    NSString *s = raw;
    NSRange scheme = [s rangeOfString:@"://"];
    if (scheme.location != NSNotFound) {
        s = [s substringFromIndex:NSMaxRange(scheme)];
    }
    // 不按 ? 截断：通配符可用 ?；仅去掉 fragment。
    NSRange hash = [s rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        s = [s substringToIndex:hash.location];
    }
    if (s.length == 0) {
        return NO;
    }

    if ([s isEqualToString:@"file"] || [s hasPrefix:@"file/"]) {
        *outHost = @"file";
        if ([s hasPrefix:@"file/"] && s.length > 5) {
            NSString *rest = [s substringFromIndex:5];
            *outPathPattern = rest.length > 0 ? rest : nil;
        }
        return YES;
    }

    NSString *authority = s;
    NSString *path = nil;
    if ([s hasPrefix:@"["]) {
        NSRange close = [s rangeOfString:@"]"];
        NSRange slashAfter = close.location == NSNotFound
            ? NSMakeRange(NSNotFound, 0)
            : [s rangeOfString:@"/" options:0 range:NSMakeRange(NSMaxRange(close), s.length - NSMaxRange(close))];
        if (slashAfter.location != NSNotFound) {
            authority = [s substringToIndex:slashAfter.location];
            path = [s substringFromIndex:slashAfter.location];
        }
    } else {
        NSRange slash = [s rangeOfString:@"/"];
        if (slash.location != NSNotFound) {
            authority = [s substringToIndex:slash.location];
            path = [s substringFromIndex:slash.location];
        }
    }

    if (![self authority:authority host:outHost port:outPort]) {
        return NO;
    }
    if ([path isEqualToString:@"/"]) {
        path = nil;
    }
    *outPathPattern = path.length > 0 ? path : nil;
    return YES;
}

+ (MeoSitePathMatchMode)inferredPathMatchModeForPattern:(NSString *)pathPattern {
    if (pathPattern.length == 0) {
        return MeoSitePathMatchModePrefix;
    }
    if ([pathPattern containsString:@"*"] || [pathPattern containsString:@"?"]) {
        return MeoSitePathMatchModeWildcard;
    }
    return MeoSitePathMatchModePrefix;
}

+ (NSString *)stripWWW:(NSString *)host {
    if ([host hasPrefix:@"www."] && host.length > 4) {
        return [host substringFromIndex:4];
    }
    return host ?: @"";
}

+ (BOOL)host:(NSString *)left matchesHost:(NSString *)right {
    if (left.length == 0 || right.length == 0) {
        return NO;
    }
    if ([left isEqualToString:right]) {
        return YES;
    }
    return [[self stripWWW:left] isEqualToString:[self stripWWW:right]];
}

+ (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern mode:(MeoSitePathMatchMode)mode {
    if (pattern.length == 0) {
        return YES;
    }
    NSString *normalizedPath = path.length > 0 ? path : @"/";
    MeoSitePathMatchMode resolved =
        mode.length > 0 ? mode : [self inferredPathMatchModeForPattern:pattern];
    if ([resolved isEqualToString:MeoSitePathMatchModeWildcard]) {
        NSMutableString *regex = [NSMutableString stringWithString:@"^"];
        for (NSUInteger i = 0; i < pattern.length; i++) {
            unichar c = [pattern characterAtIndex:i];
            if (c == '*') {
                [regex appendString:@".*"];
            } else if (c == '?') {
                [regex appendString:@"."];
            } else if (c == '.' || c == '[' || c == ']' || c == '(' || c == ')' || c == '{' ||
                       c == '}' || c == '+' || c == '^' || c == '$' || c == '|' || c == '\\') {
                [regex appendFormat:@"\\%C", c];
            } else {
                [regex appendFormat:@"%C", c];
            }
        }
        [regex appendString:@"$"];
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:regex options:0 error:nil];
        if (!re) {
            return NO;
        }
        NSRange full = NSMakeRange(0, normalizedPath.length);
        return [re numberOfMatchesInString:normalizedPath options:0 range:full] > 0;
    }
    return [normalizedPath hasPrefix:pattern];
}

+ (BOOL)matchesURL:(NSURL *)url
              host:(NSString *)host
              port:(NSNumber *)port
       pathPattern:(NSString *)pathPattern
              mode:(MeoSitePathMatchMode)mode {
    if (!url || host.length == 0) {
        return NO;
    }

    if (url.isFileURL) {
        if (![host isEqualToString:@"file"] && ![host isEqualToString:@"localhost"]) {
            return NO;
        }
        if (pathPattern.length == 0) {
            return YES;
        }
        NSString *path = url.path ?: @"";
        MeoSitePathMatchMode resolved =
            mode.length > 0 ? mode : [self inferredPathMatchModeForPattern:pathPattern];
        if ([resolved isEqualToString:MeoSitePathMatchModeWildcard]) {
            return [self path:path matchesPattern:pathPattern mode:resolved];
        }
        return [path containsString:pathPattern] || [path hasPrefix:pathPattern];
    }

    NSString *urlHost = url.host.lowercaseString;
    if (![self host:urlHost matchesHost:host.lowercaseString]) {
        return NO;
    }

    if (port != nil) {
        NSNumber *urlPort = [self portNumberForURL:url];
        NSInteger expected = port.integerValue;
        if (urlPort != nil) {
            if (urlPort.integerValue != expected) {
                return NO;
            }
        } else {
            // URL 未带显式非默认端口：仅当期望端口恰为 scheme 默认时才算匹配。
            NSString *scheme = url.scheme.lowercaseString;
            BOOL defaultOK =
                ([scheme isEqualToString:@"http"] && expected == 80) ||
                ([scheme isEqualToString:@"https"] && expected == 443);
            if (!defaultOK) {
                return NO;
            }
        }
    }

    NSString *path = url.path.length > 0 ? url.path : @"/";
    return [self path:path matchesPattern:pathPattern mode:mode];
}

+ (BOOL)shouldReuseHost:(NSString *)host
                   port:(NSNumber *)port
            pathPattern:(NSString *)pathPattern
                   mode:(MeoSitePathMatchMode)mode
           forSavingURL:(NSURL *)url {
    if (![self matchesURL:url host:host port:port pathPattern:pathPattern mode:mode]) {
        return NO;
    }
    NSNumber *urlPort = [self portNumberForURL:url];
    if (port != nil) {
        if (urlPort == nil || port.integerValue != urlPort.integerValue) {
            return NO;
        }
    } else if (urlPort != nil) {
        // 旧「任意端口」条目：不要在显式端口页上合并保存。
        return NO;
    }

    NSString *urlPath = [self pathPatternForURL:url];
    NSString *entryPath = pathPattern.length > 0 ? pathPattern : nil;
    if (entryPath.length == 0) {
        return urlPath.length == 0;
    }
    return [entryPath isEqualToString:urlPath ?: @""];
}

+ (NSInteger)specificityScoreForHost:(NSString *)host
                                port:(NSNumber *)port
                         pathPattern:(NSString *)pathPattern
                                mode:(MeoSitePathMatchMode)mode {
    (void)host;
    NSInteger score = 0;
    if (port != nil) {
        score += 1000;
    }
    if (pathPattern.length > 0) {
        score += 100 + (NSInteger)MIN(pathPattern.length, (NSUInteger)500);
        MeoSitePathMatchMode resolved =
            mode.length > 0 ? mode : [self inferredPathMatchModeForPattern:pathPattern];
        if ([resolved isEqualToString:MeoSitePathMatchModeWildcard]) {
            score -= 50;
        }
    }
    return score;
}

@end
