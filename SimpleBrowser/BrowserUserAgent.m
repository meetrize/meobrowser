#import "BrowserUserAgent.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <os/lock.h>

@implementation BrowserUserAgent

static NSString *sCachedUserAgent = nil;
static os_unfair_lock sUserAgentLock = OS_UNFAIR_LOCK_INIT;
static BOOL sWarmUpStarted = NO;

+ (void)setCachedUserAgent:(NSString *)ua {
    if (ua.length == 0) {
        return;
    }
    os_unfair_lock_lock(&sUserAgentLock);
    sCachedUserAgent = [ua copy];
    os_unfair_lock_unlock(&sUserAgentLock);
}

+ (nullable NSString *)cachedUserAgentCopy {
    os_unfair_lock_lock(&sUserAgentLock);
    NSString *cached = sCachedUserAgent;
    os_unfair_lock_unlock(&sUserAgentLock);
    return cached;
}

/// 仅在主线程调用：WKWebView / WebKit 初始化不允许离主线程。
+ (void)sampleOnMainQueueIfNeeded {
    NSAssert([NSThread isMainThread], @"UA sampling requires main thread");
    if ([self cachedUserAgentCopy].length > 0) {
        // 若已是采样结果则跳过；fallback 也可被升级覆盖。
    }
    NSString *computed = [self computeSafariAlignedUserAgent];
    if (computed.length == 0) {
        computed = [self fallbackUserAgent];
    }
    [self setCachedUserAgent:computed];
}

+ (void)warmUpInBackground {
    os_unfair_lock_lock(&sUserAgentLock);
    if (sWarmUpStarted) {
        os_unfair_lock_unlock(&sUserAgentLock);
        return;
    }
    sWarmUpStarted = YES;
    // 后台绝不创建 WKWebView（WebKit::InitializeWebKit2 会 SIGTRAP）。
    if (sCachedUserAgent.length == 0) {
        sCachedUserAgent = [[self fallbackUserAgent] copy];
    }
    os_unfair_lock_unlock(&sUserAgentLock);
}

+ (void)scheduleMainQueueSampleIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sampleOnMainQueueIfNeeded];
    });
}

+ (NSString *)safariAlignedUserAgent {
    NSString *cached = [self cachedUserAgentCopy];
    if (cached.length > 0) {
        return cached;
    }

    NSString *fallback = [self fallbackUserAgent];
    [self setCachedUserAgent:fallback];
    [self warmUpInBackground];
    return fallback;
}

+ (NSString *)computeSafariAlignedUserAgent {
    NSString *sampled = [self sampleDefaultUserAgent];
    NSString *safariVersion = [self installedSafariShortVersion] ?: @"18.0";
    NSString *safariToken = @"605.1.15";

    if (sampled.length == 0) {
        return nil;
    }

    NSString *base = [self strippingTrailingApplicationTokenFromUserAgent:sampled];

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
    // 仅主线程：短超时等待，禁止无限泵 runloop。
    if (![NSThread isMainThread]) {
        return nil;
    }

    __block NSString *result = nil;
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
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

    // 主线程需泵 runloop 才能完成 evaluateJavaScript，但硬限 0.5s。
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        if ([deadline timeIntervalSinceNow] < 0) {
            break;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
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
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if (parts.count >= 2) {
        return [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    }
    return version;
}

+ (NSString *)strippingTrailingApplicationTokenFromUserAgent:(NSString *)ua {
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
