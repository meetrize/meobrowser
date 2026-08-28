#import "BrowserGeolocationBridge.h"
#import "BrowserLocationPreferences.h"
#import "BrowserSitePermissionStore.h"
#import "BrowserLocationService.h"
#import "BrowserRiskHostPolicy.h"
#import "LoginAssistScriptMessageProxy.h"
#import <AppKit/AppKit.h>

static NSString * const kMessageHandlerName = @"meoGeolocation";

@interface BrowserGeolocationBridge () <WKScriptMessageHandler>
@property (nonatomic, strong) LoginAssistScriptMessageProxy *messageProxy;
@end

@implementation BrowserGeolocationBridge

+ (instancetype)sharedBridge {
    static BrowserGeolocationBridge *bridge;
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
    BrowserGeolocationBridge *bridge = [self sharedBridge];
    [ucc removeScriptMessageHandlerForName:kMessageHandlerName];
    [ucc addScriptMessageHandler:bridge.messageProxy name:kMessageHandlerName];
    // 仅主框架 + DocumentEnd：Turnstile iframe 保持原生环境；业务域 interstitial 可用 DOM 启发式。
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self userScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)userScriptSource {
    // Cloudflare Turnstile 对改写 geolocation / permissions.query 极敏感。
    // 延迟安装：等 widget / interstitial 挂上后再判定；命中则永不改写原生 API。
    // 不在安装时改写 permissions.query（Turnstile 常探测）；定位请求仍走桥接。
    NSString *suppressFn =
        [BrowserRiskHostPolicy javaScriptShouldSuppressPageAutomationFunctionNamed:@"meoShouldSkipGeolocationBridge"];
    NSString *body = @
    "  if (window.__meoGeolocationBridgeInstalled || window.__meoGeolocationBridgeScheduled) { return; }\n"
    "  var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoGeolocation;\n"
    "  if (!handler) { return; }\n"
    "  if (meoShouldSkipGeolocationBridge()) { return; }\n"
    "  window.__meoGeolocationBridgeScheduled = true;\n"
    "  function tryInstall() {\n"
    "    if (window.__meoGeolocationBridgeInstalled) { return; }\n"
    "    if (meoShouldSkipGeolocationBridge()) { return; }\n"
    "    window.__meoGeolocationBridgeInstalled = true;\n"
    "    var pending = Object.create(null);\n"
    "    var watchMap = Object.create(null);\n"
    "    var nextWatchId = 1;\n"
    "    function post(msg) { try { handler.postMessage(msg); } catch (e) {} }\n"
    "    function mkError(code, message) {\n"
    "      return { code: code, message: message || '', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 };\n"
    "    }\n"
    "    function mkPosition(p) {\n"
    "      return {\n"
    "        coords: {\n"
    "          latitude: p.latitude, longitude: p.longitude, accuracy: p.accuracy || 0,\n"
    "          altitude: p.altitude || null, altitudeAccuracy: p.altitudeAccuracy || null,\n"
    "          heading: p.heading || null, speed: p.speed || null\n"
    "        },\n"
    "        timestamp: p.timestamp || Date.now()\n"
    "      };\n"
    "    }\n"
    "    window.__meoGeolocationDeliver = function(id, payload) {\n"
    "      var cb = pending[id]; if (!cb) return; delete pending[id];\n"
    "      if (payload && payload.error) { cb.error(mkError(payload.error.code, payload.error.message)); return; }\n"
    "      if (payload && payload.position) {\n"
    "        var pos = mkPosition(payload.position);\n"
    "        if (cb.success) { cb.success(pos); }\n"
    "        if (cb.watch) { cb.watch(pos); }\n"
    "        return;\n"
    "      }\n"
    "      cb.error(mkError(2, 'Position unavailable'));\n"
    "    };\n"
    "    window.__meoGeolocationPermissionDeliver = function(id, state) {\n"
    "      var cb = pending[id]; if (!cb) return; delete pending[id];\n"
    "      var status = { state: state || 'denied', onchange: null, addEventListener: function() {}, removeEventListener: function() {} };\n"
    "      if (cb.success) { cb.success(status); }\n"
    "    };\n"
    "    function host() { try { return location.hostname || ''; } catch (e) { return ''; } }\n"
    "    function request(type, requestId, success, error, extra) {\n"
    "      if (meoShouldSkipGeolocationBridge()) {\n"
    "        if (typeof error === 'function') { error(mkError(2, 'Position unavailable')); }\n"
    "        return;\n"
    "      }\n"
    "      pending[requestId] = { success: success, error: error, watch: extra && extra.watch };\n"
    "      var msg = { type: type, requestId: requestId, host: host() };\n"
    "      if (extra && extra.options) { msg.options = extra.options; }\n"
    "      post(msg);\n"
    "    }\n"
    "    if (navigator.geolocation) {\n"
    "      navigator.geolocation.getCurrentPosition = function(success, error, options) {\n"
    "        request('getCurrentPosition', String(Date.now()) + '-' + Math.random(), success, error, { options: options || {} });\n"
    "      };\n"
    "      navigator.geolocation.watchPosition = function(success, error, options) {\n"
    "        var watchId = nextWatchId++;\n"
    "        request('watchPosition', String(watchId), success, error, { options: options || {}, watch: true });\n"
    "        watchMap[watchId] = true;\n"
    "        return watchId;\n"
    "      };\n"
    "      navigator.geolocation.clearWatch = function(watchId) {\n"
    "        delete watchMap[watchId];\n"
    "        post({ type: 'clearWatch', requestId: String(watchId), host: host() });\n"
    "      };\n"
    "    }\n"
    "  }\n"
    "  setTimeout(tryInstall, 1800);\n";
    return [NSString stringWithFormat:@"(function() {\n%@%@})();", suppressFn, body];
}

