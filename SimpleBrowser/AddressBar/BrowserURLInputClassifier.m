#import "BrowserURLInputClassifier.h"

@implementation BrowserURLInputClassifier

+ (BOOL)looksLikeURL:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    // 含空格一般是搜索词（合法 URL 中的空格应已编码）。
    if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        return NO;
    }

    NSString *lower = trimmed.lowercaseString;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) {
        return [self hostLooksNavigableInURLString:trimmed];
    }

    // 其它带 :// 的 scheme（如 file://）按网址处理。
    NSRange schemeSep = [trimmed rangeOfString:@"://"];
    if (schemeSep.location != NSNotFound && schemeSep.location > 0) {
        return YES;
    }

    // about:blank 等
    if ([lower hasPrefix:@"about:"]) {
        return YES;
    }

    return [self bareInputLooksLikeURL:trimmed];
}

+ (nullable NSURL *)navigableURLFromInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || ![self looksLikeURL:trimmed]) {
        return nil;
    }

    NSString *lower = trimmed.lowercaseString;
    if ([lower hasPrefix:@"http://"] ||
        [lower hasPrefix:@"https://"] ||
        [lower hasPrefix:@"about:"] ||
        [trimmed rangeOfString:@"://"].location != NSNotFound) {
        return [NSURL URLWithString:trimmed];
    }

    NSString *normalizedBare = [self normalizedBareURLBodyFromInput:trimmed];
    if (normalizedBare.length == 0) {
        return nil;
    }
    NSString *scheme = [self preferredSchemeForBareHostInput:normalizedBare];
    NSString *urlString = [scheme stringByAppendingString:normalizedBare];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return nil;
    }
    if (url.host.length == 0 && ![url.scheme.lowercaseString isEqualToString:@"about"]) {
        return nil;
    }
    return url;
}

/// 将裸 IPv6 写成 [literal]，便于 NSURL 解析；其余原样返回。
+ (NSString *)normalizedBareURLBodyFromInput:(NSString *)input {
    NSString *hostPort = [self hostPortFromAuthorityAndPath:input];
    NSString *host = nil;
    NSString *port = nil;
    if (![self splitHost:&host port:&port fromHostPort:hostPort]) {
        return input;
    }

    // splitHost 已将裸 IPv6 规范为 [literal]，需写回 body。
    if ([host hasPrefix:@"["] && ![hostPort hasPrefix:@"["]) {
        NSString *suffix = (hostPort.length < input.length) ? [input substringFromIndex:hostPort.length] : @"";
        if (port.length > 0) {
            return [NSString stringWithFormat:@"%@:%@%@", host, port, suffix];
        }
        return [host stringByAppendingString:suffix];
    }
    return input;
}

#pragma mark - Internals

+ (BOOL)bareInputLooksLikeURL:(NSString *)input {
    NSString *authorityAndPath = input;

    // 去掉 userinfo（罕见，但避免误判）。
    NSRange at = [authorityAndPath rangeOfString:@"@"];
    if (at.location != NSNotFound) {
        authorityAndPath = [authorityAndPath substringFromIndex:NSMaxRange(at)];
    }

    NSString *hostPort = [self hostPortFromAuthorityAndPath:authorityAndPath];
    if (hostPort.length == 0) {
        return NO;
    }

    NSString *host = nil;
    NSString *port = nil;
    if (![self splitHost:&host port:&port fromHostPort:hostPort]) {
        return NO;
    }

    if (port.length > 0 && ![self isValidPortString:port]) {
        return NO;
    }

    if ([self isLocalhostHost:host]) {
        return YES;
    }
    if ([self isIPv4Host:host]) {
        return YES;
    }
    if ([self isIPv6Host:host]) {
        return YES;
    }

    // 单标签主机名：仅当带端口时视为内网地址（如 myserver:3000）。
    if (![host containsString:@"."]) {
        return port.length > 0;
    }

    return [self isPlausibleDomainHost:host];
}

+ (BOOL)hostLooksNavigableInURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"about"]) {
        return YES;
    }
    if (url.host.length == 0) {
        return NO;
    }
    return YES;
}

+ (NSString *)hostPortFromAuthorityAndPath:(NSString *)authorityAndPath {
    NSCharacterSet *stoppers = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
    NSRange stop = [authorityAndPath rangeOfCharacterFromSet:stoppers];
    if (stop.location == NSNotFound) {
        return authorityAndPath;
    }
    return [authorityAndPath substringToIndex:stop.location];
}

+ (BOOL)splitHost:(NSString * _Nonnull * _Nonnull)outHost
             port:(NSString * _Nullable * _Nonnull)outPort
     fromHostPort:(NSString *)hostPort {
    if (hostPort.length == 0) {
        return NO;
    }

    // [IPv6] 或 [IPv6]:port
    if ([hostPort hasPrefix:@"["]) {
        NSRange close = [hostPort rangeOfString:@"]"];
        if (close.location == NSNotFound) {
            return NO;
        }
        *outHost = [hostPort substringWithRange:NSMakeRange(0, close.location + 1)];
        if (close.location + 1 < hostPort.length) {
            if ([hostPort characterAtIndex:close.location + 1] != ':') {
                return NO;
            }
            *outPort = [hostPort substringFromIndex:close.location + 2];
        } else {
            *outPort = nil;
        }
        return YES;
    }

    // 多个冒号且无方括号：视为裸 IPv6，规范化为 [literal]。
    NSUInteger colonCount = [[hostPort componentsSeparatedByString:@":"] count] - 1;
    if (colonCount > 1) {
        NSString *bracketed = [NSString stringWithFormat:@"[%@]", hostPort];
        if ([self isIPv6Host:bracketed] || [self isLocalhostHost:bracketed]) {
            *outHost = bracketed;
            *outPort = nil;
            return YES;
        }
        return NO;
    }

    // host:port — 仅当 ':' 后全是数字时才拆端口。
    NSRange colon = [hostPort rangeOfString:@":" options:NSBackwardsSearch];
    if (colon.location != NSNotFound) {
        NSString *maybePort = [hostPort substringFromIndex:NSMaxRange(colon)];
        if (maybePort.length > 0 && [self isAllDigits:maybePort]) {
            *outHost = [hostPort substringToIndex:colon.location];
            *outPort = maybePort;
            return (*outHost).length > 0;
        }
    }

    *outHost = hostPort;
    *outPort = nil;
    return YES;
}

