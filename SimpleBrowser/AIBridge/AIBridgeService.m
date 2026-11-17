#import "AIBridgeService.h"
#import "AIBridgePreferences.h"
#import "AIBridgeHTTPServer.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeJobQueue.h"
#import "AIBridgeDOMProvider.h"
#import "AIBridgeUpstreamClient.h"
#import "AIBridgeToolSimulator.h"
#import "AIBridgeSidebarController.h"
#import "BrowserTab.h"
#import "BrowserWebView.h"
#import "BrowserWindowController.h"
#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

NSNotificationName const AIBridgeServiceStateDidChangeNotification = @"AIBridgeServiceStateDidChangeNotification";

@implementation AIBridgeRequestLogEntry
@end

@interface AIBridgeService ()
@property (nonatomic, strong) AIBridgeHTTPServer *server;
@property (nonatomic, strong) NSMutableArray<AIBridgeRequestLogEntry *> *logs;
@property (nonatomic, assign, readwrite, getter=isListening) BOOL listening;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
/// providerId -> 最近一次 probe 成功的时间戳，用于跳过冗长就绪等待
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *providerReadyAt;
@end

@implementation AIBridgeService

#pragma mark - Provider host matching

- (NSString *)displayNameForProviderId:(NSString *)providerId {
    NSString *pid = providerId.length ? providerId : @"deepseek";
    if ([pid isEqualToString:@"mock"]) return @"Mock 对话页";
    if ([pid isEqualToString:@"deepseek"]) return @"DeepSeek 网页";
    if ([pid isEqualToString:@"kimi"]) return @"Kimi 网页";
    if ([pid isEqualToString:@"iwencai"]) return @"问财 网页";
    if ([pid isEqualToString:@"doubao"]) return @"豆包 网页";
    if ([pid isEqualToString:@"gemini"]) return @"Gemini 网页";
    if ([pid isEqualToString:@"chatgpt"]) return @"ChatGPT 网页";
    return pid;
}

/// 与各 adapter probe / 设计文档 matchHosts 对齐。
- (NSArray<NSString *> *)matchHostsForProviderId:(NSString *)providerId {
    NSString *pid = providerId ?: @"";
    if ([pid isEqualToString:@"deepseek"]) {
        return @[ @"chat.deepseek.com", @"deepseek.com" ];
    }
    if ([pid isEqualToString:@"kimi"]) {
        return @[ @"kimi.moonshot.cn", @"www.kimi.com", @"kimi.com", @"app.kimi.ai" ];
    }
    if ([pid isEqualToString:@"iwencai"]) {
        return @[ @"www.iwencai.com", @"iwencai.com" ];
    }
    if ([pid isEqualToString:@"doubao"]) {
        return @[ @"www.doubao.com", @"doubao.com" ];
    }
    if ([pid isEqualToString:@"gemini"]) {
        return @[ @"gemini.google.com", @"bard.google.com" ];
    }
    if ([pid isEqualToString:@"chatgpt"]) {
        return @[ @"chatgpt.com", @"chat.openai.com" ];
    }
    if ([pid isEqualToString:@"mock"]) {
        return @[]; // 任意 host
    }
    return @[];
}

- (BOOL)host:(NSString *)host matchesProviderId:(NSString *)providerId {
    NSArray<NSString *> *hosts = [self matchHostsForProviderId:providerId];
    if (hosts.count == 0) {
        return YES; // mock / 未知：不拦（含 file:// 本地 mock）
    }
    NSString *h = host.lowercaseString ?: @"";
    if (h.length == 0) {
        return NO;
    }
    for (NSString *needle in hosts) {
        NSString *n = needle.lowercaseString;
        if ([h isEqualToString:n] || [h hasSuffix:[@"." stringByAppendingString:n]]) {
            return YES;
        }
        // 与 JS adapter 宽松规则对齐：子串（如 *.doubao.com）
        if (n.length >= 4 && [h containsString:n]) {
            return YES;
        }
    }
    return NO;
}

- (NSURL *)resolvedURLForTab:(BrowserTab *)tab fallback:(NSURL *)fallback {
    NSURL *live = nil;
    if (tab.webView.URL) {
        live = [BrowserWebView publicURLFromInternalURL:tab.webView.URL] ?: tab.webView.URL;
    }
    if (!live) {
        live = tab.currentOrRestorableURL;
    }
    if (!live) {
        live = fallback;
    }
    NSString *abs = live.absoluteString ?: @"";
    if (abs.length == 0 || [abs isEqualToString:@"about:blank"]) {
        NSURL *restorable = tab.currentOrRestorableURL;
        if (restorable.absoluteString.length > 0 &&
            ![restorable.absoluteString isEqualToString:@"about:blank"]) {
            return restorable;
        }
    }
    return live;
}

- (NSString *)hostMismatchMessageForProviderId:(NSString *)providerId actualHost:(NSString *)host {
    NSString *name = [self displayNameForProviderId:providerId];
    NSArray<NSString *> *hosts = [self matchHostsForProviderId:providerId];
    NSString *expect = hosts.count ? [hosts componentsJoinedByString:@" / "] : @"对应站点";
    NSString *actual = host.length ? host : @"(空)";
    return [NSString stringWithFormat:
            @"域名不匹配：当前标签是 %@，但选中的是 %@（期望 %@）。请先打开对应网站再绑定，或切换到已绑定的标签。",
            actual, name, expect];
}

- (NSURL *)homeURLForProviderId:(NSString *)providerId {
    NSString *pid = providerId ?: @"";
    if ([pid isEqualToString:@"deepseek"]) {
        return [NSURL URLWithString:@"https://chat.deepseek.com/"];
    }
    if ([pid isEqualToString:@"kimi"]) {
        return [NSURL URLWithString:@"https://www.kimi.com/"];
    }
    if ([pid isEqualToString:@"iwencai"]) {
        return [NSURL URLWithString:@"https://www.iwencai.com/"];
    }
    if ([pid isEqualToString:@"doubao"]) {
        return [NSURL URLWithString:@"https://www.doubao.com/chat/"];
    }
    if ([pid isEqualToString:@"gemini"]) {
        return [NSURL URLWithString:@"https://gemini.google.com/app"];
    }
    if ([pid isEqualToString:@"chatgpt"]) {
        return [NSURL URLWithString:@"https://chatgpt.com/"];
    }
    if ([pid isEqualToString:@"mock"]) {
        NSString *path = [NSBundle.mainBundle pathForResource:@"mock-chat" ofType:@"html" inDirectory:@"AIBridge"];
        if (!path) {
            path = [NSBundle.mainBundle pathForResource:@"mock-chat" ofType:@"html"];
        }
        return path.length ? [NSURL fileURLWithPath:path] : nil;
    }
    return nil;
}

+ (AIBridgeService *)sharedService {
    static AIBridgeService *svc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        svc = [[AIBridgeService alloc] init];
    });
    return svc;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _server = [[AIBridgeHTTPServer alloc] init];
        _logs = [NSMutableArray array];
        _providerReadyAt = [NSMutableDictionary dictionary];
        __weak typeof(self) weakSelf = self;
        _server.requestHandler = ^(NSString *method, NSString *path,
                                   NSDictionary<NSString *, NSString *> *headers,
                                   NSData *body,
                                   AIBridgeHTTPRespondBlock respond) {
            [weakSelf handleMethod:method path:path headers:headers body:body respond:respond];
        };
    }
    return self;
}

- (NSArray<AIBridgeRequestLogEntry *> *)recentRequests {
    return [self.logs copy];
}

- (NSString *)statusText {
    if (!self.listening) {
        return @"服务未启动";
    }
    AIBridgeJobQueue *q = AIBridgeJobQueue.sharedQueue;
    if (q.isBusy) {
        if (q.pendingCount > 0) {
            return [NSString stringWithFormat:@"生成中… 排队 %lu（卡死可点「重启服务」）",
                    (unsigned long)q.pendingCount];
        }
        return @"生成中…";
    }
    if (q.pendingCount > 0) {
        return [NSString stringWithFormat:@"排队 %lu", (unsigned long)q.pendingCount];
    }
    return @"空闲";
}

/// 本机局域网 IPv4（优先 en0/en1），无则 nil。
- (nullable NSString *)preferredLANIPv4 {
    NSMutableArray<NSString *> *preferred = [NSMutableArray array];
    NSMutableArray<NSString *> *others = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) {
        return nil;
    }
    for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) {
            continue;
        }
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        char host[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
        if (!inet_ntop(AF_INET, &addr->sin_addr, host, sizeof(host))) {
            continue;
        }
        NSString *ip = [NSString stringWithUTF8String:host];
        if (ip.length == 0 || [ip hasPrefix:@"127."] || [ip hasPrefix:@"169.254."]) {
            continue;
        }
        NSString *name = ifa->ifa_name ? [NSString stringWithUTF8String:ifa->ifa_name] : @"";
        if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
            [preferred addObject:ip];
        } else {
            [others addObject:ip];
        }
    }
    freeifaddrs(interfaces);
    if (preferred.count > 0) {
        return preferred.firstObject;
    }
    return others.firstObject;
}

