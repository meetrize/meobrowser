#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 在当前页面就地抽取/替换文本（WebKit TextManipulation），不改变页面 URL。
@interface BrowserInPageTranslator : NSObject

+ (instancetype)sharedTranslator;

/// 正在翻译的 WebView（用于避免重入）。
- (BOOL)isTranslatingWebView:(WKWebView *)webView;

/// 开始就地翻译。完成后在主线程回调；success=NO 时 errorMessage 可读。
- (void)translateWebView:(WKWebView *)webView
        targetLocaleIdentifier:(NSString *)localeID
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion;

@end

NS_ASSUME_NONNULL_END
