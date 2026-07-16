#import "BrowserUserAgent.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@implementation BrowserUserAgent

+ (NSString *)safariAlignedUserAgent {
    static NSString *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cached = [self computeSafariAlignedUserAgent];
        if (cached.length == 0) {
            cached = [self fallbackUserAgent];
        }
    });
    return cached;
}

+ (NSString *)computeSafariAlignedUserAgent {
    NSString *sampled = [self sampleDefaultUserAgent];
    NSString *safariVersion = [self installedSafariShortVersion] ?: @"18.0";
    NSString *safariToken = @"605.1.15";

    if (sampled.length == 0) {
        return nil;
    }

    // 去掉末尾 App 名（WKWebView 默认可能带 bundle 名）。
    NSString *base = [self strippingTrailingApplicationTokenFromUserAgent:sampled];

    // 已含 Version + Safari：替换 Version 为系统 Safari 短版本，保持与本机一致。
    NSRegularExpression *versionRe =
        [NSRegularExpression regularExpressionWithPattern:@"Version/[0-9]+(?:\\.[0-9]+)*"
                                                  options:0
                                                    error:nil];
    NSRegularExpression *safariRe =
        [NSRegularExpression regularExpressionWithPattern:@"Safari/[0-9.]+"
                                                  options:0
                                                    error:nil];

    NSString *withVersion = base;
    NSString *versionReplacement = [NSString stringWithFormat:@"Version/%@", safariVersion];
    if ([versionRe numberOfMatchesInString:withVersion options:0 range:NSMakeRange(0, withVersion.length)] > 0) {
        withVersion = [versionRe stringByReplacingMatchesInString:withVersion
                                                          options:0
                                                            range:NSMakeRange(0, withVersion.length)
                                                     withTemplate:versionReplacement];
    } else {
        withVersion = [withVersion stringByAppendingFormat:@" %@", versionReplacement];
    }

    if ([safariRe numberOfMatchesInString:withVersion options:0 range:NSMakeRange(0, withVersion.length)] > 0) {
        withVersion = [safariRe stringByReplacingMatchesInString:withVersion
                                                         options:0
                                                           range:NSMakeRange(0, withVersion.length)
                                                    withTemplate:[NSString stringWithFormat:@"Safari/%@", safariToken]];
    } else {
        withVersion = [withVersion stringByAppendingFormat:@" Safari/%@", safariToken];
    }

    return [withVersion stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)sampleDefaultUserAgent {
    __block NSString *result = nil;
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // 空 applicationName，避免采样到硬编码 Safari 伪装段。
    config.applicationNameForUserAgent = @"";
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1) configuration:config];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id value, NSError *error) {
        (void)error;
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            result = [(NSString *)value copy];
        }
        dispatch_semaphore_signal(sem);
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        if ([deadline timeIntervalSinceNow] < 0) {
            break;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    (void)webView;
    return result;
}

+ (nullable NSString *)installedSafariShortVersion {
    NSString *plistPath = @"/Applications/Safari.app/Contents/Info.plist";
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSString *version = info[@"CFBundleShortVersionString"];
    if (![version isKindOfClass:[NSString class]] || version.length == 0) {
        return nil;
    }
    // 仅保留主.次，避免过长。
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if (parts.count >= 2) {
        return [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    }
    return version;
}

+ (NSString *)strippingTrailingApplicationTokenFromUserAgent:(NSString *)ua {
    // 匹配末尾「 Name/1.2.3」且 Name 不是 Version/Safari/Mobile/AppleWebKit。
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
             @"\\s+(?!Version|Safari|Mobile|AppleWebKit|Chrome|CriOS|FxiOS)[A-Za-z0-9._-]+/[0-9][^\\s]*\\s*$"
                                                  options:0
                                                    error:nil];
    NSString *stripped = [re stringByReplacingMatchesInString:ua
                                                      options:0
                                                        range:NSMakeRange(0, ua.length)
                                                 withTemplate:@""];
    return stripped.length > 0 ? stripped : ua;
}

+ (NSString *)fallbackUserAgent {
    NSString *safariVersion = [self installedSafariShortVersion] ?: @"18.0";
    return [NSString stringWithFormat:
            @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%@ Safari/605.1.15",
            safariVersion];
}

@end