- (NSString *)baseURLString {
    NSInteger port = self.listeningPort > 0 ? self.listeningPort : AIBridgePreferences.sharedPreferences.port;
    NSString *lan = [self preferredLANIPv4];
    if (lan.length > 0) {
        return [NSString stringWithFormat:@"http://%@:%ld", lan, (long)port];
    }
    return [NSString stringWithFormat:@"http://127.0.0.1:%ld", (long)port];
}

- (void)notify {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AIBridgeServiceStateDidChangeNotification object:self];
    });
}

- (BOOL)startServer:(NSError **)error {
    AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
    [prefs ensureToken];
    NSError *local = nil;
    BOOL ok = [self.server startOnPort:prefs.port error:&local];
    if (!ok) {
        if (error) {
            *error = local;
        }
        return NO;
    }
    prefs.serverEnabled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.listening = self.server.isRunning;
        self.listeningPort = self.server.listeningPort > 0 ? self.server.listeningPort : prefs.port;
        [self notify];
    });
    self.listening = YES;
    self.listeningPort = prefs.port;
    [self notify];
    return YES;
}

- (void)stopServer {
    [self.server stop];
    AIBridgePreferences.sharedPreferences.serverEnabled = NO;
    self.listening = NO;
    self.listeningPort = 0;
    [self notify];
}

- (void)scheduleListenerRestart {
    [self.server stop];
    self.listening = NO;
    self.listeningPort = 0;
    [self notify];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *err = nil;
        if ([strongSelf startServer:&err]) {
            AIBridgePreferences.sharedPreferences.serverEnabled = YES;
        } else {
            NSLog(@"[AIBridge] restart listen failed: %@", err.localizedDescription);
        }
        [strongSelf notify];
    });
}

- (void)purgeQueueAndAbortBoundPages {
    void (^work)(void) = ^{
        [[AIBridgeJobQueue sharedQueue] resetNow];
        [self.logs removeAllObjects];
        [self.providerReadyAt removeAllObjects];
        [self notify];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
}

- (BOOL)restartServer:(NSError **)error {
    (void)error;
    void (^work)(void) = ^{
        [self purgeQueueAndAbortBoundPages];
        [self scheduleListenerRestart];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
    return YES;
}

- (AIBridgeBinding *)bindCurrentTab:(BrowserTab *)tab
                            pageURL:(NSURL *)url
                         providerId:(NSString *)providerId
                          sessionId:(NSString *)sessionId
                              error:(NSError **)error {
    if (!tab) {
        if (error) {
            *error = [NSError errorWithDomain:@"AIBridgeService" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"无当前标签"}];
        }
        return nil;
    }
    NSString *pid = providerId.length ? providerId : @"deepseek";
    NSURL *resolved = [self resolvedURLForTab:tab fallback:url];
    NSString *host = resolved.host ?: @"";
    // mock / file：host 可空
    NSArray *expectHosts = [self matchHostsForProviderId:pid];
    if (expectHosts.count > 0 && ![self host:host matchesProviderId:pid]) {
        if (error) {
            *error = [NSError errorWithDomain:@"AIBridgeService" code:2
                                    userInfo:@{NSLocalizedDescriptionKey:
                                                   [self hostMismatchMessageForProviderId:pid actualHost:host]}];
        }
        return nil;
    }
    NSString *name = [self displayNameForProviderId:pid];
    AIBridgeBinding *binding = [[AIBridgeRegistry sharedRegistry] bindTab:tab
                                                               providerId:pid
                                                              displayName:name
                                                                  pageURL:resolved.absoluteString ?: url.absoluteString
                                                                sessionId:sessionId];
    [self notify];
    return binding;
}

- (void)unbindBindingId:(NSString *)bindingId {
    [[AIBridgeRegistry sharedRegistry] unbindBindingId:bindingId];
    [self notify];
}

- (void)unbindProviderId:(NSString *)providerId {
    [[AIBridgeRegistry sharedRegistry] unbindProviderId:providerId];
    [self notify];
}

- (AIBridgeBinding *)resolveBindingForModelId:(NSString *)modelId error:(NSError **)error {
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForModelId:modelId];
    if (b) {
        return b;
    }
    if (error) {
        *error = [NSError errorWithDomain:@"AIBridgeService" code:404
                                userInfo:@{NSLocalizedDescriptionKey: @"model not bound"}];
    }
    return nil;
}

- (void)unbindAllProviders {
    [[AIBridgeRegistry sharedRegistry] unbindAll];
    [self notify];
}

- (void)cancelAllJobs {
    // 同步清空，避免 cancel 返回后队列仍显示 busy
    [[AIBridgeJobQueue sharedQueue] resetNow];
    [self.providerReadyAt removeAllObjects];
    [self notify];
}

- (void)newChatForBindingId:(NSString *)bindingId
                 completion:(void (^)(BOOL, NSString *_Nullable))completion {
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForId:bindingId];
    if (!b || !b.tab) {
        if (completion) {
            completion(NO, @"未绑定");
        }
        return;
    }
    [self newChatOnBinding:b completion:completion];
}

- (void)newChatForProviderId:(NSString *)providerId
                  completion:(void (^)(BOOL, NSString *_Nullable))completion {
    AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:providerId];
    if (!b || !b.tab) {
        if (completion) {
            completion(NO, @"未绑定");
        }
        return;
    }
    [self newChatOnBinding:b completion:completion];
}

- (void)newChatOnBinding:(AIBridgeBinding *)b
              completion:(void (^)(BOOL, NSString *_Nullable))completion {
    NSString *providerId = b.providerId ?: @"";
    [b.tab wakeFromHibernationIfNeeded];
    WKWebView *wv = b.tab.webView ?: [b.tab ensureWebView];
    if (!wv) {
        if (completion) {
            completion(NO, @"无 WebView");
        }
        return;
    }
    [[AIBridgeDOMProvider sharedProvider] newChatOnWebView:wv
                                                providerId:providerId
                                                completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error.localizedDescription);
            }
            return;
        }
        BOOL ok = [result[@"ok"] boolValue];
        NSString *detail = [result[@"error"] isKindOfClass:[NSString class]] ? result[@"error"] : (ok ? @"ok" : @"failed");
        if (completion) {
            completion(ok, detail);
        }
    }];
}

- (NSString *)curlExampleForModel:(NSString *)modelId {
    NSString *token = AIBridgePreferences.sharedPreferences.bearerToken;
    NSString *model = modelId.length ? modelId : @"bridge__deepseek";
    return [NSString stringWithFormat:
            @"curl -s %@/v1/chat/completions \\\n"
             "  -H \"Authorization: Bearer %@\" \\\n"
             "  -H \"Content-Type: application/json\" \\\n"
             "  -d '{\"model\":\"%@\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}'",
            self.baseURLString, token, model];
}

#pragma mark - HTTP

- (BOOL)authorize:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *expected = AIBridgePreferences.sharedPreferences.bearerToken;
    if (expected.length == 0) {
        return NO;
    }
    NSString *auth = headers[@"authorization"] ?: @"";
    NSString *prefix = @"bearer ";
    if (auth.length < prefix.length) {
        return NO;
    }
    if (![[auth substringToIndex:prefix.length].lowercaseString isEqualToString:prefix]) {
        return NO;
    }
    NSString *token = [[auth substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return [token isEqualToString:expected];
}

- (void)handleMethod:(NSString *)method
                path:(NSString *)path
             headers:(NSDictionary<NSString *, NSString *> *)headers
                body:(NSData *)body
             respond:(AIBridgeHTTPRespondBlock)respond {
    NSString *pathOnly = path;
    NSRange q = [path rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        pathOnly = [path substringToIndex:q.location];
    }

    if ([method isEqualToString:@"OPTIONS"]) {
        respond(204, @"text/plain", [NSData data]);
        return;
    }

    if ([pathOnly isEqualToString:@"/health"] && [method isEqualToString:@"GET"]) {
        [self handleHealth:respond];
        return;
    }

    if (![self authorize:headers]) {
        [self respondJSON:respond status:401 object:@{@"error": @{@"message": @"unauthorized", @"type": @"auth"}}];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/models"] && [method isEqualToString:@"GET"]) {
        [self handleModels:respond];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/chat/completions"] && [method isEqualToString:@"POST"]) {
        [self handleChatCompletions:body respond:respond];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/bridge/new_chat"] && [method isEqualToString:@"POST"]) {
        [self handleNewChat:body respond:respond];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/bridge/cancel"] && [method isEqualToString:@"POST"]) {
        [self cancelAllJobs];
        [self respondJSON:respond status:200 object:@{@"ok": @YES, @"cancelled": @YES}];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/bridge/restart"] && [method isEqualToString:@"POST"]) {
        // 先回包，再异步清队列并热重启监听，避免连接被中途掐断
        NSInteger port = self.listeningPort > 0 ? self.listeningPort : AIBridgePreferences.sharedPreferences.port;
        [self respondJSON:respond status:200 object:@{
            @"ok": @YES,
            @"restarting": @YES,
            @"port": @(port),
            @"baseURL": self.baseURLString ?: @""
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self restartServer:nil];
        });
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/bridge/inspect"] && ([method isEqualToString:@"GET"] || [method isEqualToString:@"POST"])) {
        [self handleInspect:body respond:respond];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/bridge/bind"] && [method isEqualToString:@"POST"]) {
        [self handleBindProvider:body respond:respond];
        return;
    }

    [self respondJSON:respond status:404 object:@{@"error": @{@"message": @"not found", @"type": @"invalid_request"}}];
}

