#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIBridgeUpstreamCompletion)(NSInteger httpStatus,
                                           NSData *_Nullable body,
                                           NSString *_Nullable contentType,
                                           NSString *_Nullable errorMessage);

@interface AIBridgeUpstreamClient : NSObject

+ (instancetype)sharedClient;

/// 将 OpenAI 兼容 JSON body 转发到上游 `/v1/chat/completions`（或完整 URL）。
- (void)forwardChatCompletionsBody:(NSData *)body
                           baseURL:(NSString *)baseURL
                            apiKey:(nullable NSString *)apiKey
                        completion:(AIBridgeUpstreamCompletion)completion;

/// 探测上游是否可达（HEAD/GET models，短超时）。
- (void)pingBaseURL:(NSString *)baseURL
             apiKey:(nullable NSString *)apiKey
         completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;

@end

NS_ASSUME_NONNULL_END
