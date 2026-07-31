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

+ (NSArray<NSString *> *)pageAutomationSuppressionHostSuffixes {
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
    NSString *query = url.query.lowercaseString ?: @"";

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
    // Cloudflare Managed Challenge / Turnstile 常见路径与参数（主站 origin 也会带）。
    if ([path containsString:@"/cdn-cgi/challenge"]) {
        return YES;
    }
    if ([path containsString:@"/cdn-cgi/l/chk_jschl"]) {
        return YES;
    }
    if ([absolute containsString:@"__cf_chl"]) {
        return YES;
    }
    if ([query containsString:@"__cf_chl"]) {
        return YES;
    }
    if ([absolute containsString:@"cf-challenge"] || [absolute containsString:@"cf_challenge"]) {
        return YES;
    }
    if ([host containsString:@"turnstile"]) {
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

+ (BOOL)URLShouldSuppressPageAutomation:(NSURL *)url {
    return [self URLShouldSuppressLoginAssist:url];
}

+ (NSString *)javaScriptQuotedSuffixLiteral {
    NSArray<NSString *> *suffixes = [self pageAutomationSuppressionHostSuffixes];
    NSMutableArray<NSString *> *quoted = [NSMutableArray arrayWithCapacity:suffixes.count];
    for (NSString *s in suffixes) {
        NSString *escaped = [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                             stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        [quoted addObject:[NSString stringWithFormat:@"'%@'", escaped]];
    }
    return [quoted componentsJoinedByString:@","];
}

/// 供 UserScript 嵌入：根据 location / 简易 DOM 判定是否应静默（人机页 / 风险域）。
+ (NSString *)javaScriptShouldSuppressPageAutomationFunctionNamed:(NSString *)functionName {
    NSString *name = functionName.length > 0 ? functionName : @"meoShouldSuppressPageAutomation";
    NSString *suffixLiteral = [self javaScriptQuotedSuffixLiteral];
    return [NSString stringWithFormat:
            @"function %@() {\n"
            @"  try {\n"
            @"    var host = (location.hostname || '').toLowerCase();\n"
            @"    var path = (location.pathname || '').toLowerCase();\n"
            @"    var href = (location.href || '').toLowerCase();\n"
            @"    var search = (location.search || '').toLowerCase();\n"
            @"    var suffixes = [%@];\n"
            @"    for (var i = 0; i < suffixes.length; i++) {\n"
            @"      var s = suffixes[i];\n"
            @"      if (host === s || host.endsWith('.' + s)) return true;\n"
            @"    }\n"
            @"    if (path.indexOf('/sorry/') >= 0) return true;\n"
            @"    if (path.indexOf('/recaptcha') >= 0) return true;\n"
            @"    if (host.indexOf('challenges.cloudflare') >= 0) return true;\n"
            @"    if (href.indexOf('challenges.cloudflare.com') >= 0) return true;\n"
            @"    if (path.indexOf('/cdn-cgi/challenge') >= 0) return true;\n"
            @"    if (path.indexOf('/cdn-cgi/l/chk_jschl') >= 0) return true;\n"
            @"    if (href.indexOf('__cf_chl') >= 0 || search.indexOf('__cf_chl') >= 0) return true;\n"
            @"    if (href.indexOf('cf-challenge') >= 0 || href.indexOf('cf_challenge') >= 0) return true;\n"
            @"    if (host.indexOf('turnstile') >= 0) return true;\n"
            @"    // DocumentEnd：主站托管的 CF interstitial（URL 仍是业务域名）。\n"
            @"    try {\n"
            @"      var t = (document.title || '').toLowerCase();\n"
            @"      if (t.indexOf('just a moment') >= 0 || t.indexOf('attention required') >= 0) return true;\n"
            @"      if (t.indexOf('请稍候') >= 0 || t.indexOf('正在验证') >= 0) return true;\n"
            @"      if (document.querySelector && document.querySelector(\n"
            @"          '#challenge-form, #cf-challenge-running, #cf-please-wait, .cf-turnstile, #cf-turnstile, '\n"
            @"          + 'iframe[src*=\"challenges.cloudflare\"], iframe[src*=\"turnstile\"]')) {\n"
            @"        return true;\n"
            @"      }\n"
            @"    } catch (domErr) {}\n"
            @"  } catch (e) {}\n"
            @"  return false;\n"
            @"}\n",
            name, suffixLiteral];
}

@end
