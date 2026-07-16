#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class LoginCredentials;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginRunnerCompletion)(BOOL success, NSError * _Nullable error);

@interface LoginRunner : NSObject

/// 执行 recipe。若 requiresOTPWait，会在填完前置字段后阻塞至 OTPInbox。
+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
      credentials:(LoginCredentials *)credentials
         fillOnly:(BOOL)fillOnly
       completion:(LoginRunnerCompletion)completion;

+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
         username:(NSString *)username
         password:(NSString *)password
         fillOnly:(BOOL)fillOnly
       completion:(LoginRunnerCompletion)completion;

+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
         username:(NSString *)username
         password:(NSString *)password
       completion:(LoginRunnerCompletion)completion;

/// 按选择器直接填入（可选提交），用于系统密码回填。
+ (void)fillInWebView:(WKWebView *)webView
     usernameSelector:(NSString *)usernameSelector
     passwordSelector:(NSString *)passwordSelector
             username:(NSString *)username
             password:(NSString *)password
       submitSelector:(nullable NSString *)submitSelector
         shouldSubmit:(BOOL)shouldSubmit
           completion:(nullable LoginRunnerCompletion)completion;

/// 仅填入验证码栏（不重跑帐密/发码），用于 Companion 推码到达且页面已有 recipe。
+ (void)fillOTPCode:(NSString *)code
          intoRecipe:(LoginRecipe *)recipe
           inWebView:(WKWebView *)webView
        shouldSubmit:(BOOL)shouldSubmit
          completion:(nullable LoginRunnerCompletion)completion;

+ (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
