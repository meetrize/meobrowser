#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserWindowController;
@class BrowserFindBarView;
@class BrowserFindSession;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFindBarController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, strong, readonly) BrowserFindBarView *findBarView;
@property (nonatomic, assign, readonly, getter=isVisible) BOOL visible;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)installInContentContainer:(NSView *)contentContainer;
- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration;

- (IBAction)showFindBar:(nullable id)sender;
/// 工具栏按钮用：已打开则关闭，未打开则打开。
- (IBAction)toggleFindBar:(nullable id)sender;
- (IBAction)findNext:(nullable id)sender;
- (IBAction)findPrevious:(nullable id)sender;
- (IBAction)useSelectionForFind:(nullable id)sender;

- (void)hideFindBarClearingHighlights:(BOOL)clearHighlights;
- (void)syncWithSelectedTab;
- (void)noteNavigationCommittedInWebView:(WKWebView *)webView;
- (void)noteNavigationFinishedInWebView:(WKWebView *)webView;
- (BOOL)canFindInCurrentPage;

@end

NS_ASSUME_NONNULL_END
