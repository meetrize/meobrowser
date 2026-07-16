#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface CaptchaAssistController : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, weak, nullable) NSButton *captchaButton;
@property (nonatomic, strong, readonly) NSArray *currentDetections;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;
- (void)wireCaptchaButton:(NSButton *)button;
- (void)updateForURL:(nullable NSURL *)url;
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(nullable NSURL *)url;

- (IBAction)toggleCaptchaAssistPanel:(nullable id)sender;
- (void)solveNow;
- (void)captureNow;

@end

NS_ASSUME_NONNULL_END
