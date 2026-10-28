#import "BrowserAIAssistantClient.h"
#import "AIBridgeService.h"
#import "AIBridgePreferences.h"

@interface BrowserAIAssistantClient ()
@property (nonatomic, strong, nullable) NSURLSessionDataTask *inFlightTask;
@end

@implementation BrowserAIAssistantClient

+ (BrowserAIAssistantClient *)sharedClient {
    static BrowserAIAssistantClient *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[BrowserAIAssistantClient alloc] init];
    });
    return c;
}

- (void)cancelInFlight {
    [self.inFlightTask cancel];
    self.inFlightTask = nil;
    [[AIBridgeService sharedService] cancelAllJobs];
}

- (nullable NSString *)extractAssistantContentFromJSONData:(NSData *)data {
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *json = obj;
    NSArray *choices = json[@"choices"];
    if ([choices isKindOfClass:[NSArray class]] && choices.count > 0) {
        id choice = choices.firstObject;
        if ([choice isKindOfClass:[NSDictionary class]]) {
            id msg = choice[@"message"];
            if ([msg isKindOfClass:[NSDictionary class]]) {
                id content = msg[@"content"];
                if ([content isKindOfClass:[NSString class]]) {
                    return content;
                }
            }
            id text = choice[@"text"];
            if ([text isKindOfClass:[NSString class]]) {
                return text;
            }
        }
    }
    id err = json[@"error"];
    if ([err isKindOfClass:[NSDictionary class]]) {
        id message = err[@"message"];
        if ([message isKindOfClass:[NSString class]]) {
            return message;
        }
    }
    if ([json[@"message"] isKindOfClass:[NSString class]]) {
        return json[@"message"];
    }
    return nil;
}

- (void)chatWithModel:(NSString *)modelId
              prompt:(NSString *)prompt
          completion:(BrowserAIAssistantClientCompletion)completion {
    NSString *model = modelId.length ? modelId : @"bridge__deepseek";
    NSString *text = prompt ?: @"";
    if (text.length == 0) {
        if (completion) {
            completion(400, nil, @"请输入提示词");
        }
        return;
    }

    AIBridgeService *svc = AIBridgeService.sharedService;
    if (!svc.isListening) {
        NSError *err = nil;
        if (![svc startServer:&err]) {
            if (completion) {
                completion(503, nil, err.localizedDescription ?: @"无法启动 AI Bridge 服务");
            }
            return;
        }
    }

    [AIBridgePreferences.sharedPreferences ensureToken];
    NSString *token = AIBridgePreferences.sharedPreferences.bearerToken ?: @"";
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1/chat/completions", svc.baseURLString];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) {
            completion(500, nil, @"URL 无效");
        }
        return;
    }

    NSDictionary *body = @{
        @"model": model,
        @"stream": @NO,
        @"messages": @[ @{ @"role": @"user", @"content": text } ]
    };
    NSError *jsonErr = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (!payload) {
        if (completion) {
            completion(400, nil, jsonErr.localizedDescription ?: @"JSON 编码失败");
        }
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = payload;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    req.timeoutInterval = 200;

    [self.inFlightTask cancel];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf.inFlightTask == task) {
                strongSelf.inFlightTask = nil;
            }
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
                                          ? (NSHTTPURLResponse *)response : nil;
            if (error) {
                if (error.code == NSURLErrorCancelled) {
                    if (completion) {
                        completion(499, nil, @"已取消");
                    }
                    return;
                }
                if (completion) {
                    completion(http.statusCode > 0 ? http.statusCode : 502,
                               nil,
                               error.localizedDescription ?: @"网络错误");
                }
                return;
            }
            NSInteger code = http.statusCode;
            NSString *extracted = [strongSelf extractAssistantContentFromJSONData:data];
            NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (code >= 200 && code < 300) {
                if (completion) {
                    completion(code, extracted.length ? extracted : @"（空回复）", nil);
                }
            } else {
                if (completion) {
                    completion(code, nil, extracted.length ? extracted : (raw.length ? raw : @"请求失败"));
                }
            }
        });
    }];
    self.inFlightTask = task;
    [task resume];
}

@end