#pragma mark - Permission flow

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

+ (NSString *)permissionStateForHost:(NSString *)host {
    if (![BrowserLocationPreferences sharedPreferences].geolocationEnabled) {
        return @"denied";
    }
    BrowserSitePermissionDecision decision = [[BrowserSitePermissionStore sharedStore] geolocationDecisionForHost:host];
    if (decision == BrowserSitePermissionDecisionDeny) {
        return @"denied";
    }
    if (![BrowserLocationService isSystemLocationAuthorized]) {
        return @"denied";
    }
    // 主开关与系统定位均已开启时返回 granted，避免站点只查 permissions.query 就报错（如闲鱼按距离筛选）。
    return @"granted";
}

+ (void)resolveSitePermissionForHost:(NSString *)host
                          hostWindow:(nullable NSWindow *)hostWindow
                          completion:(void (^)(BOOL allowed))completion {
    if (![BrowserLocationPreferences sharedPreferences].geolocationEnabled) {
        completion(NO);
        return;
    }

    BrowserSitePermissionStore *store = [BrowserSitePermissionStore sharedStore];
    BrowserSitePermissionDecision existing = [store geolocationDecisionForHost:host];
    if (existing == BrowserSitePermissionDecisionDeny) {
        completion(NO);
        return;
    }
    if (existing == BrowserSitePermissionDecisionAllow) {
        [BrowserLocationService ensureSystemAuthorizationWithCompletion:completion];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"允许“%@”获取你的位置？", [self displayHost:host]];
    alert.informativeText = @"网站将使用你的地理位置提供附近服务或地图功能。";
    [alert addButtonWithTitle:@"允许"];
    [alert addButtonWithTitle:@"拒绝"];
    [self presentPanel:alert hostWindow:hostWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [store setGeolocationDecision:BrowserSitePermissionDecisionAllow forHost:host];
            [BrowserLocationService ensureSystemAuthorizationWithCompletion:completion];
        } else {
            [store setGeolocationDecision:BrowserSitePermissionDecisionDeny forHost:host];
            completion(NO);
        }
    }];
}

