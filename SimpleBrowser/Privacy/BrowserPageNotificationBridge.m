#import "BrowserPageNotificationBridge.h"
#import "BrowserPageNotificationPresenter.h"
#import "LoginAssistScriptMessageProxy.h"
#import <os/log.h>

static NSString * const kMessageHandlerName = @"meoPageNotify";
static NSString * const kAllowedHostsDefaultsKey = @"PageNotifyAllowedHosts";
static const NSUInteger kMaxTitleLength = 80;
static const NSUInteger kMaxBodyLength = 200;
static const NSTimeInterval kMinIntervalSeconds = 10.0;

@interface BrowserPageNotificationBridge () <WKScriptMessageHandler>
@property (nonatomic, strong) LoginAssistScriptMessageProxy *messageProxy;
/// host\ntag → 上次投递时间（timeIntervalSince1970）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastPresentedAtByKey;
@end

@implementation BrowserPageNotificationBridge

+ (instancetype)sharedBridge {
    static BrowserPageNotificationBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[self alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _messageProxy = [[LoginAssistScriptMessageProxy alloc] init];
        _messageProxy.target = self;
        _lastPresentedAtByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) {
        return;
    }
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    BrowserPageNotificationBridge *bridge = [self sharedBridge];
    [ucc removeScriptMessageHandlerForName:kMessageHandlerName];
    [ucc addScriptMessageHandler:bridge.messageProxy name:kMessageHandlerName];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self userScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)userScriptSource {
    return @
    "(function() {\n"
    "  window.MeoBrowser = window.MeoBrowser || {};\n"
    "  window.MeoBrowser.notify = function (opts) {\n"
    "    var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoPageNotify;\n"
    "    if (!h) return false;\n"
    "    opts = opts || {};\n"
    "    h.postMessage({\n"
    "      type: 'notify',\n"
    "      title: opts.title || '',\n"
    "      body: opts.body || '',\n"
    "      tag: opts.tag || 'default',\n"
    "      count: opts.count || 0\n"
    "    });\n"
    "    return true;\n"
    "  };\n"
    "})();";
}

#pragma mark - Allow list / rate limit

- (NSString *)clippedString:(id)value maxLength:(NSUInteger)maxLength {
    NSString *raw = @"";
    if ([value isKindOfClass:[NSString class]]) {
        raw = (NSString *)value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        raw = [(NSNumber *)value stringValue];
    }
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length > maxLength) {
        raw = [raw substringToIndex:maxLength];
    }
    return raw;
}

- (BOOL)isHostAllowed:(NSString *)host {
    NSString *normalized = [(host ?: @"") lowercaseString];
    if (normalized.length == 0) {
        return NO;
    }
    if ([normalized isEqualToString:@"localhost"] ||
        [normalized isEqualToString:@"127.0.0.1"] ||
        [normalized isEqualToString:@"::1"]) {
        return YES;
    }

    NSArray *configured = [[NSUserDefaults standardUserDefaults] arrayForKey:kAllowedHostsDefaultsKey];
    if (![configured isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (id entry in configured) {
        if (![entry isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *allowed = [[(NSString *)entry lowercaseString]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (allowed.length == 0) {
            continue;
        }
        if ([normalized isEqualToString:allowed]) {
            return YES;
        }
        NSString *suffix = [@"." stringByAppendingString:allowed];
        if ([normalized hasSuffix:suffix]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)shouldRateLimitHost:(NSString *)host tag:(NSString *)tag {
    NSString *key = [NSString stringWithFormat:@"%@\n%@", host ?: @"", tag ?: @"default"];
    NSNumber *last = self.lastPresentedAtByKey[key];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (last != nil && (now - last.doubleValue) < kMinIntervalSeconds) {
        return YES;
    }
    self.lastPresentedAtByKey[key] = @(now);
    return NO;
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:kMessageHandlerName]) {
        return;
    }
    if (![message.body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *body = message.body;
    NSString *type = [body[@"type"] isKindOfClass:[NSString class]] ? body[@"type"] : @"";
    if (![type isEqualToString:@"notify"]) {
        return;
    }

    WKWebView *webView = [message.webView isKindOfClass:[WKWebView class]] ? message.webView : nil;
    NSString *host = webView.URL.host ?: @"";
    host = [host lowercaseString];
    if (![self isHostAllowed:host]) {
        os_log_info(OS_LOG_DEFAULT, "page notif drop unallowed host=%{public}@", host);
        return;
    }

    NSString *title = [self clippedString:body[@"title"] maxLength:kMaxTitleLength];
    NSString *text = [self clippedString:body[@"body"] maxLength:kMaxBodyLength];
    if (text.length == 0) {
        return;
    }
    NSString *tag = [self clippedString:body[@"tag"] maxLength:64];
    if (tag.length == 0) {
        tag = @"default";
    }
    NSInteger count = 0;
    id countValue = body[@"count"];
    if ([countValue isKindOfClass:[NSNumber class]]) {
        count = [(NSNumber *)countValue integerValue];
    }

    if ([self shouldRateLimitHost:host tag:tag]) {
        os_log_info(OS_LOG_DEFAULT, "page notif rate-limited host=%{public}@ tag=%{public}@", host, tag);
        return;
    }

    os_log_info(OS_LOG_DEFAULT,
                "page notif accept host=%{public}@ tag=%{public}@ count=%ld",
                host,
                tag,
                (long)count);

    [[BrowserPageNotificationPresenter sharedPresenter] presentWithTitle:title
                                                                    body:text
                                                                     tag:tag
                                                                    host:host];
}

@end
