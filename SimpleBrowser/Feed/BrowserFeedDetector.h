#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserFeedAssistHandlerName;

@interface BrowserFeedDetector : NSObject

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
                messageHandler:(id<WKScriptMessageHandler>)handler;

@end

NS_ASSUME_NONNULL_END
