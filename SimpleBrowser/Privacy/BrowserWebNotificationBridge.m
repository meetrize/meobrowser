#import "BrowserWebNotificationBridge.h"
#import "BrowserPageNotificationPresenter.h"
#import "BrowserSitePermissionStore.h"
#import "LoginAssistScriptMessageProxy.h"
#import <AppKit/AppKit.h>
#import <os/log.h>

static NSString * const kMessageHandlerName = @"meoWebNotification";
static const NSUInteger kMaxTitleLength = 80;
static const NSUInteger kMaxBodyLength = 200;
static const NSTimeInterval kMinIntervalSeconds = 3.0;

@interface BrowserWebNotificationBridge () <WKScriptMessageHandler>
@property (nonatomic, strong) LoginAssistScriptMessageProxy *messageProxy;
/// host\ntag → 上次投递时间
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastPresentedAtByKey;
@end

@implementation BrowserWebNotificationBridge

+ (instancetype)sharedBridge {
    static BrowserWebNotificationBridge *bridge;
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
    BrowserWebNotificationBridge *bridge = [self sharedBridge];
    [ucc removeScriptMessageHandlerForName:kMessageHandlerName];
    [ucc addScriptMessageHandler:bridge.messageProxy name:kMessageHandlerName];
    // DocumentStart：页面脚本常在加载早期探测 Notification / requestPermission。
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self userScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)userScriptSource {
    // 覆盖 WK 原生 Notification（http / 局域网上常为 permission=denied 且无法弹授权框）。
    // 不要求 isSecureContext，以便 FeedGen 等 http://IP 阅读器可用。
    return @
    "(function() {\n"
    "  if (window.__meoWebNotificationInstalled) { return; }\n"
    "  var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoWebNotification;\n"
    "  if (!handler) { return; }\n"
    "  window.__meoWebNotificationInstalled = true;\n"
    "  var pending = Object.create(null);\n"
    "  function post(msg) { try { handler.postMessage(msg); } catch (e) {} }\n"
    "  function host() { try { return location.hostname || ''; } catch (e) { return ''; } }\n"
    "  window.__meoWebNotificationDeliver = function(id, payload) {\n"
    "    var cb = pending[id]; if (!cb) return; delete pending[id];\n"
    "    try { cb(payload || {}); } catch (e) {}\n"
    "  };\n"
    "  function permissionFromStore(state) {\n"
    "    if (state === 'granted' || state === 'denied' || state === 'default') { return state; }\n"
    "    return 'default';\n"
    "  }\n"
    "  function Notification(title, options) {\n"
    "    if (!(this instanceof Notification)) {\n"
    "      throw new TypeError(\"Failed to construct 'Notification': Please use the 'new' operator.\");\n"
    "    }\n"
    "    if (Notification.permission !== 'granted') {\n"
    "      var err = new Error('Notification permission has not been granted');\n"
    "      err.name = 'NotAllowedError';\n"
    "      throw err;\n"
    "    }\n"
    "    options = options || {};\n"
    "    this.title = title == null ? '' : String(title);\n"
    "    this.body = options.body == null ? '' : String(options.body);\n"
    "    this.tag = options.tag == null ? '' : String(options.tag);\n"
    "    this.icon = options.icon == null ? '' : String(options.icon);\n"
    "    this.lang = options.lang == null ? '' : String(options.lang);\n"
    "    this.dir = options.dir || 'auto';\n"
    "    this.data = options.data;\n"
    "    this.onclick = null;\n"
    "    this.onshow = null;\n"
    "    this.onerror = null;\n"
    "    this.onclose = null;\n"
    "    var self = this;\n"
    "    post({\n"
    "      type: 'show',\n"
    "      title: this.title,\n"
    "      body: this.body,\n"
    "      tag: this.tag || 'default',\n"
    "      host: host()\n"
    "    });\n"
    "    setTimeout(function() {\n"
    "      if (typeof self.onshow === 'function') { try { self.onshow(); } catch (e) {} }\n"
    "    }, 0);\n"
    "  }\n"
    "  Notification.permission = 'default';\n"
    "  Notification.maxActions = 0;\n"
    "  Notification.prototype.close = function() {};\n"
    "  Notification.requestPermission = function(deprecatedCallback) {\n"
    "    return new Promise(function(resolve) {\n"
    "      var id = String(Date.now()) + '-' + Math.random();\n"
    "      pending[id] = function(payload) {\n"
    "        var state = permissionFromStore(payload && payload.permission);\n"
    "        Notification.permission = state;\n"
    "        if (typeof deprecatedCallback === 'function') {\n"
    "          try { deprecatedCallback(state); } catch (e) {}\n"
    "        }\n"
    "        resolve(state);\n"
    "      };\n"
    "      post({ type: 'requestPermission', requestId: id, host: host() });\n"
    "    });\n"
    "  };\n"
    "  window.Notification = Notification;\n"
    "  (function syncPermission() {\n"
    "    var id = 'sync-' + String(Date.now()) + '-' + Math.random();\n"
    "    pending[id] = function(payload) {\n"
    "      Notification.permission = permissionFromStore(payload && payload.permission);\n"
    "    };\n"
    "    post({ type: 'getPermission', requestId: id, host: host() });\n"
    "  })();\n"
    "})();";
}

#pragma mark - Helpers

+ (NSString *)displayHost:(NSString *)host {
    return host.length > 0 ? host : @"此网站";
}

+ (void)presentPanel:(NSAlert *)alert
          hostWindow:(nullable NSWindow *)hostWindow
   completionHandler:(void (^)(NSModalResponse returnCode))completionHandler {
    if (hostWindow != nil) {
        [alert beginSheetModalForWindow:hostWindow completionHandler:completionHandler];
    } else {
        completionHandler([alert runModal]);
    }
}

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

