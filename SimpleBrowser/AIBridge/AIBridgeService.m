#import "AIBridgeService.h"
#import "AIBridgePreferences.h"
#import "AIBridgeHTTPServer.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeJobQueue.h"
#import "AIBridgeDOMProvider.h"
#import "AIBridgeUpstreamClient.h"
#import "BrowserTab.h"
#import <WebKit/WebKit.h>

NSNotificationName const AIBridgeServiceStateDidChangeNotification = @"AIBridgeServiceStateDidChangeNotification";

@implementation AIBridgeRequestLogEntry
@end

@interface AIBridgeService ()
@property (nonatomic, strong) AIBridgeHTTPServer *server;
@property (nonatomic, strong) NSMutableArray<AIBridgeRequestLogEntry *> *logs;
@property (nonatomic, assign, readwrite, getter=isListening) BOOL listening;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
@end

@implementation AIBridgeService

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
        return [NSString stringWithFormat:@"生成中… 排队 %lu", (unsigned long)q.pendingCount];
    }
    if (q.pendingCount > 0) {
        return [NSString stringWithFormat:@"排队 %lu", (unsigned long)q.pendingCount];
    }
    return @"空闲";
}

- (NSString *)baseURLString {
    NSInteger port = self.listeningPort > 0 ? self.listeningPort : AIBridgePreferences.sharedPreferences.port;
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

- (void)bindCurrentTab:(BrowserTab *)tab
               pageURL:(NSURL *)url
            providerId:(NSString *)providerId
                 error:(NSError **)error {
    if (!tab) {
        if (error) {
            *error = [NSError errorWithDomain:@"AIBridgeService" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"无当前标签"}];
        }
        return;
    }
    NSString *pid = providerId.length ? providerId : @"deepseek";
    NSString *modelId = [NSString stringWithFormat:@"bridge__%@", pid];
    NSString *name = pid;
    if ([pid isEqualToString:@"mock"]) {
        name = @"Mock 对话页";
    } else if ([pid isEqualToString:@"deepseek"]) {
        name = @"DeepSeek 网页";
    } else if ([pid isEqualToString:@"kimi"]) {
        name = @"Kimi 网页";
    } else if ([pid isEqualToString:@"iwencai"]) {
        name = @"问财 网页";
    } else if ([pid isEqualToString:@"doubao"]) {
        name = @"豆包 网页";
    } else if ([pid isEqualToString:@"gemini"]) {
        name = @"Gemini 网页";
    } else if ([pid isEqualToString:@"chatgpt"]) {
        name = @"ChatGPT 网页";
    }
    [[AIBridgeRegistry sharedRegistry] bindTab:tab
                                    providerId:pid
                                       modelId:modelId
                                   displayName:name
                                       pageURL:url.absoluteString];
    [self notify];
}

- (void)unbindProviderId:(NSString *)providerId {
    [[AIBridgeRegistry sharedRegistry] unbindProviderId:providerId];
    [self notify];
}