- (void)handleHealth:(AIBridgeHTTPRespondBlock)respond {
    NSMutableArray *bindings = [NSMutableArray array];
    for (AIBridgeBinding *b in AIBridgeRegistry.sharedRegistry.allBindings) {
        [bindings addObject:@{
            @"id": b.bindingId ?: @"",
            @"model": b.modelId ?: @"",
            @"provider": b.providerId ?: @"",
            @"session_id": b.sessionId ?: @"",
            @"url": b.pageURL ?: @"",
            @"hasTab": @(b.tab != nil)
        }];
    }
    AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
    AIBridgeJobQueue *q = AIBridgeJobQueue.sharedQueue;
    NSString *lan = [self preferredLANIPv4] ?: @"";
    NSDictionary *payload = @{
        @"ok": @YES,
        @"listening": @(self.listening),
        @"host": @"0.0.0.0",
        @"port": @(self.listeningPort),
        @"baseURL": self.baseURLString ?: @"",
        @"lanIP": lan,
        @"bindings": bindings,
        @"queue": @{
            @"busy": @(q.isBusy),
            @"pending": @(q.pendingCount),
            @"active": @(q.activeJobCount),
            @"maxPending": @(q.maxPending),
            @"note": @"same provider single-flight (busy→429); different providers parallel"
        },
        @"upstream": @{
            @"ollamaBaseURL": prefs.ollamaBaseURL ?: @"",
            @"openaiBaseURL": prefs.openaiBaseURL ?: @"",
            @"openaiConfigured": @(prefs.openaiBaseURL.length > 0)
        },
        @"models": @{
            @"bridge": @"bridge__<provider>",
            @"ollama": @"ollama__<tag>",
            @"openai": @"openai__<model>"
        },
        @"status": self.statusText ?: @""
    };
    [self respondJSON:respond status:200 object:payload];
}

- (void)handleModels:(AIBridgeHTTPRespondBlock)respond {
    NSMutableArray *data = [NSMutableArray array];
    for (AIBridgeBinding *b in AIBridgeRegistry.sharedRegistry.allBindings) {
        if (!b.tab) {
            continue;
        }
        [data addObject:@{
            @"id": b.modelId ?: @"",
            @"object": @"model",
            @"owned_by": @"meo-bridge",
            @"provider": b.providerId ?: @"",
            @"binding_id": b.bindingId ?: @"",
            @"session_id": b.sessionId ?: @""
        }];
    }
    // 静态提示条目，便于客户端发现前缀约定
    [data addObject:@{@"id": @"ollama__*", @"object": @"model", @"owned_by": @"ollama-prefix"}];
    if (AIBridgePreferences.sharedPreferences.openaiBaseURL.length) {
        [data addObject:@{@"id": @"openai__*", @"object": @"model", @"owned_by": @"openai-prefix"}];
    }
    [self respondJSON:respond status:200 object:@{@"object": @"list", @"data": data}];
}

- (NSString *)extractUserPrompt:(NSDictionary *)json {
    id messages = json[@"messages"];
    if (![messages isKindOfClass:[NSArray class]]) {
        return nil;
    }
    for (NSInteger i = (NSInteger)((NSArray *)messages).count - 1; i >= 0; i--) {
        id m = ((NSArray *)messages)[(NSUInteger)i];
        if (![m isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *role = m[@"role"];
        if (![role isEqualToString:@"user"]) {
            continue;
        }
        id content = m[@"content"];
        if ([content isKindOfClass:[NSString class]]) {
            return content;
        }
        if ([content isKindOfClass:[NSArray class]]) {
            NSMutableString *acc = [NSMutableString string];
            for (id part in (NSArray *)content) {
                if ([part isKindOfClass:[NSDictionary class]] && [part[@"type"] isEqualToString:@"text"]) {
                    id t = part[@"text"];
                    if ([t isKindOfClass:[NSString class]]) {
                        [acc appendString:t];
                    }
                }
            }
            return acc.length ? acc : @"";
        }
    }
    return nil;
}

/// 单文件上限 20MB（设计 D4）。
static const unsigned long long kAIBridgeAttachmentMaxBytes = 20ULL * 1024ULL * 1024ULL;

- (nullable NSString *)guessMIMEForPath:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    if (!ext.length) return @"application/octet-stream";
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"txt": @"text/plain",
            @"md": @"text/markdown",
            @"csv": @"text/csv",
            @"json": @"application/json",
            @"pdf": @"application/pdf",
            @"png": @"image/png",
            @"jpg": @"image/jpeg",
            @"jpeg": @"image/jpeg",
            @"gif": @"image/gif",
            @"webp": @"image/webp",
            @"doc": @"application/msword",
            @"docx": @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            @"xls": @"application/vnd.ms-excel",
            @"xlsx": @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            @"ppt": @"application/vnd.ms-powerpoint",
            @"pptx": @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
            @"html": @"text/html",
            @"htm": @"text/html",
            @"js": @"text/javascript",
            @"ts": @"text/typescript",
            @"py": @"text/x-python",
            @"c": @"text/x-c",
            @"cpp": @"text/x-c++",
            @"h": @"text/x-c",
            @"java": @"text/x-java",
            @"go": @"text/x-go",
            @"rs": @"text/x-rust",
            @"swift": @"text/x-swift",
            @"log": @"text/plain",
            @"yaml": @"text/yaml",
            @"yml": @"text/yaml",
        };
    });
    return map[ext] ?: @"application/octet-stream";
}

/// 解析 meo_attachments → [{name,mime,base64}]；失败时 *outError 有可读说明。
- (nullable NSArray<NSDictionary *> *)loadAttachmentsFromJSON:(NSDictionary *)json
                                                        error:(NSString *_Nullable *_Nullable)outError {
    id raw = json[@"meo_attachments"];
    if (raw == nil) {
        return @[];
    }
    if (![raw isKindOfClass:[NSArray class]]) {
        if (outError) *outError = @"meo_attachments must be an array";
        return nil;
    }
    NSArray *arr = (NSArray *)raw;
    if (arr.count == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id item in arr) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            if (outError) *outError = @"meo_attachments item must be object";
            return nil;
        }
        NSDictionary *d = item;
        NSString *path = [d[@"path"] isKindOfClass:[NSString class]] ? d[@"path"] : nil;
        NSString *name = [d[@"name"] isKindOfClass:[NSString class]] ? d[@"name"] : nil;
        NSString *mime = [d[@"mime"] isKindOfClass:[NSString class]] ? d[@"mime"] : nil;
        if (path.length == 0) {
            if (outError) *outError = @"meo_attachments.path required";
            return nil;
        }
        if (![path hasPrefix:@"/"]) {
            if (outError) *outError = @"meo_attachments.path must be absolute";
            return nil;
        }
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] || isDir) {
            if (outError) *outError = [NSString stringWithFormat:@"附件不存在：%@", path.lastPathComponent];
            return nil;
        }
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        unsigned long long sz = [attrs fileSize];
        if (sz > kAIBridgeAttachmentMaxBytes) {
            if (outError) *outError = [NSString stringWithFormat:@"附件超过 20MB 上限：%@", path.lastPathComponent];
            return nil;
        }
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (!data) {
            if (outError) *outError = [NSString stringWithFormat:@"无法读取附件：%@", path.lastPathComponent];
            return nil;
        }
        NSString *fileName = name.length ? name : path.lastPathComponent;
        NSString *contentType = mime.length ? mime : [self guessMIMEForPath:path];
        NSString *b64 = [data base64EncodedStringWithOptions:0];
        [out addObject:@{
            @"name": fileName ?: @"file",
            @"mime": contentType ?: @"application/octet-stream",
            @"base64": b64 ?: @""
        }];
    }
    return out;
}

- (BOOL)boolValue:(id)v {
    if ([v isKindOfClass:[NSNumber class]]) {
        return [v boolValue];
    }
    if ([v isKindOfClass:[NSString class]]) {
        return [v boolValue];
    }
    return NO;
}

- (NSData *)rewriteModelInBody:(NSData *)body toModel:(NSString *)model {
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![obj isKindOfClass:[NSMutableDictionary class]] && [obj isKindOfClass:[NSDictionary class]]) {
        obj = [obj mutableCopy];
    }
    if (![obj isKindOfClass:[NSMutableDictionary class]]) {
        return body;
    }
    ((NSMutableDictionary *)obj)[@"model"] = model ?: @"";
    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil] ?: body;
}

