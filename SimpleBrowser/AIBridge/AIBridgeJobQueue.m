#import "AIBridgeJobQueue.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeDOMProvider.h"
#import "BrowserTab.h"

@interface AIBridgeJob : NSObject
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *providerId;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *attachments;
@property (nonatomic, assign) NSInteger timeoutMs;
@property (nonatomic, copy, nullable) AIBridgeJobPrepareBlock prepare;
@property (nonatomic, copy) AIBridgeJobCompletion completion;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) NSTimeInterval startedAt;
@end

@implementation AIBridgeJob
@end

@interface AIBridgeJobQueue ()
@property (nonatomic, strong) NSMutableArray<AIBridgeJob *> *pending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIBridgeJob *> *runningByProvider;
@property (nonatomic, assign, readwrite, getter=isBusy) BOOL busy;
@property (nonatomic, strong, nullable) AIBridgeJob *currentJob;
@property (nonatomic, weak, nullable) WKWebView *currentWebView;
@property (nonatomic, assign) NSUInteger cancelGeneration;
@property (nonatomic, assign) NSUInteger jobWatchdogToken;
@end

@implementation AIBridgeJobQueue

+ (AIBridgeJobQueue *)sharedQueue {
    static AIBridgeJobQueue *q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = [[AIBridgeJobQueue alloc] init];
    });
    return q;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableArray array];
        _runningByProvider = [NSMutableDictionary dictionary];
        _maxPending = 8;
    }
    return self;
}

- (NSUInteger)pendingCount {
    return self.pending.count;
}

- (NSUInteger)activeJobCount {
    return self.pending.count + self.runningByProvider.count;
}

- (BOOL)isBusy {
    return self.runningByProvider.count > 0;
}

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion {
    [self enqueueModel:modelId prompt:prompt attachments:nil timeoutMs:timeoutMs completion:completion];
}

- (NSString *)providerIdFromModelId:(NSString *)modelId {
    NSString *pid = [AIBridgeRegistry providerIdFromModelId:modelId];
    if (pid.length) return pid;
    if ([modelId hasPrefix:@"bridge__"]) {
        return [modelId substringFromIndex:@"bridge__".length];
    }
    return modelId.length ? modelId : @"unknown";
}

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
         attachments:(NSArray<NSDictionary *> *)attachments
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion {
    [self enqueueModel:modelId
                prompt:prompt
           attachments:attachments
             timeoutMs:timeoutMs
               prepare:nil
            completion:completion];
}

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
         attachments:(NSArray<NSDictionary *> *)attachments
           timeoutMs:(NSInteger)timeoutMs
             prepare:(AIBridgeJobPrepareBlock)prepare
          completion:(AIBridgeJobCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *pid = [self providerIdFromModelId:modelId];
        AIBridgeJob *running = self.runningByProvider[pid];
        if (running) {
            NSTimeInterval age = NSDate.date.timeIntervalSince1970 - running.startedAt;
            // 与任务自身 timeout 对齐；勿再卡 35s 上限（DeepSeek 慢答会被误杀成 504）
            NSTimeInterval limit = MAX(running.timeoutMs / 1000.0, 25.0) + 15.0;
            if (age > limit) {
                NSLog(@"[AIBridge] stale job on %@ (%.0fs > %.0fs)", pid, age, limit);
                WKWebView *wv = [AIBridgeRegistry.sharedRegistry bindingForModelId:running.modelId].tab.webView;
                if (wv) [[AIBridgeDOMProvider sharedProvider] abortOnWebView:wv];
                [self finishJob:running result:nil status:504 error:@"stale_job_watchdog" generation:self.cancelGeneration];
            }
        }
        if (self.pending.count >= self.maxPending) {
            if (completion) completion(nil, 429, @"queue full");
            return;
        }
        // 同一 provider（同一 DeepSeek 页）严格单飞：忙就立刻 429，局域网/助手互不拖死
        NSUInteger pendingSame = 0;
        for (AIBridgeJob *p in self.pending) {
            if ([p.providerId isEqualToString:pid]) pendingSame += 1;
        }
        BOOL runningSame = (self.runningByProvider[pid] != nil);
        if (runningSame || pendingSame > 0) {
            if (completion) {
                completion(nil, 429, @"provider busy (same tab serial); retry after current job finishes");
            }
            return;
        }
        AIBridgeJob *job = [[AIBridgeJob alloc] init];
        job.modelId = modelId ?: @"";
        job.providerId = pid;
        job.prompt = prompt ?: @"";
        job.attachments = attachments.count ? [attachments copy] : nil;
        job.timeoutMs = timeoutMs > 0 ? timeoutMs : 60000;
        job.prepare = prepare;
        job.completion = completion;
        [self.pending addObject:job];
        NSLog(@"[AIBridge] enqueue model=%@ pending=%lu running=%@",
              job.modelId, (unsigned long)self.pending.count, runningSame ? @"yes" : @"no");
        [self pump];
    });
}

