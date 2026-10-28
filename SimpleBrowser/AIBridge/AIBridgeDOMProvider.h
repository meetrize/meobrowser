#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIBridgeDOMCompletion)(NSDictionary *_Nullable result, NSError *_Nullable error);

@interface AIBridgeDOMProvider : NSObject

+ (instancetype)sharedProvider;

/// 注入 runtime + 指定 adapter（mock / deepseek），幂等。
- (void)ensureReadyOnWebView:(WKWebView *)webView
                  providerId:(NSString *)providerId
                  completion:(void (^)(NSError *_Nullable error))completion;

- (void)probeOnWebView:(WKWebView *)webView
            completion:(AIBridgeDOMCompletion)completion;

/// 推荐入口：先 baseline 再 send（页内 sendAndWait）。
- (void)sendAndWaitPrompt:(NSString *)prompt
                onWebView:(WKWebView *)webView
               providerId:(NSString *)providerId
                timeoutMs:(NSInteger)timeoutMs
               completion:(AIBridgeDOMCompletion)completion;

- (void)abortOnWebView:(WKWebView *)webView;

- (void)newChatOnWebView:(WKWebView *)webView
              providerId:(NSString *)providerId
              completion:(AIBridgeDOMCompletion)completion;

/// 调试：转储最后一条助手消息的 DOM 结构（class / 文本预览）。
- (void)inspectAssistantDOMOnWebView:(WKWebView *)webView
                          completion:(AIBridgeDOMCompletion)completion;

@end

NS_ASSUME_NONNULL_END