- (NSString *)jsQuoted:(NSString *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
    if (!data) {
        return @"\"\"";
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length < 2) {
        return @"\"\"";
    }
    return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

- (void)deliverToWebView:(WKWebView *)webView javaScript:(NSString *)javaScript {
    if (!webView || javaScript.length == 0) {
        return;
    }
    [webView evaluateJavaScript:javaScript completionHandler:nil];
}

- (void)deliverPermission:(NSString *)permission
                requestId:(NSString *)requestId
                toWebView:(WKWebView *)webView {
    if (!webView || requestId.length == 0) {
        return;
    }
    NSDictionary *payload = @{@"permission": permission ?: @"denied"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) {
        return;
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.__meoWebNotificationDeliver(%@,%@);",
                    [self jsQuoted:requestId], json];
    [self deliverToWebView:webView javaScript:js];
}

+ (NSString *)permissionStringForHost:(NSString *)host {
    BrowserSitePermissionDecision decision =
        [[BrowserSitePermissionStore sharedStore] notificationDecisionForHost:host];
    // 仅同步 granted。deny 若暴露给页面，FeedGen 等会短路不再调用 requestPermission。
    if (decision == BrowserSitePermissionDecisionAllow) {
        return @"granted";
    }
    return @"default";
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

#pragma mark - Permission flow

+ (void)finishWithSystemAuthorization:(void (^)(NSString *permission))completion {
    [[BrowserPageNotificationPresenter sharedPresenter] ensureAuthorizationWithCompletion:^(BOOL granted) {
        // 系统已拒绝时 Presenter 会打开「通知」设置；返回 default 便于页面再次点击重试
        //（若返回 denied，FeedGen 等站点会永久短路不再调用 requestPermission）。
        completion(granted ? @"granted" : @"default");
    }];
}

+ (void)resolvePermissionForHost:(NSString *)host
                      hostWindow:(nullable NSWindow *)hostWindow
                      completion:(void (^)(NSString *permission))completion {
    BrowserSitePermissionStore *store = [BrowserSitePermissionStore sharedStore];
    BrowserSitePermissionDecision existing = [store notificationDecisionForHost:host];
    if (existing == BrowserSitePermissionDecisionAllow) {
        [self finishWithSystemAuthorization:completion];
        return;
    }
    if (existing == BrowserSitePermissionDecisionDeny) {
        // 允许用户再次点击时重新询问站点权限。
        [store setNotificationDecision:BrowserSitePermissionDecisionUnknown forHost:host];
    }

    NSString *display = [self displayHost:host];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText =
        [NSString stringWithFormat:@"网站 “%@” 想在 “通知中心” 中给你发送通知。", display];
    alert.informativeText = @"可以在 “设置” 的 “网站” 部分更改通知设置。";
    // 与系统浏览器一致：右侧默认「允许」，左侧「不允许」。
    [alert addButtonWithTitle:@"允许"];
    [alert addButtonWithTitle:@"不允许"];
    [self presentPanel:alert hostWindow:hostWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [store setNotificationDecision:BrowserSitePermissionDecisionAllow forHost:host];
            [self finishWithSystemAuthorization:completion];
        } else {
            [store setNotificationDecision:BrowserSitePermissionDecisionDeny forHost:host];
            completion(@"denied");
        }
    }];
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
    NSString *requestId = [body[@"requestId"] isKindOfClass:[NSString class]] ? body[@"requestId"] : @"";
    WKWebView *webView = [message.webView isKindOfClass:[WKWebView class]] ? message.webView : nil;
    NSWindow *hostWindow = webView.window;

    NSString *host = [body[@"host"] isKindOfClass:[NSString class]] ? body[@"host"] : @"";
    if (host.length == 0) {
        host = webView.URL.host ?: @"";
    }
    host = [host lowercaseString];

    if ([type isEqualToString:@"getPermission"]) {
        NSString *permission = [[self class] permissionStringForHost:host];
        [self deliverPermission:permission requestId:requestId toWebView:webView];
        return;
    }

    if ([type isEqualToString:@"requestPermission"]) {
        [[self class] resolvePermissionForHost:host
                                    hostWindow:hostWindow
                                    completion:^(NSString *permission) {
            [self deliverPermission:permission requestId:requestId toWebView:webView];
        }];
        return;
    }

    if ([type isEqualToString:@"show"]) {
        BrowserSitePermissionDecision decision =
            [[BrowserSitePermissionStore sharedStore] notificationDecisionForHost:host];
        if (decision != BrowserSitePermissionDecisionAllow) {
            os_log_info(OS_LOG_DEFAULT, "web notif drop unauthorized host=%{public}@", host);
            return;
        }

        NSString *title = [self clippedString:body[@"title"] maxLength:kMaxTitleLength];
        NSString *text = [self clippedString:body[@"body"] maxLength:kMaxBodyLength];
        if (text.length == 0 && title.length == 0) {
            return;
        }
        if (text.length == 0) {
            text = title;
        }
        NSString *tag = [self clippedString:body[@"tag"] maxLength:64];
        if (tag.length == 0) {
            tag = @"default";
        }

        if ([self shouldRateLimitHost:host tag:tag]) {
            os_log_info(OS_LOG_DEFAULT, "web notif rate-limited host=%{public}@ tag=%{public}@", host, tag);
            return;
        }

        os_log_info(OS_LOG_DEFAULT, "web notif show host=%{public}@ tag=%{public}@", host, tag);
        [[BrowserPageNotificationPresenter sharedPresenter] presentWithTitle:title.length > 0 ? title : host
                                                                        body:text
                                                                         tag:tag
                                                                        host:host];
        return;
    }
}

@end