- (void)handleChatCompletions:(NSData *)body respond:(AIBridgeHTTPRespondBlock)respond {
    NSError *err = nil;
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:&err] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) {
        [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"invalid json", @"type": @"invalid_request"}}];
        return;
    }
    NSDictionary *json = obj;
    NSString *model = [json[@"model"] isKindOfClass:[NSString class]] ? json[@"model"] : @"";
    if (model.length == 0) {
        [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"model required", @"type": @"invalid_request"}}];
        return;
    }

    BOOL stream = [self boolValue:json[@"stream"]];

    if ([model hasPrefix:@"ollama__"]) {
        NSString *upstreamModel = [model substringFromIndex:@"ollama__".length];
        AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
        NSData *fwd = [self rewriteModelInBody:body toModel:upstreamModel];
        [self forwardUpstream:fwd
                      baseURL:prefs.ollamaBaseURL
                       apiKey:nil
                        model:model
                       stream:stream
                      respond:respond];
        return;
    }

    if ([model hasPrefix:@"openai__"]) {
        NSString *upstreamModel = [model substringFromIndex:@"openai__".length];
        AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
        if (prefs.openaiBaseURL.length == 0) {
            [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"openaiBaseURL not configured", @"type": @"invalid_request"}}];
            return;
        }
        NSData *fwd = [self rewriteModelInBody:body toModel:upstreamModel];
        [self forwardUpstream:fwd
                      baseURL:prefs.openaiBaseURL
                       apiKey:prefs.openaiApiKey
                        model:model
                       stream:stream
                      respond:respond];
        return;
    }

    if (![model hasPrefix:@"bridge__"]) {
        [self respondJSON:respond status:400 object:@{
            @"error": @{
                @"message": @"model must start with bridge__ / ollama__ / openai__",
                @"type": @"invalid_request"
            }
        }];
        return;
    }

    NSError *resolveErr = nil;
    AIBridgeBinding *binding = [self resolveBindingForModelId:model error:&resolveErr];
    if (!binding || !binding.tab) {
        NSInteger code = resolveErr.code == 409 ? 409 : 404;
        [self respondJSON:respond status:code object:@{
            @"error": @{
                @"message": resolveErr.localizedDescription ?: @"model not bound",
                @"type": code == 409 ? @"ambiguous_model" : @"invalid_request"
            }
        }];
        return;
    }
    NSString *attachErr = nil;
    NSArray<NSDictionary *> *attachments = [self loadAttachmentsFromJSON:json error:&attachErr];
    if (!attachments) {
        [self respondJSON:respond status:400 object:@{
            @"error": @{
                @"message": attachErr ?: @"invalid meo_attachments",
                @"type": @"invalid_request"
            }
        }];
        return;
    }

    BOOL agentMode = [AIBridgeToolSimulator shouldEnableForRequest:json];
    NSString *prompt = nil;
    if (agentMode) {
        prompt = [AIBridgeToolSimulator buildWebpagePromptFromRequest:json];
        if (prompt.length == 0) {
            [self respondJSON:respond status:400 object:@{
                @"error": @{@"message": @"unable to build agent prompt", @"type": @"invalid_request"}
            }];
            return;
        }
    } else {
        prompt = [self extractUserPrompt:json];
        if (prompt == nil) {
            [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"messages must include user content", @"type": @"invalid_request"}}];
            return;
        }
        if (prompt.length == 0 && attachments.count == 0) {
            [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"messages must include user content or meo_attachments", @"type": @"invalid_request"}}];
            return;
        }
    }

    // 409：先校验绑定标签域名，再 probe 登录/输入框
    NSString *providerId = binding.providerId ?: @"deepseek";
    if (attachments.count > 0 && ![providerId isEqualToString:@"deepseek"]) {
        [self respondJSON:respond status:400 object:@{
            @"error": @{
                @"message": @"attachments currently supported only for bridge__deepseek",
                @"type": @"attachments_unsupported"
            }
        }];
        return;
    }
    // meo_timeout_ms：单次网页任务超时（默认 60s，上限 180s）
    NSInteger jobTimeoutMs = 60000;
    id timeoutRaw = json[@"meo_timeout_ms"] ?: json[@"timeout_ms"];
    if ([timeoutRaw isKindOfClass:[NSNumber class]]) {
        jobTimeoutMs = [(NSNumber *)timeoutRaw integerValue];
    } else if ([timeoutRaw isKindOfClass:[NSString class]]) {
        jobTimeoutMs = [(NSString *)timeoutRaw integerValue];
    }
    if (jobTimeoutMs < 10000) jobTimeoutMs = 10000;
    if (jobTimeoutMs > 180000) jobTimeoutMs = 180000;

    // 立刻入队占槽：同 provider 串行；就绪探测只在真正开跑时做，避免并发请求抢同一 WebView 把 JS 队列堵死。
    NSTimeInterval t0 = [NSDate date].timeIntervalSince1970;
    __weak typeof(self) weakSelf = self;
    AIBridgeJobPrepareBlock prepare = ^(WKWebView *wv, BrowserTab *tab, NSString *pid, AIBridgeJobPrepareCompletion prepDone) {
        __strong typeof(weakSelf) strongBoot = weakSelf;
        if (!strongBoot) {
            if (prepDone) prepDone(NO, 503, @"bridge gone", @"bridge_error");
            return;
        }
        if (binding.tab) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"AIBridgeRequestPrepareBoundTabNotification"
                              object:strongBoot
                            userInfo:@{ @"tab": binding.tab }];
        }
        [binding.tab wakeFromHibernationIfNeeded];
        if (binding.tab.pendingRestorableLoad) {
            [binding.tab loadPendingRestorableURLIfNeeded];
        }
        if (!wv) {
            if (prepDone) prepDone(NO, 503, @"webView unavailable", @"bridge_error");
            return;
        }
        NSNumber *readyAt = strongBoot.providerReadyAt[pid ?: @""];
        BOOL warm = readyAt && (NSDate.date.timeIntervalSince1970 - readyAt.doubleValue) < 45.0;
        // 热路径：跳过 host/probe，直接发（sendAndWait 内仍有 ensureReady）
        if (warm) {
            if (prepDone) prepDone(YES, 200, nil, nil);
            return;
        }
        NSTimeInterval hostTimeout = 8.0;
        NSTimeInterval probeTimeout = 8.0;
        [strongBoot waitUntilDocumentHostReadyOnWebView:wv
                                                    tab:tab ?: binding.tab
                                             providerId:pid
                                                timeout:hostTimeout
                                             completion:^(BOOL ok, NSString *liveHost, NSString *liveAbs, NSString *failDetail) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                if (prepDone) prepDone(NO, 503, @"bridge gone", @"bridge_error");
                return;
            }
            if (!ok) {
                NSString *msg = failDetail.length ? failDetail
                    : @"绑定标签页面尚未加载。请稍候重试；若持续失败，可在侧栏点「显示」查看该网页。";
                BOOL mismatch = [msg containsString:@"域名不匹配"];
                if (prepDone) {
                    prepDone(NO, mismatch ? 409 : 503, msg, mismatch ? @"host_mismatch" : @"bridge_error");
                }
                (void)liveHost;
                return;
            }
            binding.pageURL = liveAbs;
            binding.tabTitle = binding.tab.title;
            [strongSelf ensureReadyAndProbeUntilReadyOnWebView:wv
                                                    providerId:pid
                                                       timeout:probeTimeout
                                                    completion:^(NSDictionary *probe, NSString *errorDetail, NSString *errorType) {
                (void)probe;
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (!innerSelf) {
                    if (prepDone) prepDone(NO, 503, @"bridge gone", @"bridge_error");
                    return;
                }
                if (errorDetail.length) {
                    [innerSelf.providerReadyAt removeObjectForKey:pid ?: @""];
                    if (prepDone) {
                        prepDone(NO, 409, errorDetail, errorType.length ? errorType : @"login_required");
                    }
                    return;
                }
                if (pid.length) {
                    innerSelf.providerReadyAt[pid] = @(NSDate.date.timeIntervalSince1970);
                }
                if (prepDone) prepDone(YES, 200, nil, nil);
            }];
        }];
    };

    [[AIBridgeJobQueue sharedQueue] enqueueModel:model
                                          prompt:prompt
                                     attachments:attachments
                                       timeoutMs:jobTimeoutMs
                                         prepare:prepare
                                      completion:^(NSDictionary *result, NSInteger httpStatus, NSString *errorMessage) {
        __strong typeof(weakSelf) innerSelf = weakSelf;
        if (!innerSelf) return;
        if (httpStatus != 200) {
            NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
            [innerSelf appendLogModel:model status:httpStatus duration:dt detail:errorMessage];
            [innerSelf notify];
            NSString *errType = @"bridge_error";
            NSString *msg = errorMessage ?: @"failed";
            if ([msg containsString:@"attachments_unsupported"]) {
                errType = @"attachments_unsupported";
            } else if ([msg containsString:@"attach_timeout"]) {
                errType = @"attach_timeout";
            } else if ([msg containsString:@"attach"] || [result[@"phase"] isEqual:@"attach"]) {
                errType = @"attach_failed";
            } else if ([msg containsString:@"域名不匹配"]) {
                errType = @"host_mismatch";
            } else if ([msg containsString:@"登录"] || [msg containsString:@"输入框"]) {
                errType = @"login_required";
            }
            [innerSelf respondJSON:respond status:httpStatus object:@{
                @"error": @{
                    @"message": msg,
                    @"type": errType
                }
            }];
            return;
        }
        if (providerId.length) {
            innerSelf.providerReadyAt[providerId] = @(NSDate.date.timeIntervalSince1970);
        }
        NSString *text = result[@"text"] ?: @"";
        if (agentMode) {
            [innerSelf finishAgentCompletionWithText:text
                                               model:model
                                             request:json
                                              stream:stream
                                           startedAt:t0
                                      repairAttempted:NO
                                             respond:respond];
        } else {
            NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
            [innerSelf appendLogModel:model status:200 duration:dt detail:nil];
            [innerSelf notify];
            if (stream) {
                [innerSelf respondFakeSSE:respond model:model text:text created:(NSInteger)t0];
            } else {
                [innerSelf respondCompletion:respond model:model text:text created:(NSInteger)t0];
            }
        }
    }];
}