+ (BOOL)isValidPortString:(NSString *)port {
    if (![self isAllDigits:port] || port.length == 0 || port.length > 5) {
        return NO;
    }
    NSInteger value = port.integerValue;
    return value >= 1 && value <= 65535;
}

+ (BOOL)isAllDigits:(NSString *)string {
    if (string.length == 0) {
        return NO;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

+ (BOOL)isLocalhostHost:(NSString *)host {
    NSString *lower = host.lowercaseString;
    if ([lower hasPrefix:@"["] && [lower hasSuffix:@"]"]) {
        lower = [lower substringWithRange:NSMakeRange(1, lower.length - 2)];
    }
    if ([lower isEqualToString:@"localhost"] || [lower isEqualToString:@"::1"]) {
        return YES;
    }
    // *.localhost（如 app.localhost）
    if ([lower hasSuffix:@".localhost"] && lower.length > 10) {
        return YES;
    }
    return NO;
}

+ (BOOL)isIPv4Host:(NSString *)host {
    NSArray<NSString *> *parts = [host componentsSeparatedByString:@"."];
    if (parts.count != 4) {
        return NO;
    }
    for (NSString *part in parts) {
        if (part.length == 0 || part.length > 3 || ![self isAllDigits:part]) {
            return NO;
        }
        // 禁止前导零（除单独的 0），减少把「版本号」误判为 IP；仍接受 10.0.0.1。
        if (part.length > 1 && [part hasPrefix:@"0"]) {
            return NO;
        }
        NSInteger octet = part.integerValue;
        if (octet < 0 || octet > 255) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)isIPv6Host:(NSString *)host {
    NSString *literal = host;
    if ([literal hasPrefix:@"["] && [literal hasSuffix:@"]"] && literal.length >= 4) {
        literal = [literal substringWithRange:NSMakeRange(1, literal.length - 2)];
    } else {
        // 裸 IPv6 在地址栏较少见，且易与 host:port 混淆；要求方括号。
        return NO;
    }
    if (literal.length == 0) {
        return NO;
    }
    // 粗校验：仅含十六进制、冒号，且至少有一个冒号。
    if ([literal rangeOfString:@":"].location == NSNotFound) {
        return NO;
    }
    static NSCharacterSet *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet characterSetWithCharactersInString:@":"];
        [set formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"]];
        // 允许 IPv4 映射段中的点
        [set addCharactersInString:@"."];
        allowed = [set copy];
    });
    NSCharacterSet *disallowed = [allowed invertedSet];
    return [literal rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

+ (BOOL)isPlausibleDomainHost:(NSString *)host {
    NSString *lower = host.lowercaseString;
    if ([lower hasPrefix:@"."] || [lower hasSuffix:@".."]) {
        return NO;
    }
    // 去掉末尾根点：example.com.
    if ([lower hasSuffix:@"."] && lower.length > 1) {
        lower = [lower substringToIndex:lower.length - 1];
    }

    NSArray<NSString *> *labels = [lower componentsSeparatedByString:@"."];
    if (labels.count < 2) {
        return NO;
    }

    for (NSString *label in labels) {
        if (label.length == 0 || label.length > 63) {
            return NO;
        }
        if ([label hasPrefix:@"-"] || [label hasSuffix:@"-"]) {
            return NO;
        }
        static NSCharacterSet *labelAllowed;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSMutableCharacterSet *set = [NSMutableCharacterSet alphanumericCharacterSet];
            [set addCharactersInString:@"-"];
            // 国际化域名可能已是 xn-- 或系统已处理；允许下划线以兼容少数内网命名。
            [set addCharactersInString:@"_"];
            labelAllowed = [set copy];
        });
        if ([label rangeOfCharacterFromSet:[labelAllowed invertedSet]].location != NSNotFound) {
            return NO;
        }
    }

    // 最终标签（TLD）不应为纯数字（避免把 1.2.3 之类当域名；完整 IPv4 已先行匹配）。
    NSString *tld = labels.lastObject;
    if ([self isAllDigits:tld]) {
        return NO;
    }
    // 至少 2 字符的 TLD（.c 过于可疑）；允许常见 2+ 以及新 gTLD。
    if (tld.length < 2) {
        return NO;
    }
    return YES;
}

+ (NSString *)preferredSchemeForBareHostInput:(NSString *)input {
    NSString *hostPort = [self hostPortFromAuthorityAndPath:input];
    NSString *host = nil;
    NSString *port = nil;
    if (![self splitHost:&host port:&port fromHostPort:hostPort]) {
        return @"https://";
    }
    // 本地开发常见无 TLS：IP / localhost / 单标签内网主机默认 http。
    if ([self isLocalhostHost:host] || [self isIPv4Host:host] || [self isIPv6Host:host]) {
        return @"http://";
    }
    if (![host containsString:@"."] && port.length > 0) {
        return @"http://";
    }
    return @"https://";
}

@end
