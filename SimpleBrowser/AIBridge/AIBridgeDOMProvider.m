#import "AIBridgeDOMProvider.h"

@interface AIBridgeDOMProvider ()
@property (nonatomic, strong) NSMutableSet<NSString *> *readyKeys;
@end

@implementation AIBridgeDOMProvider

+ (AIBridgeDOMProvider *)sharedProvider {
    static AIBridgeDOMProvider *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [[AIBridgeDOMProvider alloc] init];
    });
    return p;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _readyKeys = [NSMutableSet set];
    }
    return self;
}

- (NSString *)keyForWebView:(WKWebView *)webView providerId:(NSString *)providerId {
    return [NSString stringWithFormat:@"%p|%@", webView, providerId ?: @""];
}

- (nullable NSString *)loadResourceNamed:(NSString *)name subdirectory:(nullable NSString *)sub {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *path = nil;
    if (sub.length) {
        path = [bundle pathForResource:name ofType:nil inDirectory:sub];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:nil];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:nil inDirectory:@"AIBridge"];
    }
    if (!path && sub.length) {
        path = [bundle pathForResource:name ofType:nil inDirectory:[@"AIBridge" stringByAppendingPathComponent:sub]];
    }
    if (!path) {
        return nil;
    }
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

- (void)evaluate:(NSString *)script
       onWebView:(WKWebView *)webView
      completion:(void (^)(id _Nullable result, NSError *_Nullable error))completion {
    if (!webView || script.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"AIBridgeDOMProvider" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"无 WebView 或空脚本"}]);
        }
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (completion) {
                completion(result, error);
            }
        }];
    });
}

- (NSDictionary *)coerceDictionary:(id)result {
    if ([result isKindOfClass:[NSDictionary class]]) {
        return result;
    }
    if ([result isKindOfClass:[NSString class]]) {
        NSData *data = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            return obj;
        }
    }
    return nil;
}

- (NSString *)jsonStringForPrompt:(NSString *)prompt {
    NSString *p = prompt ?: @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[ p ] options:0 error:nil];
    if (!data) {
        return @"\"\"";
    }
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayJSON.length >= 2 && [arrayJSON hasPrefix:@"["] && [arrayJSON hasSuffix:@"]"]) {
        return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
    }
    return @"\"\"";
}

- (void)ensureReadyOnWebView:(WKWebView *)webView
                  providerId:(NSString *)providerId
                  completion:(void (^)(NSError *_Nullable))completion {
    NSString *key = [self keyForWebView:webView providerId:providerId];
    NSString *runtime = [self loadResourceNamed:@"runtime.js" subdirectory:@"AIBridge"];
    if (!runtime) {
        runtime = [self loadResourceNamed:@"runtime.js" subdirectory:nil];
    }
    NSString *adapterName = @"deepseek.js";
    if ([providerId isEqualToString:@"mock"]) {
        adapterName = @"mock.js";
    } else if ([providerId isEqualToString:@"kimi"]) {
        adapterName = @"kimi.js";
    } else if ([providerId isEqualToString:@"deepseek"]) {
        adapterName = @"deepseek.js";
    }
    NSString *adapter = [self loadResourceNamed:adapterName subdirectory:@"AIBridge/Adapters"];
    if (!adapter) {
        adapter = [self loadResourceNamed:adapterName subdirectory:@"Adapters"];
    }
    if (!runtime.length || !adapter.length) {
        if (completion) {
            completion([NSError errorWithDomain:@"AIBridgeDOMProvider" code:2
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     @"缺少 AIBridge runtime/adapter 资源，请重新构建"}]);
        }
        return;
    }
    // 包一层并返回字符串，避免脚本末尾表达式类型无法桥接。
    NSString *combined = [NSString stringWithFormat:
                          @"(function(){\n%@\n%@\nreturn 'ready';\n})();", runtime, adapter];
    [self evaluate:combined onWebView:webView completion:^(id result, NSError *error) {
        BOOL ok = !error && [result isKindOfClass:[NSString class]] && [result isEqualToString:@"ready"];
        // 有些 WebKit 对返回值挑剔：只要无 error 且全局已装上，也算成功。
        if (!error) {
            [self.readyKeys addObject:key];
        }
        if (completion) {
            if (error && !ok) {
                completion(error);
            } else {
                completion(nil);
            }
        }
    }];
}

- (void)probeOnWebView:(WKWebView *)webView completion:(AIBridgeDOMCompletion)completion {
    NSString *js =
        @"(function(){ try {"
         "  var r = window.__MeoAIBridge ? window.__MeoAIBridge.probe() : {ok:false,detail:'no api'};"
         "  return JSON.stringify(r);"
         "} catch(e){ return JSON.stringify({ok:false,detail:String(e)}); } })()";
    [self evaluate:js onWebView:webView completion:^(id result, NSError *error) {
        NSDictionary *dict = [self coerceDictionary:result];
        if (completion) {
            completion(dict, dict ? nil : error);
        }
    }];
}