- (void)completeJob:(AIBridgeJob *)job
             result:(NSDictionary *)result
             status:(NSInteger)status
              error:(NSString *)error {
    if (!job || job.finished) return;
    job.finished = YES;
    if (job.completion) job.completion(result, status, error);
}

- (void)forceResetLockedReason:(NSString *)reason {
    self.cancelGeneration += 1;
    self.jobWatchdogToken += 1;
    NSArray<AIBridgeJob *> *queued = [self.pending copy];
    [self.pending removeAllObjects];
    for (AIBridgeJob *job in queued) {
        [self completeJob:job result:nil status:499 error:reason ?: @"cancelled"];
    }
    [[AIBridgeDOMProvider sharedProvider] invalidateInjections];
    NSMutableSet *aborted = [NSMutableSet set];
    NSArray<AIBridgeJob *> *running = [self.runningByProvider.allValues copy];
    [self.runningByProvider removeAllObjects];
    for (AIBridgeJob *cur in running) {
        [self completeJob:cur result:nil status:499 error:reason ?: @"cancelled"];
    }
    for (AIBridgeBinding *b in AIBridgeRegistry.sharedRegistry.allBindings) {
        WKWebView *bound = b.tab.webView;
        if (bound && ![aborted containsObject:bound]) {
            [[AIBridgeDOMProvider sharedProvider] resetBridgeOnWebView:bound];
            [aborted addObject:bound];
        }
    }
    self.currentJob = nil;
    self.currentWebView = nil;
    self.busy = NO;
    NSLog(@"[AIBridge] queue force reset (%@), aborted %lu webviews\n%@",
          reason ?: @"?", (unsigned long)aborted.count, [NSThread callStackSymbols]);
}

- (void)cancelAll {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self forceResetLockedReason:@"cancelled"];
    });
}

- (void)resetNow {
    void (^work)(void) = ^{
        [self forceResetLockedReason:@"cancelled"];
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
}

- (void)armWatchdogForJob:(AIBridgeJob *)job generation:(NSUInteger)gen {
    self.jobWatchdogToken += 1;
    NSUInteger token = self.jobWatchdogToken;
    NSTimeInterval grace = (job.timeoutMs / 1000.0) + 10.0;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(grace * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (token != strongSelf.jobWatchdogToken) return;
        if (gen != strongSelf.cancelGeneration) return;
        if (job.finished) return;
        if (strongSelf.runningByProvider[job.providerId] != job) return;
        NSLog(@"[AIBridge] job watchdog fired after %.0fs model=%@", grace, job.modelId);
        AIBridgeBinding *b = [AIBridgeRegistry.sharedRegistry bindingForModelId:job.modelId];
        WKWebView *wv = b.tab.webView;
        if (wv) [[AIBridgeDOMProvider sharedProvider] abortOnWebView:wv];
        [strongSelf finishJob:job result:nil status:504 error:@"watchdog_timeout" generation:gen];
    });
}

- (void)pump {
    // 不同 provider 可并行；同一 provider（同一网页）串行
    NSMutableArray<AIBridgeJob *> *toStart = [NSMutableArray array];
    NSMutableSet<NSString *> *claimed = [NSMutableSet set];
    for (AIBridgeJob *job in self.pending) {
        NSString *pid = job.providerId ?: @"unknown";
        if (self.runningByProvider[pid]) continue;
        if ([claimed containsObject:pid]) continue;
        [claimed addObject:pid];
        [toStart addObject:job];
    }
    for (AIBridgeJob *job in toStart) {
        [self.pending removeObject:job];
        [self startJob:job];
    }
    self.busy = self.runningByProvider.count > 0;
    self.currentJob = self.runningByProvider.allValues.firstObject;
}

