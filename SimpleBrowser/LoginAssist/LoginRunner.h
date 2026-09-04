#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class LoginCredentials;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginRunnerCompletion)(BOOL success, NSError * _Nullable error);

@interface LoginRunner : NSObject

/// 执行密码登录 recipe。
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

/// 仅填入单个选择器对应字段（不提交）。
+ (void)fillSelector:(NSString *)selector
               value:(NSString *)value
           inWebView:(WKWebView *)webView
          completion:(nullable LoginRunnerCompletion)completion;

+ (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
