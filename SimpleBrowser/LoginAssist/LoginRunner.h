#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginRunnerCompletion)(BOOL success, NSError * _Nullable error);

@interface LoginRunner : NSObject

/// 在指定 WebView 上执行 recipe（需已加载页面）。
+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
         username:(NSString *)username
         password:(NSString *)password
       completion:(LoginRunnerCompletion)completion;

+ (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
