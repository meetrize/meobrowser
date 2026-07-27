#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

/// 将页面内联「＋备忘」请求合并写入 FormMemoStore。
@interface FormMemoPageSaveCoordinator : NSObject

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)handleSaveFieldMessage:(NSDictionary *)body fromWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