static NSString * const kMeoBridgeDocHostJS =
    @"(function(){try{"
     "  return JSON.stringify({"
     "    host: String(location.hostname||''),"
     "    href: String(location.href||''),"
     "    ready: String(document.readyState||'')"
     "  });"
     "}catch(e){return JSON.stringify({host:'',href:'',ready:'',error:String(e)});}})()";

/// 用 document.location.hostname 判断就绪（webView.URL 在临时导航期会「超前」于文档）。
/// 必须在主线程调用（或由此方法自行跳转到主线程）。
- (void)waitUntilDocumentHostReadyOnWebView:(WKWebView *)webView
                                        tab:(BrowserTab *)tab
                                 providerId:(NSString *)providerId
                                    timeout:(NSTimeInterval)timeout
                                 completion:(void (^)(BOOL ok, NSString *liveHost, NSString *liveAbs, NSString *failDetail))completion {
    if (!completion) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self waitUntilDocumentHostReadyOnWebView:webView
                                                  tab:tab
                                           providerId:providerId
                                              timeout:timeout
                                           completion:completion];
        });
        return;
    }
    if (!webView) {
        completion(NO, @"", @"", @"webView unavailable");
        return;
    }
    NSTimeInterval deadline = NSDate.date.timeIntervalSince1970 + MAX(timeout, 1.0);
    const NSTimeInterval interval = 0.5;
    __weak typeof(self) weakSelf = self;
    // 强引用 __block 保活；weak 仅用于自调度，避免 retain cycle 警告。
    // 切勿只保留 weak：方法返回后若无强引用，轮询会停死。
    __block void (^poll)(void) = nil;
    __weak __block void (^weakPoll)(void) = nil;
    __block BOOL finished = NO;
    void (^finishOnce)(BOOL, NSString *, NSString *, NSString *) =
        ^(BOOL ok, NSString *liveHost, NSString *liveAbs, NSString *failDetail) {
            if (finished) return;
            finished = YES;
            poll = nil; // 断开强引用，结束轮询
            completion(ok, liveHost ?: @"", liveAbs ?: @"", failDetail);
        };
    // 硬超时：不依赖 evaluateJavaScript 一定回调
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(timeout, 1.0) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (finished) return;
        NSURL *raw = webView.URL;
        finishOnce(NO, raw.host ?: @"", raw.absoluteString ?: @"",
                   @"绑定标签页面尚未加载完成。请稍候重试；若持续失败，可在侧栏点「显示」查看该网页。");
    });
    poll = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || finished) return;
        if (NSDate.date.timeIntervalSince1970 >= deadline) {
            NSURL *raw = webView.URL;
            finishOnce(NO, raw.host ?: @"", raw.absoluteString ?: @"",
                       @"绑定标签页面尚未加载完成。请稍候重试；若持续失败，可在侧栏点「显示」查看该网页。");
            return;
        }
        NSURL *rawURL = webView.URL;
        NSString *rawAbs = rawURL.absoluteString ?: @"";
        BOOL urlBlank = rawAbs.length == 0 || [rawAbs isEqualToString:@"about:blank"];
        if (urlBlank && !webView.isLoading) {
            NSURL *target = tab.restorableURL ?: [strongSelf homeURLForProviderId:providerId];
            if (target) {
                if (tab) tab.restorableURL = target;
                [webView loadRequest:[NSURLRequest requestWithURL:target]];
            }
        }
        [webView evaluateJavaScript:kMeoBridgeDocHostJS completionHandler:^(id result, NSError *evalErr) {
            typeof(self) inner = weakSelf;
            if (!inner || finished) return;
            NSString *host = @"";
            NSString *href = @"";
            if (!evalErr && [result isKindOfClass:[NSString class]]) {
                NSData *data = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
                id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if ([obj isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *dict = (NSDictionary *)obj;
                    if ([dict[@"host"] isKindOfClass:[NSString class]]) host = dict[@"host"];
                    if ([dict[@"href"] isKindOfClass:[NSString class]]) href = dict[@"href"];
                }
            }
            if ([inner host:host matchesProviderId:providerId]) {
                finishOnce(YES, host, href.length ? href : (webView.URL.absoluteString ?: @""), nil);
                return;
            }
            void (^again)(void) = weakPoll;
            if (!again) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), again);
        }];
    };
    weakPoll = poll;
    poll();
}

/// 注入 adapter 后，在加载周期内反复 probe，直到 hostOk+输入框稳定就绪或超时。
/// 要求连续两次 probe 成功，避免 SPA 水合瞬间误判。
- (void)ensureReadyAndProbeUntilReadyOnWebView:(WKWebView *)webView
                                    providerId:(NSString *)providerId
                                       timeout:(NSTimeInterval)timeout
                                    completion:(void (^)(NSDictionary *_Nullable probe, NSString *_Nullable errorDetail, NSString *_Nullable errorType))completion {
    if (!completion) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self ensureReadyAndProbeUntilReadyOnWebView:webView
                                              providerId:providerId
                                                 timeout:timeout
                                              completion:completion];
        });
        return;
    }
    NSTimeInterval deadline = NSDate.date.timeIntervalSince1970 + MAX(timeout, 1.0);
    // 热路径：缩短轮询间隔；只需 1 次 probe 成功（旧逻辑连续 2 次易白白多等 ~0.6s+）
    const NSTimeInterval interval = 0.35;
    const NSInteger requiredConsecutiveOk = 1;
    __weak typeof(self) weakSelf = self;
    // 强引用 __block 保活；weak 仅用于自调度，避免 retain cycle 警告。
    // finish 时将强引用置 nil。切勿只保留 weak，否则轮询会停。
    __block void (^attempt)(void) = nil;
    __weak __block void (^weakAttempt)(void) = nil;
    __block BOOL finished = NO;
    __block NSInteger consecutiveOk = 0;
    void (^finishOnce)(NSDictionary *, NSString *, NSString *) =
        ^(NSDictionary *probe, NSString *errorDetail, NSString *errorType) {
            if (finished) return;
            finished = YES;
            attempt = nil;
            completion(probe, errorDetail, errorType);
        };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(timeout, 1.0) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        finishOnce(nil, @"AI 网页就绪超时：找不到输入框或域名未匹配，请确认已登录 DeepSeek。", @"login_required");
    });
    attempt = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || finished) return;
        if (NSDate.date.timeIntervalSince1970 >= deadline) {
            finishOnce(nil, @"AI 网页就绪超时：找不到输入框或域名未匹配，请确认已登录 DeepSeek。", @"login_required");
            return;
        }
        [[AIBridgeDOMProvider sharedProvider] ensureReadyOnWebView:webView providerId:providerId completion:^(NSError *readyErr) {
            typeof(self) inner = weakSelf;
            if (!inner || finished) return;
            if (readyErr) {
                consecutiveOk = 0;
                void (^again)(void) = weakAttempt;
                if (!again) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), again);
                return;
            }
            [[AIBridgeDOMProvider sharedProvider] probeOnWebView:webView completion:^(NSDictionary *probe, NSError *probeErr) {
                typeof(self) probeSelf = weakSelf;
                if (!probeSelf || finished) return;
                BOOL hostOk = YES;
                if (probe[@"hostOk"] != nil) {
                    hostOk = [probe[@"hostOk"] boolValue];
                }
                BOOL okFlag = [probe[@"ok"] boolValue];
                BOOL hasInput = [probe[@"loggedIn"] boolValue] || [probe[@"hasInput"] boolValue];
                BOOL docReady = YES;
                if (probe[@"docReady"] != nil) {
                    docReady = [probe[@"docReady"] boolValue];
                } else if ([probe[@"readyState"] isKindOfClass:[NSString class]]) {
                    NSString *rs = probe[@"readyState"];
                    docReady = [rs isEqualToString:@"interactive"] || [rs isEqualToString:@"complete"];
                }
                BOOL detailLoading = [probe[@"detail"] isEqual:@"document loading"];
                BOOL ready = okFlag || (hasInput && hostOk && docReady && !detailLoading);
                {
                    NSString *line = [NSString stringWithFormat:
                        @"%@ probe okFlag=%d hostOk=%d hasInput=%d docReady=%d ready=%d consec=%ld detail=%@ err=%@\n",
                        [NSDate date], okFlag, hostOk, hasInput, docReady, ready, (long)consecutiveOk,
                        probe[@"detail"] ?: @"",
                        probeErr.localizedDescription ?: @""];
                    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MeoBrowser/aibridge.log"];
                    [[NSFileManager defaultManager] createDirectoryAtPath:logPath.stringByDeletingLastPathComponent
                                             withIntermediateDirectories:YES attributes:nil error:nil];
                    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
                    if (!fh) {
                        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    } else {
                        [fh seekToEndOfFile];
                        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                        [fh closeFile];
                    }
                }
                if (!probeErr && hostOk && ready) {
                    consecutiveOk += 1;
                    if (consecutiveOk >= requiredConsecutiveOk) {
                        finishOnce(probe, nil, nil);
                        return;
                    }
                    void (^again)(void) = weakAttempt;
                    if (!again) return;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), again);
                    return;
                }
                consecutiveOk = 0;
                BOOL stillLoading = !hostOk
                    || !docReady
                    || detailLoading
                    || (probe[@"host"] && [probe[@"host"] isEqual:@""])
                    || [probe[@"detail"] isEqual:@"host mismatch"]
                    || [probe[@"detail"] isEqual:@"input not found (login?)"]
                    || hasInput == NO;
                if (stillLoading && NSDate.date.timeIntervalSince1970 < deadline) {
                    void (^again)(void) = weakAttempt;
                    if (!again) return;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), again);
                    return;
                }
                NSString *detail = nil;
                NSString *type = @"login_required";
                if (!hostOk || [probe[@"detail"] isEqual:@"host mismatch"]) {
                    NSString *probeHost = [probe[@"host"] isKindOfClass:[NSString class]] ? probe[@"host"] : @"";
                    detail = [probeSelf hostMismatchMessageForProviderId:providerId actualHost:probeHost];
                    type = @"host_mismatch";
                } else if (probeErr) {
                    detail = probeErr.localizedDescription;
                    type = @"bridge_error";
                } else if ([probe[@"detail"] isKindOfClass:[NSString class]] && [probe[@"detail"] length]) {
                    NSString *raw = probe[@"detail"];
                    if ([raw containsString:@"input not found"] || [raw containsString:@"login"]) {
                        detail = [NSString stringWithFormat:@"%@ 未就绪：找不到输入框，请确认已登录并打开对话页。",
                                  [probeSelf displayNameForProviderId:providerId]];
                    } else if ([raw containsString:@"document loading"]) {
                        detail = [NSString stringWithFormat:@"%@ 页面仍在加载，请稍候再试。",
                                  [probeSelf displayNameForProviderId:providerId]];
                    } else {
                        detail = raw;
                    }
                } else {
                    detail = @"login required";
                }
                finishOnce(probe, detail, type);
            }];
        }];
    };
    weakAttempt = attempt;
    attempt();
}

