#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserTabControllerDelegate <NSObject>
- (void)tabControllerDidChange:(id)controller;
- (void)tabControllerRequestsCloseWindow:(id)controller;
@end

@interface BrowserTabController : NSObject

@property (nonatomic, weak, nullable) id<BrowserTabControllerDelegate> delegate;
@property (nonatomic, readonly) NSArray<BrowserTab *> *tabs;
@property (nonatomic, readonly, nullable) BrowserTab *selectedTab;
@property (nonatomic, readonly) BOOL canRestoreRecentlyClosedTab;

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)configuration;

- (BrowserTab *)addNewTab;
- (BrowserTab *)addTabWithURL:(NSURL *)url;
- (void)closeTab:(BrowserTab *)tab;
- (void)closeSelectedTab;
- (void)closeOtherTabsExcept:(BrowserTab *)tab;
- (void)closeTabsToTheRightOf:(BrowserTab *)tab;
- (nullable BrowserTab *)restoreRecentlyClosedTab;
- (void)selectTab:(BrowserTab *)tab;
- (void)selectNextTab;
- (void)selectPreviousTab;
- (void)restoreTabsFromEntries:(NSArray<NSString *> *)entries selectedIndex:(NSInteger)selectedIndex;
- (NSInteger)indexOfSelectedTab;
- (nullable BrowserTab *)tabForWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