/// 同步启动任务 + 轮询结果，彻底避开 evaluateJavaScript 对 Promise 的桥接缺陷。
- (void)sendAndWaitPrompt:(NSString *)prompt
                onWebView:(WKWebView *)webView
               providerId:(NSString *)providerId
                timeoutMs:(NSInteger)timeoutMs
               completion:(AIBridgeDOMCompletion)completion {
    __weak typeof(self) weakSelf = self;
    [self ensureReadyOnWebView:webView providerId:providerId completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        NSInteger ms = timeoutMs > 0 ? timeoutMs : 120000;
        NSString *promptJSON = [strongSelf jsonStringForPrompt:prompt];
        NSString *startJS = [NSString stringWithFormat:
            @"(function(){"
             "  try {"
             "    if (!window.__MeoAIBridge || typeof window.__MeoAIBridge.sendAndWait !== 'function') {"
             "      window.__MeoAIBridgeJob = {status:'done', result:{ok:false, error:'sendAndWait missing'}};"
             "      return 'error';"
             "    }"
             "    window.__MeoAIBridgeJob = {status:'running', startedAt: Date.now()};"
             "    window.__MeoAIBridge.sendAndWait(%@, {timeoutMs:%ld, stableMs:1000}).then(function(r){"
             "      window.__MeoAIBridgeJob = {status:'done', result:{"
             "        ok: !!(r && r.ok),"
             "        text: (r && r.text != null) ? String(r.text) : '',"
             "        error: (r && r.error != null) ? String(r.error) : null,"
             "        sawBusy: !!(r && r.sawBusy),"
             "        count: (r && typeof r.count === 'number') ? r.count : 0"
             "      }};"
             "    }).catch(function(e){"
             "      window.__MeoAIBridgeJob = {status:'done', result:{ok:false, error:String(e)}};"
             "    });"
             "    return 'started';"
             "  } catch (e) {"
             "    window.__MeoAIBridgeJob = {status:'done', result:{ok:false, error:String(e)}};"
             "    return 'error';"
             "  }"
             "})()",
            promptJSON, (long)ms];

        [strongSelf evaluate:startJS onWebView:webView completion:^(id startResult, NSError *startError) {
            if (startError) {
                if (completion) {
                    completion(nil, startError);
                }
                return;
            }
            NSString *startStatus = [startResult isKindOfClass:[NSString class]] ? startResult : @"";
            if ([startStatus isEqualToString:@"error"]) {
                // 立即读一次结果
                [strongSelf pollJobOnWebView:webView
                                   deadline:[NSDate dateWithTimeIntervalSinceNow:1]
                                 completion:completion];
                return;
            }
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(ms / 1000.0) + 5.0];
            [strongSelf pollJobOnWebView:webView deadline:deadline completion:completion];
        }];
    }];
}

- (void)abortOnWebView:(WKWebView *)webView {
    NSString *js =
        @"(function(){"
         "  try {"
         "    if (window.__MeoAIBridge && typeof window.__MeoAIBridge.abort === 'function') {"
         "      window.__MeoAIBridge.abort();"
         "    }"
         "    if (window.__MeoAIBridgeJob && window.__MeoAIBridgeJob.status === 'running') {"
         "      window.__MeoAIBridgeJob = {status:'done', result:{ok:false, error:'aborted', text:''}};"
         "    }"
         "    return 'ok';"
         "  } catch(e) { return String(e); }"
         "})()";
    [self evaluate:js onWebView:webView completion:^(__unused id result, __unused NSError *error) {
    }];
}

- (void)newChatOnWebView:(WKWebView *)webView
              providerId:(NSString *)providerId
              completion:(AIBridgeDOMCompletion)completion {
    __weak typeof(self) weakSelf = self;
    [self ensureReadyOnWebView:webView providerId:providerId completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        NSString *js =
            @"(function(){ try {"
             "  var r = window.__MeoAIBridge ? window.__MeoAIBridge.newChat() : {ok:false,error:'no api'};"
             "  return JSON.stringify(r);"
             "} catch(e){ return JSON.stringify({ok:false,error:String(e)}); } })()";
        [strongSelf evaluate:js onWebView:webView completion:^(id result, NSError *evalErr) {
            NSDictionary *dict = [strongSelf coerceDictionary:result];
            if (completion) {
                completion(dict, dict ? nil : evalErr);
            }
        }];
    }];
}

- (void)pollJobOnWebView:(WKWebView *)webView
                deadline:(NSDate *)deadline
              completion:(AIBridgeDOMCompletion)completion {
    NSString *pollJS =
        @"(function(){"
         "  var j = window.__MeoAIBridgeJob;"
         "  if (!j) return JSON.stringify({status:'idle'});"
         "  if (j.status === 'running') return JSON.stringify({status:'running'});"
         "  return JSON.stringify({status:'done', result: j.result || {ok:false, error:'empty'}});"
         "})()";
    __weak typeof(self) weakSelf = self;
    [self evaluate:pollJS onWebView:webView completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        NSDictionary *payload = [strongSelf coerceDictionary:result];
        NSString *status = [payload[@"status"] isKindOfClass:[NSString class]] ? payload[@"status"] : @"";
        if ([status isEqualToString:@"done"]) {
            id res = payload[@"result"];
            NSDictionary *dict = [res isKindOfClass:[NSDictionary class]] ? res : nil;
            if (completion) {
                completion(dict ?: @{@"ok": @NO, @"error": @"bad result"}, nil);
            }
            return;
        }
        if ([[NSDate date] compare:deadline] == NSOrderedDescending) {
            if (completion) {
                completion(@{@"ok": @NO, @"error": @"timeout", @"text": @""}, nil);
            }
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [strongSelf pollJobOnWebView:webView deadline:deadline completion:completion];
        });
    }];
}

@end
