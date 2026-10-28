#import "AIBridgeJobQueue.h"
#import "AIBridgeRegistry.h"
#import "AIBridgeDOMProvider.h"
#import "BrowserTab.h"
#import <WebKit/WebKit.h>

@interface AIBridgeJob : NSObject
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, assign) NSInteger timeoutMs;
@property (nonatomic, copy) AIBridgeJobCompletion completion;
@property (nonatomic, assign) BOOL finished;
@end

@implementation AIBridgeJob
@end

@interface AIBridgeJobQueue ()
@property (nonatomic, strong) NSMutableArray<AIBridgeJob *> *pending;
@property (nonatomic, assign, readwrite, getter=isBusy) BOOL busy;
@property (nonatomic, strong, nullable) AIBridgeJob *currentJob;
@property (nonatomic, weak, nullable) WKWebView *currentWebView;
@property (nonatomic, assign) NSUInteger cancelGeneration;
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
        _maxPending = 5;
    }
    return self;
}

- (NSUInteger)pendingCount {
    return self.pending.count;
}

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.pending.count >= self.maxPending) {
            if (completion) {
                completion(nil, 429, @"queue full");
            }
            return;
        }
        AIBridgeJob *job = [[AIBridgeJob alloc] init];
        job.modelId = modelId ?: @"";
        job.prompt = prompt ?: @"";
        job.timeoutMs = timeoutMs > 0 ? timeoutMs : 120000;
        job.completion = completion;
        [self.pending addObject:job];
        [self pump];
    });
}

- (void)completeJob:(AIBridgeJob *)job
             result:(NSDictionary *)result
             status:(NSInteger)status
              error:(NSString *)error {
    if (!job || job.finished) {
        return;
    }
    job.finished = YES;
    if (job.completion) {
        job.completion(result, status, error);
    }
}

- (void)cancelAll {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelGeneration += 1;
        NSArray<AIBridgeJob *> *queued = [self.pending copy];
        [self.pending removeAllObjects];
        for (AIBridgeJob *job in queued) {
            [self completeJob:job result:nil status:499 error:@"cancelled"];
        }
        WKWebView *wv = self.currentWebView;
        if (wv) {
            [[AIBridgeDOMProvider sharedProvider] abortOnWebView:wv];
        }
        AIBridgeJob *cur = self.currentJob;
        self.currentJob = nil;
        self.currentWebView = nil;
        self.busy = NO;
        if (cur) {
            [self completeJob:cur result:nil status:499 error:@"cancelled"];
        }
    });
}

- (void)pump {
    if (self.busy || self.pending.count == 0) {
        return;
    }
    AIBridgeJob *job = self.pending.firstObject;
    [self.pending removeObjectAtIndex:0];
    self.busy = YES;
    self.currentJob = job;
    NSUInteger gen = self.cancelGeneration;

    AIBridgeBinding *binding = [[AIBridgeRegistry sharedRegistry] bindingForModelId:job.modelId];
    if (!binding || !binding.tab) {
        [self finishJob:job result:nil status:404 error:@"model not bound" generation:gen];
        return;
    }

    BrowserTab *tab = binding.tab;
    [tab wakeFromHibernationIfNeeded];
    WKWebView *webView = tab.webView;
    if (!webView) {
        webView = [tab ensureWebView];
    }
    if (!webView) {
        [self finishJob:job result:nil status:503 error:@"webView unavailable" generation:gen];
        return;
    }
    self.currentWebView = webView;

    NSString *providerId = binding.providerId ?: @"deepseek";
    __weak typeof(self) weakSelf = self;
    [[AIBridgeDOMProvider sharedProvider] sendAndWaitPrompt:job.prompt
                                                  onWebView:webView
                                                 providerId:providerId
                                                  timeoutMs:job.timeoutMs
                                                 completion:^(NSDictionary *result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (gen != strongSelf.cancelGeneration || job.finished) {
            return;
        }
        if (error) {
            [strongSelf finishJob:job result:nil status:503 error:error.localizedDescription generation:gen];
            return;
        }
        BOOL ok = [result[@"ok"] boolValue];
        NSString *text = [result[@"text"] isKindOfClass:[NSString class]] ? result[@"text"] : @"";
        NSString *err = [result[@"error"] isKindOfClass:[NSString class]] ? result[@"error"] : nil;
        if ([err isEqualToString:@"aborted"] || [err isEqualToString:@"cancelled"]) {
            [strongSelf finishJob:job result:result status:499 error:@"cancelled" generation:gen];
            return;
        }
        if (!ok) {
            NSString *msg = err.length ? err : @"bridge failed";
            NSInteger status = [msg isEqualToString:@"timeout"] ? 504 : 503;
            [strongSelf finishJob:job result:result status:status error:msg generation:gen];
            return;
        }
        [strongSelf finishJob:job result:@{@"text": text ?: @"", @"model": job.modelId} status:200 error:nil generation:gen];
    }];
}

- (void)finishJob:(AIBridgeJob *)job
           result:(NSDictionary *)result
           status:(NSInteger)status
            error:(NSString *)error
       generation:(NSUInteger)generation {
    if (self.currentJob == job) {
        self.currentJob = nil;
        self.currentWebView = nil;
    }
    [self completeJob:job result:result status:status error:error];
    self.busy = NO;
    if (generation == self.cancelGeneration) {
        [self pump];
    }
}

@end
