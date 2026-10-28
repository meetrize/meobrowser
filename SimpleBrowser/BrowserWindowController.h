#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserWindowLayoutPresetStore.h"
#import "BrowserSplitLayout.h"

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
- (void)togglePagePackSidebar:(nullable id)sender;
- (void)togglePageScraperSidebar:(nullable id)sender;
- (void)toggleAIAssistantSidebar:(nullable id)sender;
/// 问问 AI：打开助手侧栏。pageContext=YES 时 context 为页面信息（标题+URL）。
- (void)openAIAssistantWithAction:(NSString *)actionKey
                          context:(nullable NSString *)context
                      pageContext:(BOOL)pageContext;
/// 加入引用：打开助手侧栏，把 payload 加入输入区引用条（不自动发送）。
/// payload: @{ @"kind": text|image|file|link|url, @"text"/"url"/"title": ... }
- (void)addAIAssistantCitation:(NSDictionary *)payload;
- (void)oneClickLogin:(nullable id)sender;
- (void)fillSiteMemo:(nullable id)sender;
- (void)toggleCaptchaAssistPanel:(nullable id)sender;
- (void)toggleDOMInspector:(nullable id)sender;

/// 标签概览 overlay。
- (void)toggleTabOverview:(nullable id)sender;
- (void)showTabOverview;
- (void)hideTabOverview;
- (BOOL)isTabOverviewVisible;
- (void)updateTabOverviewButtonAppearance;

- (void)toggleCompactMode:(nullable id)sender;
- (void)toggleAlwaysOnTop:(nullable id)sender;
- (void)toggleTransparentMode:(nullable id)sender;
- (void)toggleAfkMode:(nullable id)sender;
- (void)reloadPage:(nullable id)sender;
- (void)hardReloadPage:(nullable id)sender;
- (void)togglePresentationFullscreen:(nullable id)sender;
- (void)focusAddressBar:(nullable id)sender;
@property (nonatomic, assign, getter=isCompactModeEnabled) BOOL compactModeEnabled;
@property (nonatomic, assign, getter=isAlwaysOnTopEnabled) BOOL alwaysOnTopEnabled;
@property (nonatomic, assign, getter=isTransparentModeEnabled) BOOL transparentModeEnabled;
@property (nonatomic, assign, getter=isAfkModeEnabled) BOOL afkModeEnabled;
@property (nonatomic, assign, getter=isPresentationFullscreenActive, readonly) BOOL presentationFullscreenActive;
@property (nonatomic, assign) BrowserWindowLayoutMode windowLayoutMode;

/// 分栏脚手架(MW1): Single 时隐藏,零回归;非 Single 显示占位 panes。
- (void)setSplitLayout:(BrowserSplitLayoutID)layout weights:(nullable NSArray *)weights urls:(nullable NSArray *)urls;
- (void)focusSplitPaneAtIndex:(NSInteger)index;
- (void)setSplitLayout:(BrowserSplitLayoutID)layout weights:(nullable NSArray *)weights urls:(nullable NSArray *)urls reuseWebViews:(nullable NSArray *)reuse;
- (void)splitLayoutSingle:(nullable id)s;
- (void)splitLayoutLR:(nullable id)s;
- (void)splitLayoutUD:(nullable id)s;
- (void)splitLayoutLCR:(nullable id)s;
- (void)splitLayoutUMD:(nullable id)s;
- (void)splitLayoutQuad:(nullable id)s;
- (void)splitLayoutNine:(nullable id)s;
- (void)splitFocusNext:(nullable id)s;
- (void)splitChromeAlways:(nullable id)s;
- (void)splitChromeAutohide:(nullable id)s;
- (void)splitChromeHidden:(nullable id)s;
- (void)splitSaveCurrentAsPreset:(nullable id)s;
- (void)splitDeletePreset:(nullable id)s;
- (void)splitLoadPreset:(nullable id)s;
- (void)togglePaneSync:(nullable id)s;
- (BOOL)isSplitActive;
- (void)splitZoomInPane:(nullable id)s;
- (void)splitZoomOutPane:(nullable id)s;
- (void)splitZoomResetPane:(nullable id)s;

/// 透明模式右键拖窗进行中时抑制 WebKit 上下文菜单。
- (BOOL)shouldSuppressContextMenuForTransparentRightDrag;

/// 透明模式右键拖窗时暂时藏起壳层，避免移窗过程正文闪动。
@property (nonatomic, assign) BOOL transparentChromeRevealSuppressedForDrag;

/// 供 LoginAssistController 打开助手侧栏。
- (void)setAssistSidebarVisible:(BOOL)visible
              revealingRecipeID:(nullable NSString *)recipeID
                         memoID:(nullable NSString *)memoID;
- (void)reloadAssistSidebarIfVisible;

/// 将「允许网页检查」偏好同步到本窗所有 live WKWebView。
- (void)applyWebInspectionPreferenceToLiveWebViews;
/// 同步到应用内全部浏览器窗口。
+ (void)applyWebInspectionPreferenceAcrossWindows;
@end

NS_ASSUME_NONNULL_END
