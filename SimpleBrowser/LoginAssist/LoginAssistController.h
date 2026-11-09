#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class FormMemo;
@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LoginAssistController : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, weak, nullable) NSButton *loginButton;
@property (nonatomic, assign, readonly) BOOL isRunning;
/// 当前页有匹配的登录 Recipe 或站点备忘时可一键登录/填入。
@property (nonatomic, assign, readonly) BOOL canOneClickLogin;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;
- (void)updateForURL:(nullable NSURL *)url;
/// 主框架 commit：尽早推送内联开关，避免 DocumentEnd 把开关打成 false 后、表单已挂载却不再扫描。
- (void)noteNavigationCommittedInWebView:(WKWebView *)webView;
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(nullable NSURL *)url;

- (IBAction)oneClickLogin:(nullable id)sender;
- (IBAction)fillSiteMemo:(nullable id)sender;
- (void)runRecipe:(LoginRecipe *)recipe;
- (void)runRecipe:(LoginRecipe *)recipe fillOnly:(BOOL)fillOnly;
- (void)runMemo:(FormMemo *)memo;
- (void)cancelPendingAutoLogin;
- (void)showRecipeMenuFromButton:(NSButton *)button;

/// 将登录助手相关项追加到工具栏右键菜单（固定/隐藏之后）。
- (void)appendItemsToToolbarContextMenu:(NSMenu *)menu;

- (void)presentAssistSidebar;
- (void)presentAssistSidebarRevealingRecipeID:(nullable NSString *)recipeID;
- (void)presentAssistSidebarRevealingMemoID:(nullable NSString *)memoID;
- (void)presentSettingsEditingRecipeID:(nullable NSString *)recipeID;
- (void)presentSettingsEditingMemoID:(nullable NSString *)memoID;
/// 打开设置并滚到互联状态卡片（工具栏「互联」入口）。
- (void)presentCompanionSettings;
- (void)wireLoginButton:(NSButton *)button;
- (void)wireOneClickLoginButton:(NSButton *)button;
- (nullable WKWebView *)activeWebViewForPicking;

@end

NS_ASSUME_NONNULL_END