- (void)cancelAllJobs {
    [[AIBridgeJobQueue sharedQueue] cancelAll];
    [self notify];
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
    [b.tab wakeFromHibernationIfNeeded];
    WKWebView *wv = b.tab.webView ?: [b.tab ensureWebView];
    if (!wv) {
        if (completion) {
            completion(NO, @"无 WebView");
        }
        return;
    }
    [[AIBridgeDOMProvider sharedProvider] newChatOnWebView:wv
                                                providerId:b.providerId ?: providerId
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

    if ([pathOnly isEqualToString:@"/v1/bridge/inspect"] && ([method isEqualToString:@"GET"] || [method isEqualToString:@"POST"])) {
        [self handleInspect:body respond:respond];
        return;
    }

    [self respondJSON:respond status:404 object:@{@"error": @{@"message": @"not found", @"type": @"invalid_request"}}];
}

- (void)handleHealth:(AIBridgeHTTPRespondBlock)respond {
    NSMutableArray *bindings = [NSMutableArray array];
    for (AIBridgeBinding *b in AIBridgeRegistry.sharedRegistry.allBindings) {
        [bindings addObject:@{
            @"model": b.modelId ?: @"",
            @"provider": b.providerId ?: @"",
            @"url": b.pageURL ?: @"",
            @"hasTab": @(b.tab != nil)
        }];
    }
    AIBridgePreferences *prefs = AIBridgePreferences.sharedPreferences;
    AIBridgeJobQueue *q = AIBridgeJobQueue.sharedQueue;
    NSDictionary *payload = @{
        @"ok": @YES,
        @"listening": @(self.listening),
        @"port": @(self.listeningPort),
        @"bindings": bindings,
        @"queue": @{
            @"busy": @(q.isBusy),
            @"pending": @(q.pendingCount),
            @"maxPending": @(q.maxPending)
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
            @"provider": b.providerId ?: @""
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
            return acc.length ? acc : nil;
        }
    }
    return nil;
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

    AIBridgeBinding *binding = [AIBridgeRegistry.sharedRegistry bindingForModelId:model];
    if (!binding || !binding.tab) {
        [self respondJSON:respond status:404 object:@{@"error": @{@"message": @"model not bound", @"type": @"invalid_request"}}];
        return;
    }
    NSString *prompt = [self extractUserPrompt:json];
    if (prompt.length == 0) {
        [self respondJSON:respond status:400 object:@{@"error": @{@"message": @"messages must include user content", @"type": @"invalid_request"}}];
        return;
    }

    // 409：先 probe 登录/输入框
    [binding.tab wakeFromHibernationIfNeeded];
    WKWebView *wv = binding.tab.webView ?: [binding.tab ensureWebView];
    if (!wv) {
        [self respondJSON:respond status:503 object:@{@"error": @{@"message": @"webView unavailable", @"type": @"bridge_error"}}];
        return;
    }

    NSTimeInterval t0 = [NSDate date].timeIntervalSince1970;
    __weak typeof(self) weakSelf = self;
    NSString *providerId = binding.providerId ?: @"deepseek";
    [[AIBridgeDOMProvider sharedProvider] ensureReadyOnWebView:wv providerId:providerId completion:^(NSError *readyErr) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (readyErr) {
            [strongSelf appendLogModel:model status:503 duration:0 detail:readyErr.localizedDescription];
            [strongSelf respondJSON:respond status:503 object:@{@"error": @{@"message": readyErr.localizedDescription ?: @"inject failed", @"type": @"bridge_error"}}];
            return;
        }
        [[AIBridgeDOMProvider sharedProvider] probeOnWebView:wv completion:^(NSDictionary *probe, NSError *probeErr) {
            BOOL loggedIn = [probe[@"loggedIn"] boolValue] || [probe[@"hasInput"] boolValue] || [probe[@"ok"] boolValue];
            if (probeErr || !loggedIn) {
                NSString *detail = probe[@"detail"] ?: probeErr.localizedDescription ?: @"login required";
                [strongSelf appendLogModel:model status:409 duration:0 detail:detail];
                [strongSelf respondJSON:respond status:409 object:@{
                    @"error": @{
                        @"message": detail,
                        @"type": @"login_required",
                        @"probe": probe ?: @{}
                    }
                }];
                return;
            }
            [[AIBridgeJobQueue sharedQueue] enqueueModel:model
                                                  prompt:prompt
                                               timeoutMs:120000
                                              completion:^(NSDictionary *result, NSInteger httpStatus, NSString *errorMessage) {
                NSTimeInterval dt = [NSDate date].timeIntervalSince1970 - t0;
                [strongSelf appendLogModel:model status:httpStatus duration:dt detail:errorMessage];
                [strongSelf notify];
                if (httpStatus != 200) {
                    [strongSelf respondJSON:respond status:httpStatus object:@{
                        @"error": @{
                            @"message": errorMessage ?: @"failed",
                            @"type": @"bridge_error"
                        }
                    }];
                    return;
                }
                NSString *text = result[@"text"] ?: @"";
                if (stream) {
                    [strongSelf respondFakeSSE:respond model:model text:text created:(NSInteger)t0];
                } else {
                    [strongSelf respondCompletion:respond model:model text:text created:(NSInteger)t0];
                }
            }];
        }];
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