+ (void)handleWebKitPermissionRequestForHost:(NSString *)host
                                  hostWindow:(nullable NSWindow *)hostWindow
                             decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    [self resolveSitePermissionForHost:host hostWindow:hostWindow completion:^(BOOL allowed) {
        decisionHandler(allowed ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
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
    NSString *host = [body[@"host"] isKindOfClass:[NSString class]] ? body[@"host"] : @"";
    WKWebView *webView = [message.webView isKindOfClass:[WKWebView class]] ? message.webView : nil;
    NSWindow *hostWindow = webView.window;

    if ([type isEqualToString:@"permissionQuery"]) {
        NSString *state = [[self class] permissionStateForHost:host];
        [self deliverToWebView:webView
                    javaScript:[NSString stringWithFormat:@"window.__meoGeolocationPermissionDeliver(%@,%@);",
                                [self jsQuoted:requestId], [self jsQuoted:state]]];
        return;
    }

    if ([type isEqualToString:@"clearWatch"]) {
        [BrowserLocationService cancelWatchRequestId:requestId];
        return;
    }

    if ([type isEqualToString:@"getCurrentPosition"] || [type isEqualToString:@"watchPosition"]) {
        NSDictionary *options = [body[@"options"] isKindOfClass:[NSDictionary class]] ? body[@"options"] : @{};
        NSTimeInterval timeout = 10.0;
        id timeoutValue = options[@"timeout"];
        if ([timeoutValue isKindOfClass:[NSNumber class]]) {
            timeout = MAX(1.0, [timeoutValue doubleValue] / 1000.0);
        }
        BOOL highAccuracy = [options[@"enableHighAccuracy"] boolValue];
        BOOL isWatch = [type isEqualToString:@"watchPosition"];

        [[self class] resolveSitePermissionForHost:host hostWindow:hostWindow completion:^(BOOL allowed) {
            if (!allowed) {
                [self deliverErrorToWebView:webView requestId:requestId code:1 message:@"User denied geolocation"];
                return;
            }
            [BrowserLocationService fetchCurrentLocationWithHighAccuracy:highAccuracy
                                                                 timeout:timeout
                                                              watchRequestId:isWatch ? requestId : nil
                                                              webView:webView
                                                             completion:^(CLLocation * _Nullable location, NSError * _Nullable error) {
                if (error || !location) {
                    NSInteger code = error.code == 3 ? 3 : (error.code == 1 ? 1 : 2);
                    [self deliverErrorToWebView:webView
                                        requestId:requestId
                                             code:code
                                          message:error.localizedDescription ?: @"Position unavailable"];
                    return;
                }
                [self deliverPositionToWebView:webView requestId:requestId location:location];
            }];
        }];
    }
}

#pragma mark - JS delivery

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

- (void)deliverErrorToWebView:(WKWebView *)webView
                    requestId:(NSString *)requestId
                         code:(NSInteger)code
                      message:(NSString *)message {
    NSDictionary *payload = @{
        @"error": @{
            @"code": @(code),
            @"message": message ?: @"",
        },
    };
    [self deliverPayload:payload toWebView:webView requestId:requestId];
}

- (void)deliverPositionToWebView:(WKWebView *)webView
                       requestId:(NSString *)requestId
                        location:(CLLocation *)location {
    NSDictionary *position = @{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"accuracy": @(location.horizontalAccuracy),
        @"altitude": @(location.verticalAccuracy >= 0 ? location.altitude : 0),
        @"altitudeAccuracy": @(location.verticalAccuracy >= 0 ? location.verticalAccuracy : 0),
        @"heading": @(location.course >= 0 ? location.course : -1),
        @"speed": @(location.speed >= 0 ? location.speed : -1),
        @"timestamp": @((NSInteger)(location.timestamp.timeIntervalSince1970 * 1000.0)),
    };
    [self deliverPayload:@{@"position": position} toWebView:webView requestId:requestId];
}

- (void)deliverPayload:(NSDictionary *)payload
            toWebView:(WKWebView *)webView
            requestId:(NSString *)requestId {
    if (!webView || requestId.length == 0) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) {
        return;
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.__meoGeolocationDeliver(%@,%@);",
                    [self jsQuoted:requestId], json];
    [self deliverToWebView:webView javaScript:js];
}

@end