- (void)waitUntilModelPageReady:(NSString *)modelId
                        timeout:(NSTimeInterval)timeout
                     completion:(void (^)(BOOL ok, NSString *_Nullable errorDetail))completion {
    if (!completion) return;
    void (^finish)(BOOL, NSString *) = ^(BOOL ok, NSString *detail) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(ok, detail);
        });
    };
    if (modelId.length == 0) {
        finish(NO, @"model 为空");
        return;
    }
    NSError *resolveErr = nil;
    AIBridgeBinding *binding = [self resolveBindingForModelId:modelId error:&resolveErr];
    if (!binding || !binding.tab) {
        finish(NO, resolveErr.localizedDescription ?: @"model not bound");
        return;
    }
    NSString *providerId = binding.providerId ?: @"deepseek";
    NSTimeInterval t = MAX(timeout, 1.0);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongBoot = weakSelf;
        if (!strongBoot) return;
        if (binding.tab) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"AIBridgeRequestPrepareBoundTabNotification"
                              object:strongBoot
                            userInfo:@{ @"tab": binding.tab }];
        }
        [binding.tab wakeFromHibernationIfNeeded];
        if (binding.tab.pendingRestorableLoad) {
            [binding.tab loadPendingRestorableURLIfNeeded];
        }
        WKWebView *wv = binding.tab.webView ?: [binding.tab ensureWebView];
        if (!wv) {
            finish(NO, @"webView unavailable");
            return;
        }
        [strongBoot waitUntilDocumentHostReadyOnWebView:wv
                                                    tab:binding.tab
                                             providerId:providerId
                                                timeout:MIN(t, 45.0)
                                             completion:^(BOOL ok, NSString *liveHost, NSString *liveAbs, NSString *failDetail) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) {
                finish(NO, failDetail.length ? failDetail : @"绑定标签页面尚未加载");
                return;
            }
            binding.pageURL = liveAbs;
            binding.tabTitle = binding.tab.title;
            (void)liveHost;
            NSTimeInterval remain = MAX(5.0, t - 5.0);
            [strongSelf ensureReadyAndProbeUntilReadyOnWebView:wv
                                                    providerId:providerId
                                                       timeout:remain
                                                    completion:^(NSDictionary *probe, NSString *errorDetail, NSString *errorType) {
                (void)probe;
                (void)errorType;
                if (errorDetail.length) {
                    finish(NO, errorDetail);
                    return;
                }
                finish(YES, nil);
            }];
        }];
    });
}

/// Agent 模式：解析网页 JSON；失败则自动 1 次 repair；再失败 502。
- (void)finishAgentCompletionWithText:(NSString *)text
                                model:(NSString *)model
                              request:(NSDictionary *)json
                               stream:(BOOL)stream
                            startedAt:(NSTimeInterval)t0
                       repairAttempted:(BOOL)repairAttempted
                              respond:(AIBridgeHTTPRespondBlock)respond {
    AIBridgeToolSimResult *parsed = [AIBridgeToolSimulator parseWebpageText:text forRequest:json];
    if (!parsed.parseError.length) {
        NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
        NSString *detail = (parsed.kind == AIBridgeToolSimKindToolCalls)
            ? [NSString stringWithFormat:@"tools tool_calls:%lu", (unsigned long)parsed.toolCalls.count]
            : @"tools message";
        [self appendLogModel:model status:200 duration:dt detail:detail];
        [self notify];
        if (parsed.kind == AIBridgeToolSimKindToolCalls) {
            if (stream) {
                [self respondFakeSSEToolCalls:respond
                                        model:model
                                    toolCalls:parsed.toolCalls
                                      created:(NSInteger)t0];
            } else {
                [self respondToolCallsCompletion:respond
                                           model:model
                                       toolCalls:parsed.toolCalls
                                         created:(NSInteger)t0];
            }
        } else {
            NSString *content = parsed.content ?: @"";
            if (stream) {
                [self respondFakeSSE:respond model:model text:content created:(NSInteger)t0];
            } else {
                [self respondCompletion:respond model:model text:content created:(NSInteger)t0];
            }
        }
        return;
    }

    if (!repairAttempted) {
        NSString *repairPrompt = [AIBridgeToolSimulator buildRepairPromptFromRequest:json
                                                                        previousText:text ?: @""];
        __weak typeof(self) weakSelf = self;
        [[AIBridgeJobQueue sharedQueue] enqueueModel:model
                                              prompt:repairPrompt
                                         attachments:nil
                                           timeoutMs:90000
                                          completion:^(NSDictionary *result, NSInteger httpStatus, NSString *errorMessage) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (httpStatus != 200) {
                NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
                NSString *msg = [NSString stringWithFormat:@"tool_parse_error: %@; repair failed: %@",
                                 parsed.parseError ?: @"", errorMessage ?: @"failed"];
                [strongSelf appendLogModel:model status:httpStatus duration:dt detail:msg];
                [strongSelf notify];
                [strongSelf respondJSON:respond status:502 object:@{
                    @"error": @{
                        @"message": msg,
                        @"type": @"tool_parse_error"
                    }
                }];
                return;
            }
            NSString *retryText = result[@"text"] ?: @"";
            [strongSelf finishAgentCompletionWithText:retryText
                                                model:model
                                              request:json
                                               stream:stream
                                            startedAt:t0
                                       repairAttempted:YES
                                              respond:respond];
        }];
        return;
    }

    NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
    NSString *msg = [NSString stringWithFormat:@"tool_parse_error: %@", parsed.parseError ?: @"invalid agent JSON"];
    [self appendLogModel:model status:502 duration:dt detail:msg];
    [self notify];
    [self respondJSON:respond status:502 object:@{
        @"error": @{
            @"message": msg,
            @"type": @"tool_parse_error"
        }
    }];
}

