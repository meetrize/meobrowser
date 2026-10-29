#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class AIPageContextBundle;
@class AIPageContextResource;

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIPageContextCaptureCompletion)(AIPageContextBundle *_Nullable bundle,
                                               NSString *_Nullable errorMessage);
typedef void (^AIPageContextResourceLoadCompletion)(BOOL ok,
                                                    NSString *_Nullable text,
                                                    NSString *_Nullable errorMessage);

@interface AIPageContextCapturer : NSObject

@property (class, readonly, strong) AIPageContextCapturer *sharedCapturer;

/// 采集各层 + 资源索引；成功后写入 Store（若提供 tabID）。
- (void)captureFromWebView:(WKWebView *)webView
                     tabID:(nullable NSUUID *)tabID
          maxArticleChars:(NSUInteger)maxArticleChars
                completion:(AIPageContextCaptureCompletion)completion;

/// L3：按需拉取同源资源正文，写回 resource.text。
- (void)loadTextForResource:(AIPageContextResource *)resource
                  inWebView:(WKWebView *)webView
                 maxChars:(NSUInteger)maxChars
                 completion:(AIPageContextResourceLoadCompletion)completion;

@end

NS_ASSUME_NONNULL_END
