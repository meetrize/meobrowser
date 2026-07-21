#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LoginAssistController : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, weak, nullable) NSButton *loginButton;
@property (nonatomic, assign, readonly) BOOL isRunning;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;
- (void)updateForURL:(nullable NSURL *)url;
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(nullable NSURL *)url;

- (IBAction)oneClickLogin:(nullable id)sender;
- (void)runRecipe:(LoginRecipe *)recipe;
- (void)cancelPendingAutoLogin;
- (void)showRecipeMenuFromButton:(NSButton *)button;

- (void)presentSettingsEditingRecipeID:(nullable NSString *)recipeID;
/// 打开设置并滚到互联状态卡片（工具栏「互联」入口）。
- (void)presentCompanionSettings;
- (void)wireLoginButton:(NSButton *)button;
- (nullable WKWebView *)activeWebViewForPicking;

@end

NS_ASSUME_NONNULL_END
