#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserAIAssistantClientCompletion)(NSInteger httpStatus,
                                                   NSString *_Nullable assistantText,
                                                   NSString *_Nullable errorMessage);

@interface BrowserAIAssistantClient : NSObject

@property (class, readonly, strong) BrowserAIAssistantClient *sharedClient;

/// POST /v1/chat/completions（非流式）。若 Bridge 未听口会尝试 startServer。
- (void)chatWithModel:(NSString *)modelId
              prompt:(NSString *)prompt
          completion:(BrowserAIAssistantClientCompletion)completion;

- (void)cancelInFlight;

@end

NS_ASSUME_NONNULL_END
