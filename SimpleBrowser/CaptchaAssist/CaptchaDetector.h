#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CaptchaAssistHandlerName;

@interface CaptchaDetector : NSObject

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
               messageHandler:(id<WKScriptMessageHandler>)handler;

@end

NS_ASSUME_NONNULL_END
