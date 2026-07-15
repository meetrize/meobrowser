#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

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
/// 地址栏未提交输入草稿；nil 表示使用规范展示（新标签页为空，普通页为当前 URL）。
@property (nonatomic, copy, nullable) NSString *addressBarDraft;
/// 休眠 / 懒恢复用：无 WebView 时记住应加载的 URL。
@property (nonatomic, copy, nullable) NSURL *restorableURL;
/// 最近一次被选中的时间（用于休眠策略）。
@property (nonatomic, assign) NSTimeInterval lastActiveTimestamp;
/// 当前主文档连接安全态（用于地址栏「连接不安全」指示）。
@property (nonatomic, assign) BrowserConnectionSecurityState connectionSecurityState;

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration;

/// 确保存在 WebView（NTP 首次导航 / 唤醒休眠时调用）。
- (WKWebView *)ensureWebView;
/// 关闭前主动释放内容进程：stop / 清委托 / about:blank / 离屏 / 置 nil。
- (void)prepareForClose;
/// 销毁 WebView，保留 restorableURL 与标题，便于再次选中时恢复。
- (void)hibernate;
/// 若已休眠则重建 WebView 并加载 restorableURL。
- (void)wakeFromHibernationIfNeeded;
/// 当前页面 URL，或休眠占位 URL。
- (nullable NSURL *)currentOrRestorableURL;
@property (nonatomic, readonly, getter=isHibernated) BOOL hibernated;

- (void)loadNewTabPage;
- (void)loadURL:(NSURL *)url;
- (NSString *)displayTitle;

- (void)notePendingMainFrameNavigation;
- (BOOL)beginMainFrameNavigation:(WKNavigation *)navigation;
- (BOOL)isMainFrameNavigation:(WKNavigation *)navigation;
- (void)endMainFrameNavigation:(WKNavigation *)navigation;

@end

NS_ASSUME_NONNULL_END
