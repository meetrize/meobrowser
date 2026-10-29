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

/// `attachmentPaths`：本机绝对路径；会编码为 meo_attachments。可与空 prompt 同用（仅附件）。
- (void)chatWithModel:(NSString *)modelId
              prompt:(NSString *)prompt
     attachmentPaths:(nullable NSArray<NSString *> *)attachmentPaths
          completion:(BrowserAIAssistantClientCompletion)completion;

- (void)cancelInFlight;

@end

NS_ASSUME_NONNULL_END
