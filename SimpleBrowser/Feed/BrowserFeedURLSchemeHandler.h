#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 自定义 scheme，使 Feed 可读页进入 WKWebView 后退栈。
@interface BrowserFeedURLSchemeHandler : NSObject <WKURLSchemeHandler>
@end

NS_ASSUME_NONNULL_END
