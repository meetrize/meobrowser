#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserFindSession;
@class BrowserNavigationSession;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserConnectionSecurityState) {
    BrowserConnectionSecurityStateUnknown = 0,
    BrowserConnectionSecurityStateTrusted,
    BrowserConnectionSecurityStateInsecureException,
};

@interface BrowserTab : NSObject

@property (nonatomic, readonly) NSUUID *tabID;
/// 可能为 nil：新标签页延迟创建、或休眠后已销毁。
@property (nonatomic, readonly, nullable) WKWebView *webView;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL isNewTabPage;
@property (nonatomic, assign) BOOL isLoading;
/// 固定标签：始终排在标签条左侧，紧凑显示，避免误关。
@property (nonatomic, assign, getter=isPinned) BOOL pinned;
@property (nonatomic, assign, readonly) NSInteger titleUpdateGeneration;
/// WebView document.title / WKWebView.title 变化时回调（用于刷新标签条）。
@property (nonatomic, copy, nullable) void (^titleDidChangeHandler)(BrowserTab *tab);
/// 地址栏未提交输入草稿；nil 表示使用规范展示（新标签页为空，普通页为当前 URL）。
@property (nonatomic, copy, nullable) NSString *addressBarDraft;
/// 休眠 / 懒恢复用：无 WebView 时记住应加载的 URL。
@property (nonatomic, copy, nullable) NSURL *restorableURL;
/// 待加载的 HTML 文档（查看源代码等）；优先于 restorableURL，且不写入会话。
@property (nonatomic, copy, nullable) NSString *pendingHTMLString;
/// 最近一次被选中的时间（用于休眠策略）。
@property (nonatomic, assign) NSTimeInterval lastActiveTimestamp;
/// 失活时检测到活跃媒体（或曾 pause 到元素）；用于跳过昂贵快照与加速休眠。
@property (nonatomic, assign) BOOL mediaHeavy;
/// 当前主文档连接安全态（用于地址栏「连接不安全」指示）。
@property (nonatomic, assign) BrowserConnectionSecurityState connectionSecurityState;
/// 页面内查找会话（查询词 / 模式 / 计数）；高亮在 WebView 文档侧。
@property (nonatomic, strong, nullable) BrowserFindSession *findSession;
/// window.open / OAuth 弹窗等 related browsing context：勿休眠，以免打断 opener / postMessage。
@property (nonatomic, assign, readonly) BOOL resistsHibernation;
/// 本标签作为 opener 时，仍存活的 related 弹窗数量。
@property (nonatomic, assign) NSInteger relatedPopupRetainCount;
/// 若本标签由 createWebView 创建，指向发起 window.open 的标签。
@property (nonatomic, weak, nullable) BrowserTab *relatedOpenerTab;
/// 当前主文档导航代际会话；超时看门狗须校验 generation。
@property (nonatomic, strong, nullable) BrowserNavigationSession *navigationSession;
/// 新导航会话开始时回调（用于挂上 T0 总超时）；在主线程触发。
@property (nonatomic, copy, nullable) void (^navigationSessionDidBeginHandler)(BrowserTab *tab, BrowserNavigationSession *session);
/// 硬恢复：已丢弃 WebView，待用户重新加载；唤醒时勿自动 load restorable。
@property (nonatomic, assign) BOOL pendingHardRecover;
/// 硬恢复错误文案（展示于原生错误页）。
@property (nonatomic, copy, nullable) NSString *hardRecoverMessage;

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration;
/// 接入已由 WebKit 指定 configuration 创建的 WebView（须用于 createWebView 回调）。
+ (instancetype)tabWithExistingWebView:(WKWebView *)webView;

/// 确保存在 WebView（NTP 首次导航 / 唤醒休眠时调用）。
- (WKWebView *)ensureWebView;
/// 弹窗关闭时解除与 opener 的 retain；prepareForClose 也会调用。
- (void)detachRelatedPopupOpener;
/// 关闭前主动释放内容进程：stop / 清委托 / about:blank / 离屏 / 置 nil。
- (void)prepareForClose;
/// 销毁 WebView，保留 restorableURL 与标题，便于再次选中时恢复。
- (void)hibernate;
/// NH-3 硬恢复：无条件丢弃 WebView（绕过 resistsHibernation），保留 restorableURL。
- (void)forceDiscardWebViewForHardRecover;
/// 若已休眠则仅重建 WebView，不发起导航（须先挂上 navigationDelegate，再调 loadPendingRestorableURLIfNeeded）。
- (void)wakeFromHibernationIfNeeded;
/// 在 navigationDelegate 已设置后加载 restorableURL（会话恢复 / 唤醒用）。
- (void)loadPendingRestorableURLIfNeeded;
/// 当前页面 URL，或休眠占位 URL。
- (nullable NSURL *)currentOrRestorableURL;
@property (nonatomic, readonly, getter=isHibernated) BOOL hibernated;

- (void)loadNewTabPage;
- (void)loadURL:(NSURL *)url;
/// 以内存 HTML 打开本标签（查看源代码）；不进入会话。须在挂上 navigationDelegate 后由 loadPendingRestorableURLIfNeeded 完成加载。
- (void)prepareHTMLDocument:(NSString *)html title:(NSString *)title;
- (NSString *)displayTitle;
/// 从 WKWebView.title 与 document.title 拉取页面标题并写回 tab.title。
- (void)pullDocumentTitleFromWebView;

- (void)notePendingMainFrameNavigation;
/// 开始一次被跟踪的主文档导航（递增 generation，phase=Loading）。
- (BrowserNavigationSession *)beginNavigationSessionWithURL:(nullable NSURL *)url;
- (void)clearNavigationSession;
/// 将已有会话推进到 provisional（若 generation 匹配）。
- (void)markNavigationSessionProvisional;
/// 将已有会话推进到 committed（若 generation 匹配）。
- (void)markNavigationSessionCommitted;
/// WebKit 可能传入 nil navigation（支付页跳转等）；内部已做空值安全处理。
- (BOOL)beginMainFrameNavigation:(nullable WKNavigation *)navigation;
- (BOOL)isMainFrameNavigation:(nullable WKNavigation *)navigation;
- (void)endMainFrameNavigation:(nullable WKNavigation *)navigation;

@end

NS_ASSUME_NONNULL_END
