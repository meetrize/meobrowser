#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserTab;
@class BrowserTabController;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserTabControllerDelegate <NSObject>
- (void)tabControllerDidChange:(id)controller;
- (void)tabControllerRequestsCloseWindow:(id)controller;

@optional
/// 关闭前确认；返回 NO 则取消本次关闭。tabs 为本次操作将关闭的标签。
- (BOOL)tabController:(BrowserTabController *)controller shouldCloseTabs:(NSArray<BrowserTab *> *)tabs;
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
/// @param select YES 时选中新标签（默认行为）；NO 时仅插入，保持当前选中不变。
- (BrowserTab *)addTabWithURL:(NSURL *)url select:(BOOL)select;
/// 打开只读 HTML 内容标签（查看源代码等）；不进入会话恢复。
- (BrowserTab *)addTabWithHTMLString:(NSString *)html title:(NSString *)title;
/// 接入 createWebView 返回的 related WebView；会选中该标签并保留与 opener 的关联。
- (BrowserTab *)addRelatedPopupTabWithWebView:(WKWebView *)webView initialURL:(nullable NSURL *)url;
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
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;
- (void)restoreTabsFromEntries:(NSArray<NSString *> *)entries
                 selectedIndex:(NSInteger)selectedIndex
                   pinnedCount:(NSUInteger)pinnedCount;
- (NSInteger)indexOfSelectedTab;
- (nullable BrowserTab *)tabForWebView:(WKWebView *)webView;

/// 即将创建 WKWebView 前调用：必要时硬休眠后台重页，避免 live 顶满时主线程卡死。
+ (void)reclaimBeforeCreatingWebViewIfNeeded;

@end

NS_ASSUME_NONNULL_END