- (void)forwardUpstream:(NSData *)body
                baseURL:(NSString *)baseURL
                 apiKey:(NSString *)apiKey
                  model:(NSString *)model
                 stream:(BOOL)stream
                respond:(AIBridgeHTTPRespondBlock)respond {
    NSTimeInterval t0 = [NSDate date].timeIntervalSince1970;
    __weak typeof(self) weakSelf = self;
    // 上游若请求 stream，直接透传响应；非 stream 原样返回。
    // 若客户端要 stream 但上游返回非 SSE，仍原样透传（不二次假流式），避免双重包装。
    (void)stream;
    [[AIBridgeUpstreamClient sharedClient] forwardChatCompletionsBody:body
                                                              baseURL:baseURL
                                                               apiKey:apiKey
                                                           completion:^(NSInteger httpStatus, NSData *respBody, NSString *contentType, NSString *errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
        [strongSelf appendLogModel:model status:httpStatus duration:dt detail:errorMessage];
        [strongSelf notify];
        if (errorMessage.length && (!respBody || respBody.length == 0)) {
            [strongSelf respondJSON:respond status:httpStatus > 0 ? httpStatus : 502
                             object:@{@"error": @{@"message": errorMessage, @"type": @"upstream_error"}}];
            return;
        }
        NSString *ct = contentType.length ? contentType : @"application/json; charset=utf-8";
        respond(httpStatus, ct, respBody ?: [NSData data]);
    }];
}

- (nullable BrowserWindowController *)firstBrowserWindowController {
    BrowserWindowController *keyWC = nil;
    BrowserWindowController *anyWC = nil;
    for (NSWindow *w in NSApp.windows) {
        id wc = w.windowController;
        if (![wc isKindOfClass:[BrowserWindowController class]]) continue;
        if (!anyWC) anyWC = (BrowserWindowController *)wc;
        if (w.isKeyWindow || w.isMainWindow) {
            keyWC = (BrowserWindowController *)wc;
            break;
        }
    }
    return keyWC ?: anyWC;
}

/// 调试/自动化：绑定已有 DeepSeek 标签（或打开首页），便于 curl 复现发送链路。
- (void)handleBindProvider:(NSData *)body respond:(AIBridgeHTTPRespondBlock)respond {
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
    NSDictionary *json = [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    NSString *providerId = [json[@"provider"] isKindOfClass:[NSString class]] ? json[@"provider"] : @"deepseek";
    if (providerId.length == 0) providerId = @"deepseek";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        BrowserWindowController *wc = [strongSelf firstBrowserWindowController];
        if (!wc) {
            [strongSelf respondJSON:respond status:503 object:@{
                @"ok": @NO,
                @"error": @{@"message": @"no browser window"}
            }];
            return;
        }
        id<AIBridgeSidebarControllerDelegate> del = (id<AIBridgeSidebarControllerDelegate>)wc;
        if (![del respondsToSelector:@selector(aiBridgeSidebar:bindOrOpenProviderId:completion:)]) {
            [strongSelf respondJSON:respond status:503 object:@{
                @"ok": @NO,
                @"error": @{@"message": @"window cannot bind"}
            }];
            return;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [del aiBridgeSidebar:(AIBridgeSidebarController *)nil
       bindOrOpenProviderId:providerId
                 completion:^(BOOL ok, NSString *detail) {
#pragma clang diagnostic pop
            AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForProviderId:providerId];
            if (!ok || !b) {
                [strongSelf respondJSON:respond status:503 object:@{
                    @"ok": @NO,
                    @"error": @{@"message": detail ?: @"bind failed"}
                }];
                return;
            }
            [strongSelf respondJSON:respond status:200 object:@{
                @"ok": @YES,
                @"model": b.modelId ?: @"",
                @"binding_id": b.bindingId ?: @"",
                @"provider": b.providerId ?: @"",
                @"url": b.pageURL ?: @"",
                @"detail": detail ?: @""
            }];
        }];
    });
}

- (void)handleInspect:(NSData *)body respond:(AIBridgeHTTPRespondBlock)respond {
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
    NSDictionary *json = [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    NSString *model = [json[@"model"] isKindOfClass:[NSString class]] ? json[@"model"] : @"bridge__kimi";
    AIBridgeBinding *binding = [AIBridgeRegistry.sharedRegistry bindingForModelId:model];
    if (!binding) {
        // try provider id
        NSString *pid = [model hasPrefix:@"bridge__"] ? [model substringFromIndex:8] : model;
        binding = [AIBridgeRegistry.sharedRegistry bindingForProviderId:pid];
    }
    if (!binding || !binding.tab) {
        [self respondJSON:respond status:404 object:@{@"error": @{@"message": @"model not bound", @"type": @"invalid_request"}}];
        return;
    }
    [binding.tab wakeFromHibernationIfNeeded];
    WKWebView *wv = binding.tab.webView ?: [binding.tab ensureWebView];
    if (!wv) {
        [self respondJSON:respond status:503 object:@{@"error": @{@"message": @"webView unavailable"}}];
        return;
    }
    NSString *what = [json[@"what"] isKindOfClass:[NSString class]] ? json[@"what"] : @"";
    if ([what isEqualToString:@"composer"] || [what isEqualToString:@"probe"]) {
        // 诊断：先 ensureReady 再 dump / probe，便于定位输入框选择器失效。
        NSString *providerId = binding.providerId ?: @"deepseek";
        [[AIBridgeDOMProvider sharedProvider] ensureReadyOnWebView:wv providerId:providerId completion:^(NSError *readyErr) {
            if (readyErr) {
                [self respondJSON:respond status:503 object:@{
                    @"ok": @NO,
                    @"error": readyErr.localizedDescription ?: @"ensureReady failed"
                }];
                return;
            }
            if ([what isEqualToString:@"probe"]) {
                [[AIBridgeDOMProvider sharedProvider] probeOnWebView:wv completion:^(NSDictionary *probe, NSError *probeErr) {
                    [self respondJSON:respond status:200 object:@{
                        @"ok": @YES,
                        @"probe": probe ?: @{},
                        @"probeError": probeErr.localizedDescription ?: [NSNull null]
                    }];
                }];
                return;
            }
            NSString *dumpJS =
                @"(function(){"
                 "  function info(el){"
                 "    if(!el) return null;"
                 "    var r=el.getBoundingClientRect();"
                 "    return {"
                 "      tag: el.tagName,"
                 "      type: el.type||null,"
                 "      role: el.getAttribute && el.getAttribute('role'),"
                 "      contentEditable: el.isContentEditable||el.getAttribute('contenteditable'),"
                 "      class: String(el.className||'').slice(0,120),"
                 "      id: el.id||null,"
                 "      placeholder: el.getAttribute && el.getAttribute('placeholder'),"
                 "      aria: el.getAttribute && el.getAttribute('aria-label'),"
                 "      w: Math.round(r.width), h: Math.round(r.height),"
                 "      valueLen: (el.value!=null?String(el.value):String(el.innerText||'')).length"
                 "    };"
                 "  }"
                 "  var tas=[].slice.call(document.querySelectorAll('textarea')).map(info);"
                 "  var edits=[].slice.call(document.querySelectorAll('[contenteditable=\"true\"], [contenteditable=\"\"], div[role=\"textbox\"], [role=\"textbox\"]')).map(info);"
                 "  var inputs=[].slice.call(document.querySelectorAll('input:not([type=hidden]):not([type=file])')).slice(0,20).map(info);"
                 "  var composers=[].slice.call(document.querySelectorAll('.aaff8b8f, [class*=\"composer\"], [class*=\"Composer\"]')).slice(0,5).map(function(el){"
                 "    return {class:String(el.className||'').slice(0,120), html:String(el.innerHTML||'').slice(0,500)};"
                 "  });"
                 "  var bridge = window.__MeoAIBridge ? window.__MeoAIBridge.probe() : {ok:false,detail:'no api'};"
                 "  return JSON.stringify({ok:true,href:location.href||'',ready:document.readyState,tas:tas,edits:edits,inputs:inputs,composers:composers,probe:bridge});"
                 "})()";
            [wv evaluateJavaScript:dumpJS completionHandler:^(id result, NSError *error) {
                if (error) {
                    [self respondJSON:respond status:503 object:@{@"ok": @NO, @"error": error.localizedDescription ?: @"dump failed"}];
                    return;
                }
                NSDictionary *dict = nil;
                if ([result isKindOfClass:[NSString class]]) {
                    NSData *data = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
                    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                    if ([obj isKindOfClass:[NSDictionary class]]) dict = obj;
                } else if ([result isKindOfClass:[NSDictionary class]]) {
                    dict = result;
                }
                [self respondJSON:respond status:200 object:dict ?: @{@"ok": @NO, @"raw": result ?: [NSNull null]}];
            }];
        }];
        return;
    }
    [[AIBridgeDOMProvider sharedProvider] inspectAssistantDOMOnWebView:wv completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            [self respondJSON:respond status:503 object:@{@"ok": @NO, @"error": error.localizedDescription ?: @"inspect failed"}];
            return;
        }
        [self respondJSON:respond status:200 object:result ?: @{@"ok": @NO}];
    }];
}

