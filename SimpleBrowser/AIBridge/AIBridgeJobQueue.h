#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIBridgeJobCompletion)(NSDictionary *_Nullable result, NSInteger httpStatus, NSString *_Nullable errorMessage);

/// 真正占到 provider 槽位后、发网页任务前执行（勿在入队前探测，否则会堵死同页并发）。
typedef void (^AIBridgeJobPrepareCompletion)(BOOL ok, NSInteger httpStatus, NSString *_Nullable errorMessage, NSString *_Nullable errorType);
typedef void (^AIBridgeJobPrepareBlock)(WKWebView *webView,
                                        BrowserTab *tab,
                                        NSString *providerId,
                                        AIBridgeJobPrepareCompletion completion);

@interface AIBridgeJobQueue : NSObject

@property (class, readonly, strong) AIBridgeJobQueue *sharedQueue;

@property (nonatomic, assign, readonly) NSUInteger pendingCount;
@property (nonatomic, assign, readonly, getter=isBusy) BOOL busy;
@property (nonatomic, assign) NSUInteger maxPending; // default 5

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion;

/// `attachments`：@{ @"name", @"mime", @"base64" }；可空。
- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
         attachments:(nullable NSArray<NSDictionary *> *)attachments
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion;

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
         attachments:(nullable NSArray<NSDictionary *> *)attachments
           timeoutMs:(NSInteger)timeoutMs
             prepare:(nullable AIBridgeJobPrepareBlock)prepare
          completion:(AIBridgeJobCompletion)completion;

/// 中止当前任务并拒绝排队中的任务（499）。
- (void)cancelAll;

/// 强制清空队列与忙标志（卡死恢复 / 重启服务时调用）。主线程同步执行。
- (void)resetNow;

/// 当前排队数量（含正在执行的 0/1）
- (NSUInteger)activeJobCount;

@end

NS_ASSUME_NONNULL_END
