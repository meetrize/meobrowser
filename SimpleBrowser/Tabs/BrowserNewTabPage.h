#import <Foundation/Foundation.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserNewTabPage : NSObject

+ (NSString *)html;
+ (void)loadInWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