- (void)handleNewChat:(NSData *)body respond:(AIBridgeHTTPRespondBlock)respond {
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
    NSDictionary *json = [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    NSString *model = [json[@"model"] isKindOfClass:[NSString class]] ? json[@"model"] : @"";
    NSString *providerId = nil;
    if ([model hasPrefix:@"bridge__"]) {
        providerId = [model substringFromIndex:@"bridge__".length];
    } else if ([json[@"provider"] isKindOfClass:[NSString class]]) {
        providerId = json[@"provider"];
    }
    if (providerId.length == 0) {
        [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"model or provider required", @"type": @"invalid_request"}}];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self newChatForProviderId:providerId completion:^(BOOL ok, NSString *detail) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (ok) {
            [strongSelf respondJSON:respond status:200 object:@{@"ok": @YES}];
        } else {
            [strongSelf respondJSON:respond status:503 object:@{@"ok": @NO, @"error": @{@"message": detail ?: @"failed"}}];
        }
    }];
}

- (void)respondCompletion:(AIBridgeHTTPRespondBlock)respond
                    model:(NSString *)model
                     text:(NSString *)text
                  created:(NSInteger)created {
    NSString *idStr = [NSString stringWithFormat:@"chatcmpl-meo-%@", NSUUID.UUID.UUIDString];
    NSDictionary *payload = @{
        @"id": idStr,
        @"object": @"chat.completion",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[
            @{
                @"index": @0,
                @"message": @{@"role": @"assistant", @"content": text ?: @""},
                @"finish_reason": @"stop"
            }
        ],
        @"usage": @{
            @"prompt_tokens": @0,
            @"completion_tokens": @0,
            @"total_tokens": @0
        }
    };
    [self respondJSON:respond status:200 object:payload];
}

- (void)respondToolCallsCompletion:(AIBridgeHTTPRespondBlock)respond
                             model:(NSString *)model
                         toolCalls:(NSArray<NSDictionary *> *)toolCalls
                           created:(NSInteger)created {
    NSString *idStr = [NSString stringWithFormat:@"chatcmpl-meo-%@", NSUUID.UUID.UUIDString];
    NSDictionary *payload = @{
        @"id": idStr,
        @"object": @"chat.completion",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[
            @{
                @"index": @0,
                @"message": @{
                    @"role": @"assistant",
                    @"content": [NSNull null],
                    @"tool_calls": toolCalls ?: @[]
                },
                @"finish_reason": @"tool_calls"
            }
        ],
        @"usage": @{
            @"prompt_tokens": @0,
            @"completion_tokens": @0,
            @"total_tokens": @0
        }
    };
    [self respondJSON:respond status:200 object:payload];
}

/// 假流式 tool_calls：先 role，再按 index 推 delta.tool_calls，最后 finish_reason=tool_calls。
- (void)respondFakeSSEToolCalls:(AIBridgeHTTPRespondBlock)respond
                          model:(NSString *)model
                      toolCalls:(NSArray<NSDictionary *> *)toolCalls
                        created:(NSInteger)created {
    NSString *idStr = [NSString stringWithFormat:@"chatcmpl-meo-%@", NSUUID.UUID.UUIDString];
    NSMutableString *sse = [NSMutableString string];

    void (^emit)(NSDictionary *) = ^(NSDictionary *obj) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
        NSString *line = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
        [sse appendFormat:@"data: %@\n\n", line];
    };

    emit(@{
        @"id": idStr,
        @"object": @"chat.completion.chunk",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[ @{
            @"index": @0,
            @"delta": @{@"role": @"assistant", @"content": [NSNull null]},
            @"finish_reason": [NSNull null]
        }]
    });

    NSArray *calls = toolCalls ?: @[];
    for (NSUInteger i = 0; i < calls.count; i++) {
        NSDictionary *tc = calls[i];
        NSDictionary *fn = [tc[@"function"] isKindOfClass:[NSDictionary class]] ? tc[@"function"] : @{};
        NSString *name = [fn[@"name"] isKindOfClass:[NSString class]] ? fn[@"name"] : @"";
        NSString *args = [fn[@"arguments"] isKindOfClass:[NSString class]] ? fn[@"arguments"] : @"{}";
        NSString *callId = [tc[@"id"] isKindOfClass:[NSString class]] ? tc[@"id"] : [NSString stringWithFormat:@"call_%lu", (unsigned long)i];

        // name chunk
        emit(@{
            @"id": idStr,
            @"object": @"chat.completion.chunk",
            @"created": @(created),
            @"model": model ?: @"",
            @"choices": @[ @{
                @"index": @0,
                @"delta": @{
                    @"tool_calls": @[ @{
                        @"index": @(i),
                        @"id": callId,
                        @"type": @"function",
                        @"function": @{@"name": name, @"arguments": @""}
                    }]
                },
                @"finish_reason": [NSNull null]
            }]
        });

        // arguments in pieces
        NSUInteger chunkSize = 48;
        for (NSUInteger off = 0; off < args.length; off += chunkSize) {
            NSUInteger len = MIN(chunkSize, args.length - off);
            NSString *piece = [args substringWithRange:NSMakeRange(off, len)];
            emit(@{
                @"id": idStr,
                @"object": @"chat.completion.chunk",
                @"created": @(created),
                @"model": model ?: @"",
                @"choices": @[ @{
                    @"index": @0,
                    @"delta": @{
                        @"tool_calls": @[ @{
                            @"index": @(i),
                            @"function": @{@"arguments": piece}
                        }]
                    },
                    @"finish_reason": [NSNull null]
                }]
            });
        }
    }

    emit(@{
        @"id": idStr,
        @"object": @"chat.completion.chunk",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[ @{
            @"index": @0,
            @"delta": @{},
            @"finish_reason": @"tool_calls"
        }]
    });
    [sse appendString:@"data: [DONE]\n\n"];

    NSData *body = [sse dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    respond(200, @"text/event-stream; charset=utf-8", body);
}

/// 整段生成后切成 SSE delta（假流式）。
- (void)respondFakeSSE:(AIBridgeHTTPRespondBlock)respond
                 model:(NSString *)model
                  text:(NSString *)text
               created:(NSInteger)created {
    NSString *idStr = [NSString stringWithFormat:@"chatcmpl-meo-%@", NSUUID.UUID.UUIDString];
    NSMutableString *sse = [NSMutableString string];
    NSString *full = text ?: @"";

    NSDictionary *first = @{
        @"id": idStr,
        @"object": @"chat.completion.chunk",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[ @{
            @"index": @0,
            @"delta": @{@"role": @"assistant", @"content": @""},
            @"finish_reason": [NSNull null]
        }]
    };
    NSData *firstData = [NSJSONSerialization dataWithJSONObject:first options:0 error:nil];
    [sse appendFormat:@"data: %@\n\n", [[NSString alloc] initWithData:firstData encoding:NSUTF8StringEncoding]];

    NSUInteger chunkSize = 24;
    for (NSUInteger i = 0; i < full.length; i += chunkSize) {
        NSUInteger len = MIN(chunkSize, full.length - i);
        NSString *piece = [full substringWithRange:NSMakeRange(i, len)];
        NSDictionary *mid = @{
            @"id": idStr,
            @"object": @"chat.completion.chunk",
            @"created": @(created),
            @"model": model ?: @"",
            @"choices": @[ @{
                @"index": @0,
                @"delta": @{@"content": piece},
                @"finish_reason": [NSNull null]
            }]
        };
        NSData *d = [NSJSONSerialization dataWithJSONObject:mid options:0 error:nil];
        [sse appendFormat:@"data: %@\n\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
    }

    NSDictionary *last = @{
        @"id": idStr,
        @"object": @"chat.completion.chunk",
        @"created": @(created),
        @"model": model ?: @"",
        @"choices": @[ @{
            @"index": @0,
            @"delta": @{},
            @"finish_reason": @"stop"
        }]
    };
    NSData *lastData = [NSJSONSerialization dataWithJSONObject:last options:0 error:nil];
    [sse appendFormat:@"data: %@\n\n", [[NSString alloc] initWithData:lastData encoding:NSUTF8StringEncoding]];
    [sse appendString:@"data: [DONE]\n\n"];

    NSData *body = [sse dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    respond(200, @"text/event-stream; charset=utf-8", body);
}

- (void)appendLogModel:(NSString *)model status:(NSInteger)status duration:(NSTimeInterval)duration detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        AIBridgeRequestLogEntry *e = [[AIBridgeRequestLogEntry alloc] init];
        e.timestamp = [NSDate date].timeIntervalSince1970;
        e.modelId = model ?: @"";
        e.status = status;
        e.durationSec = duration;
        e.detail = detail;
        [self.logs insertObject:e atIndex:0];
        while (self.logs.count > 30) {
            [self.logs removeLastObject];
        }
    });
}

- (void)respondJSON:(AIBridgeHTTPRespondBlock)respond status:(NSInteger)status object:(id)object {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil] ?: [NSData data];
    respond(status, @"application/json; charset=utf-8", data);
}

@end
