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
@property (nonatomic, readonly) NSUInteger pinnedTabCount;

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
- (void)moveTab:(BrowserTab *)tab toIndex:(NSUInteger)toIndex;
- (void)setTab:(BrowserTab *)tab pinned:(BOOL)pinned;
/// 从本控制器摘出标签，保留 WebView / 页面状态；不写入「最近关闭」。若摘空则 selectedTab 置 nil（关窗由调用方处理）。
- (nullable BrowserTab *)extractTabKeepingAlive:(BrowserTab *)tab;
/// 接入已有标签（含存活 WebView），并选中。
- (void)adoptTab:(BrowserTab *)tab;
- (void)restoreTabsFromEntries:(NSArray<NSString *> *)entries
                 selectedIndex:(NSInteger)selectedIndex
                   pinnedCount:(NSUInteger)pinnedCount;
- (NSInteger)indexOfSelectedTab;
- (nullable BrowserTab *)tabForWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
