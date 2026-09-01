#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginFieldSaveCompletion)(BOOL saved);

/// 页面内联「＋」单字段 / 「保存本表」写入 Recipe + Keychain。
@interface LoginFieldSaveCoordinator : NSObject

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)handleSaveFieldMessage:(NSDictionary *)body
                   fromWebView:(WKWebView *)webView
                    completion:(nullable LoginFieldSaveCompletion)completion;

- (void)handleSaveFormMessage:(NSDictionary *)body
                  fromWebView:(WKWebView *)webView
                   completion:(nullable LoginFieldSaveCompletion)completion;

/// 弹出确认：保存当前字段，并提供「保存本表已填项」。
- (void)confirmSaveFieldOrWholeFormFromBody:(NSDictionary *)body
                                fromWebView:(WKWebView *)webView
                                 completion:(nullable LoginFieldSaveCompletion)completion;

@end

NS_ASSUME_NONNULL_END
