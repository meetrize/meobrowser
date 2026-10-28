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
@end

@implementation AIBridgeJob
@end

@interface AIBridgeJobQueue ()
@property (nonatomic, strong) NSMutableArray<AIBridgeJob *> *pending;
@property (nonatomic, assign, readwrite, getter=isBusy) BOOL busy;
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

- (void)pump {
    if (self.busy || self.pending.count == 0) {
        return;
    }
    AIBridgeJob *job = self.pending.firstObject;
    [self.pending removeObjectAtIndex:0];
    self.busy = YES;

    AIBridgeBinding *binding = [[AIBridgeRegistry sharedRegistry] bindingForModelId:job.modelId];
    if (!binding || !binding.tab) {
        [self finishJob:job result:nil status:404 error:@"model not bound"];
        return;
    }

    BrowserTab *tab = binding.tab;
    [tab wakeFromHibernationIfNeeded];
    WKWebView *webView = tab.webView;
    if (!webView) {
        webView = [tab ensureWebView];
    }
    if (!webView) {
        [self finishJob:job result:nil status:503 error:@"webView unavailable"];
        return;
    }

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
        if (error) {
            [strongSelf finishJob:job result:nil status:503 error:error.localizedDescription];
            return;
        }
        BOOL ok = [result[@"ok"] boolValue];
        NSString *text = [result[@"text"] isKindOfClass:[NSString class]] ? result[@"text"] : @"";
        if (!ok) {
            NSString *err = [result[@"error"] isKindOfClass:[NSString class]] ? result[@"error"] : @"bridge failed";
            NSInteger status = [err isEqualToString:@"timeout"] ? 504 : 503;
            [strongSelf finishJob:job result:result status:status error:err];
            return;
        }
        [strongSelf finishJob:job result:@{@"text": text ?: @"", @"model": job.modelId} status:200 error:nil];
    }];
}

- (void)finishJob:(AIBridgeJob *)job
           result:(NSDictionary *)result
           status:(NSInteger)status
            error:(NSString *)error {
    if (job.completion) {
        job.completion(result, status, error);
    }
    self.busy = NO;
    [self pump];
}

@end
