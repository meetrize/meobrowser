#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserScraperPickMode) {
    BrowserScraperPickModeContainer = 0,
    BrowserScraperPickModeField = 1,
    BrowserScraperPickModePagination = 2,
};

typedef void (^BrowserScraperPickCompletion)(NSDictionary * _Nullable result, BOOL cancelled);

@interface BrowserScraperElementPicker : NSObject

+ (void)registerMessageHandlerOnConfiguration:(WKWebViewConfiguration *)configuration
                                      handler:(id<WKScriptMessageHandler>)handler;

+ (void)startPickingInWebView:(WKWebView *)webView
                         mode:(BrowserScraperPickMode)mode
                   completion:(BrowserScraperPickCompletion)completion;

/// 字段点选时可传入循环上下文，生成相对行节点的可复用 path（而非某张卡片的绝对 path）。
+ (void)startPickingInWebView:(WKWebView *)webView
                         mode:(BrowserScraperPickMode)mode
                containerPath:(nullable NSString *)containerPath
                      rowPath:(nullable NSString *)rowPath
                   completion:(BrowserScraperPickCompletion)completion;

+ (void)handleScriptMessageBody:(id)body;
+ (void)cancelActivePick;

@end

NS_ASSUME_NONNULL_END
