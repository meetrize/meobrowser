#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class NSURLAuthenticationChallenge;

@interface BrowserHTTPAuthPromptResult : NSObject
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) BOOL rememberPassword;
@end

/// 系统级风格的 HTTP Basic / Digest 登录 sheet（对齐 Safari）。
@interface BrowserHTTPAuthPrompt : NSObject

+ (void)presentForChallenge:(NSURLAuthenticationChallenge *)challenge
                   inWindow:(NSWindow *)window
          completionHandler:(void (^)(BrowserHTTPAuthPromptResult * _Nullable result))completionHandler;

@end

NS_ASSUME_NONNULL_END
