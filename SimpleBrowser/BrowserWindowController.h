#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserTabController;
@class BrowserTab;
@class BrowserTabStripView;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserWindowController : NSWindowController <WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate>

@property (nonatomic, readonly, nullable) WKWebView *webView;
@property (nonatomic, strong, readonly) BrowserTabController *tabController;
@property (nonatomic, strong, readonly) BrowserTabStripView *tabStripView;

- (instancetype)initWithSessionDictionary:(nullable NSDictionary *)session;
- (instancetype)init;
/// 创建空窗口（无标签），供 adoptTab: 迁入已有标签（保留 WKWebView）。
- (instancetype)initForTabAdoption;
- (void)adoptTab:(BrowserTab *)tab;
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;
/// 将本窗标签真迁移到另一浏览器窗指定下标。
- (void)transferTabID:(NSUUID *)tabID
             toWindow:(BrowserWindowController *)destination
              atIndex:(NSUInteger)index;

- (void)persistTabSession;
/// 当前窗口会话快照（tabs / selectedIndex / pinnedCount / frame）。
- (NSDictionary *)sessionDictionary;
/// 用会话字典恢复标签与可选窗口 frame；session 为空或无效时打开 NTP。
- (void)applySessionDictionary:(nullable NSDictionary *)session;
- (void)refreshTabsUI;
- (void)scheduleTrafficLightPositioning;
- (void)openURLsFromExternalSource:(NSArray<NSURL *> *)urls;
- (void)showLoginAssistSettings:(nullable id)sender;
- (void)showCompanionLinkSettings:(nullable id)sender;
- (void)showFormMemoSettings:(nullable id)sender;
- (void)toggleAssistSidebar:(nullable id)sender;
- (void)showAssistSidebar:(nullable id)sender;
- (void)toggleNotificationInboxSidebar:(nullable id)sender;
- (void)oneClickLogin:(nullable id)sender;
- (void)fillSiteMemo:(nullable id)sender;
- (void)toggleCaptchaAssistPanel:(nullable id)sender;

/// 标签概览 overlay。
- (void)toggleTabOverview:(nullable id)sender;
- (void)showTabOverview;
- (void)hideTabOverview;
- (BOOL)isTabOverviewVisible;
- (void)updateTabOverviewButtonAppearance;

/// 供 LoginAssistController 打开助手侧栏。
- (void)setAssistSidebarVisible:(BOOL)visible
              revealingRecipeID:(nullable NSString *)recipeID
                         memoID:(nullable NSString *)memoID;
- (void)reloadAssistSidebarIfVisible;
@end

NS_ASSUME_NONNULL_END
