#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;
@class BrowserFeedItem;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFeedAssistController : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, weak, nullable) NSButton *feedButton;
@property (nonatomic, copy, readonly) NSArray<BrowserFeedItem *> *currentFeeds;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;
- (void)wireFeedButton:(NSButton *)button;
- (void)updateForURL:(nullable NSURL *)url;
- (void)noteNavigationStartedInWebView:(WKWebView *)webView;
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(nullable NSURL *)url;

/// 若为 Feed 响应则取消默认导航并渲染可读页，返回 YES。
- (BOOL)handleNavigationResponseIfFeed:(WKNavigationResponse *)navigationResponse
                               webView:(WKWebView *)webView
                       decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler;

- (IBAction)showFeedMenu:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
