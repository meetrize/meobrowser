#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface SaveRecipePromptCoordinator : NSObject

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

/// 导航完成后若存在待保存草稿则询问。
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(nullable NSURL *)url;
- (void)noteFormSubmitted;
- (void)noteCredentialsDraftOnPage;

/// 主动从当前页草稿保存（不受「登录成功询问」关闭影响）。
- (void)promptSaveFromWebView:(WKWebView *)webView
               preferredHost:(nullable NSString *)host
            existingFormInfo:(nullable NSDictionary *)info;

@end

NS_ASSUME_NONNULL_END