- (void)startJob:(AIBridgeJob *)job {
    NSUInteger gen = self.cancelGeneration;
    job.startedAt = NSDate.date.timeIntervalSince1970;
    self.runningByProvider[job.providerId ?: @"unknown"] = job;
    self.busy = YES;
    self.currentJob = job;

    AIBridgeBinding *binding = [[AIBridgeRegistry sharedRegistry] bindingForModelId:job.modelId];
    if (!binding || !binding.tab) {
        [self finishJob:job result:nil status:404 error:@"model not bound" generation:gen];
        return;
    }

    BrowserTab *tab = binding.tab;
    [tab wakeFromHibernationIfNeeded];
    if (tab.pendingRestorableLoad) {
        [tab loadPendingRestorableURLIfNeeded];
    }
    WKWebView *webView = tab.webView ?: [tab ensureWebView];
    if (!webView) {
        [self finishJob:job result:nil status:503 error:@"webView unavailable" generation:gen];
        return;
    }
    self.currentWebView = webView;
    [self armWatchdogForJob:job generation:gen];

    NSString *providerId = binding.providerId ?: job.providerId ?: @"deepseek";
    __weak typeof(self) weakSelf = self;
    void (^runSend)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (gen != strongSelf.cancelGeneration || job.finished) return;
        [[AIBridgeDOMProvider sharedProvider] sendAndWaitPrompt:job.prompt
                                                    attachments:job.attachments
                                                      onWebView:webView
                                                     providerId:providerId
                                                      timeoutMs:job.timeoutMs
                                                     completion:^(NSDictionary *result, NSError *error) {
            __strong typeof(weakSelf) inner = weakSelf;
            if (!inner) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != inner.cancelGeneration || job.finished) return;
                if (error) {
                    [inner finishJob:job result:nil status:503 error:error.localizedDescription generation:gen];
                    return;
                }
                BOOL ok = [result[@"ok"] boolValue];
                NSString *text = [result[@"text"] isKindOfClass:[NSString class]] ? result[@"text"] : @"";
                NSString *err = [result[@"error"] isKindOfClass:[NSString class]] ? result[@"error"] : nil;
                NSString *detail = [result[@"detail"] isKindOfClass:[NSString class]] ? result[@"detail"] : nil;
                if ([err isEqualToString:@"aborted"] || [err isEqualToString:@"cancelled"]) {
                    [inner finishJob:job result:result status:499 error:@"cancelled" generation:gen];
                    return;
                }
                if (!ok && text.length > 0 &&
                    ([err isEqualToString:@"timeout"] ||
                     [err isEqualToString:@"no_response"] ||
                     [err isEqualToString:@"watchdog_timeout"] ||
                     [result[@"recovered"] boolValue])) {
                    [inner finishJob:job
                                   result:@{@"text": text, @"model": job.modelId, @"recovered": @YES}
                                   status:200
                                    error:nil
                               generation:gen];
                    return;
                }
                if (!ok) {
                    NSString *msg = err.length ? err : @"bridge failed";
                    if (detail.length) msg = [NSString stringWithFormat:@"%@ — %@", msg, detail];
                    NSInteger status = 503;
                    if ([err isEqualToString:@"timeout"] ||
                        [err isEqualToString:@"attach_timeout"] ||
                        [err isEqualToString:@"watchdog_timeout"] ||
                        [err isEqualToString:@"no_response"]) {
                        status = 504;
                    } else if ([err isEqualToString:@"attachments_unsupported"]) {
                        status = 400;
                    }
                    [inner finishJob:job result:result status:status error:msg generation:gen];
                    return;
                }
                [inner finishJob:job result:@{@"text": text ?: @"", @"model": job.modelId} status:200 error:nil generation:gen];
            });
        }];
    };

    if (job.prepare) {
        job.prepare(webView, tab, providerId, ^(BOOL ok, NSInteger httpStatus, NSString *errorMessage, NSString *errorType) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != strongSelf.cancelGeneration || job.finished) return;
                if (!ok) {
                    NSString *msg = errorMessage.length ? errorMessage : (errorType ?: @"prepare_failed");
                    [strongSelf finishJob:job result:nil status:(httpStatus > 0 ? httpStatus : 503) error:msg generation:gen];
                    return;
                }
                runSend();
            });
        });
    } else {
        runSend();
    }
}

- (void)finishJob:(AIBridgeJob *)job
           result:(NSDictionary *)result
           status:(NSInteger)status
            error:(NSString *)error
       generation:(NSUInteger)generation {
    NSString *pid = job.providerId ?: @"unknown";
    if (self.runningByProvider[pid] == job) {
        [self.runningByProvider removeObjectForKey:pid];
    }
    if (self.currentJob == job) {
        self.currentJob = self.runningByProvider.allValues.firstObject;
        self.currentWebView = nil;
        self.jobWatchdogToken += 1;
    }
    self.busy = self.runningByProvider.count > 0;
    [self completeJob:job result:result status:status error:error];
    if (generation == self.cancelGeneration) {
        [self pump];
    }
}

@end
