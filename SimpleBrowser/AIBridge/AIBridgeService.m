#import "AIBridgeService.h"
#import "AIBridgePreferences.h"
#import "AIBridgeHTTPServer.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeJobQueue.h"
#import "BrowserTab.h"

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
    // Port may arrive asynchronously when listener ready — poll briefly
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
    NSString *name = [pid isEqualToString:@"mock"] ? @"Mock 对话页" : @"DeepSeek 网页";
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
        NSMutableArray *bindings = [NSMutableArray array];
        for (AIBridgeBinding *b in AIBridgeRegistry.sharedRegistry.allBindings) {
            [bindings addObject:@{
                @"model": b.modelId ?: @"",
                @"provider": b.providerId ?: @"",
                @"url": b.pageURL ?: @"",
                @"hasTab": @(b.tab != nil)
            }];
        }
        [self respondJSON:respond status:200 object:@{
            @"ok": @YES,
            @"listening": @(self.listening),
            @"bindings": bindings,
            @"status": self.statusText ?: @""
        }];
        return;
    }

    if (![self authorize:headers]) {
        [self respondJSON:respond status:401 object:@{@"error": @{@"message": @"unauthorized", @"type": @"auth"}}];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/models"] && [method isEqualToString:@"GET"]) {
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
        [self respondJSON:respond status:200 object:@{@"object": @"list", @"data": data}];
        return;
    }

    if ([pathOnly isEqualToString:@"/v1/chat/completions"] && [method isEqualToString:@"POST"]) {
        [self handleChatCompletions:body respond:respond];
        return;
    }

    [self respondJSON:respond status:404 object:@{@"error": @{@"message": @"not found", @"type": @"invalid_request"}}];
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
            // multimodal: concatenate text parts
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

    NSTimeInterval t0 = [NSDate date].timeIntervalSince1970;
    __weak typeof(self) weakSelf = self;
    [[AIBridgeJobQueue sharedQueue] enqueueModel:model
                                          prompt:prompt
                                       timeoutMs:120000
                                      completion:^(NSDictionary *result, NSInteger httpStatus, NSString *errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
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
        NSString *idStr = [NSString stringWithFormat:@"chatcmpl-meo-%@", NSUUID.UUID.UUIDString];
        NSDictionary *payload = @{
            @"id": idStr,
            @"object": @"chat.completion",
            @"created": @((NSInteger)t0),
            @"model": model,
            @"choices": @[
                @{
                    @"index": @0,
                    @"message": @{@"role": @"assistant", @"content": text},
                    @"finish_reason": @"stop"
                }
            ],
            @"usage": @{
                @"prompt_tokens": @0,
                @"completion_tokens": @0,
                @"total_tokens": @0
            }
        };
        [strongSelf respondJSON:respond status:200 object:payload];
    }];
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
