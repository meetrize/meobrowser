#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginRunnerCompletion)(BOOL success, NSError * _Nullable error);

@interface LoginRunner : NSObject

/// 在指定 WebView 上执行 recipe（需已加载页面）。fillOnly=YES 时只填帐密不提交。
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

+ (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
