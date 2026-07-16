#import "BrowserRiskHostPolicy.h"

@implementation BrowserRiskHostPolicy

+ (NSArray<NSString *> *)hibernationProtectedHostSuffixes {
    static NSArray<NSString *> *list = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        list = @[
            @"google.com",
            @"googleapis.com",
            @"gstatic.com",
            @"recaptcha.net",
            @"cloudflare.com",
            @"hcaptcha.com",
            @"baidu.com",
        ];
    });
    return list;
}

+ (NSArray<NSString *> *)loginAssistSuppressionHostSuffixes {
    return [self hibernationProtectedHostSuffixes];
}

+ (BOOL)host:(NSString *)host matchesSuffixes:(NSArray<NSString *> *)suffixes {
    if (host.length == 0) {
        return NO;
    }
    NSString *normalized = host.lowercaseString;
    if ([normalized hasSuffix:@"."]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    for (NSString *suffix in suffixes) {
        NSString *s = suffix.lowercaseString;
        if (s.length == 0) {
            continue;
        }
        if ([normalized isEqualToString:s]) {
            return YES;
        }
        NSString *dotSuffix = [@"." stringByAppendingString:s];
        if ([normalized hasSuffix:dotSuffix]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)hostIsHibernationProtected:(NSString *)host {
    return [self host:host matchesSuffixes:[self hibernationProtectedHostSuffixes]];
}

+ (BOOL)URLIsHibernationProtected:(NSURL *)url {
    if (!url) {
        return NO;
    }
    return [self hostIsHibernationProtected:url.host];
}

+ (BOOL)pathOrHostLooksLikeChallenge:(NSURL *)url {
    if (!url) {
        return NO;
    }
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.lowercaseString ?: @"";
    NSString *absolute = url.absoluteString.lowercaseString ?: @"";

    if ([path containsString:@"/sorry/"]) {
        return YES;
    }
    if ([path containsString:@"/recaptcha"]) {
        return YES;
    }
    if ([host containsString:@"challenges.cloudflare"]) {
        return YES;
    }
    if ([absolute containsString:@"challenges.cloudflare.com"]) {
        return YES;
    }
    return NO;
}

+ (BOOL)hostShouldSuppressLoginAssist:(NSString *)host {
    return [self host:host matchesSuffixes:[self loginAssistSuppressionHostSuffixes]];
}

+ (BOOL)URLShouldSuppressLoginAssist:(NSURL *)url {
    if (!url) {
        return NO;
    }
    if ([self pathOrHostLooksLikeChallenge:url]) {
        return YES;
    }
    return [self hostShouldSuppressLoginAssist:url.host];
}

@end
