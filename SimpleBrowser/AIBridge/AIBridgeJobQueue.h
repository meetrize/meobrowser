#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIBridgeJobCompletion)(NSDictionary *_Nullable result, NSInteger httpStatus, NSString *_Nullable errorMessage);

@interface AIBridgeJobQueue : NSObject

@property (class, readonly, strong) AIBridgeJobQueue *sharedQueue;

@property (nonatomic, assign, readonly) NSUInteger pendingCount;
@property (nonatomic, assign, readonly, getter=isBusy) BOOL busy;
@property (nonatomic, assign) NSUInteger maxPending; // default 5

- (void)enqueueModel:(NSString *)modelId
              prompt:(NSString *)prompt
           timeoutMs:(NSInteger)timeoutMs
          completion:(AIBridgeJobCompletion)completion;

/// 中止当前任务并拒绝排队中的任务（499）。
- (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
