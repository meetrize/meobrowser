#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LoginFormInlineHandlerName;

@interface LoginFormDetector : NSObject

+ (NSString *)userScriptSource;
+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
               messageHandler:(id<WKScriptMessageHandler>)handler;

@end

NS_ASSUME_NONNULL_END
