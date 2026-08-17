#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 在当前页面就地抽取/替换文本（WebKit TextManipulation），不改变页面 URL。
@interface BrowserInPageTranslator : NSObject

+ (instancetype)sharedTranslator;

/// 正在翻译的 WebView。
- (BOOL)isTranslatingWebView:(WKWebView *)webView;

/// 开始就地翻译。完成后在主线程回调；cancelled 时 success=NO 且 errorMessage=nil。
- (void)translateWebView:(WKWebView *)webView
        targetLocaleIdentifier:(NSString *)localeID
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion;

/// 取消指定 WebView 的进行中翻译。
- (void)cancelTranslationForWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
