#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserAIAssistantSidebarController;
@class AIAssistantSession;
@class AIBridgeBinding;

@protocol BrowserAIAssistantSidebarControllerDelegate <NSObject>
- (void)aiAssistantSidebarDidRequestClose:(BrowserAIAssistantSidebarController *)controller;
- (void)aiAssistantSidebarDidRequestOpenBridge:(BrowserAIAssistantSidebarController *)controller;

/// 始终新开平台首页并绑定，供新建会话
- (void)aiAssistantSidebar:(BrowserAIAssistantSidebarController *)controller
openAndBindProviderId:(NSString *)providerId
            sessionId:(NSString *)sessionId
           completion:(void (^)(AIBridgeBinding *_Nullable binding, NSString *_Nullable errorDetail))completion;

- (void)aiAssistantSidebar:(BrowserAIAssistantSidebarController *)controller
     focusTabForBindingId:(NSString *)bindingId;

- (void)aiAssistantSidebar:(BrowserAIAssistantSidebarController *)controller
reopenAndBindProviderId:(NSString *)providerId
              sessionId:(NSString *)sessionId
             completion:(void (^)(AIBridgeBinding *_Nullable binding, NSString *_Nullable errorDetail))completion;

/// 当前浏览标签（非 Bridge 绑定页）的 WebView / tabID，供页面上下文采集。
- (nullable WKWebView *)aiAssistantSidebarCurrentWebView:(BrowserAIAssistantSidebarController *)controller;
- (nullable NSUUID *)aiAssistantSidebarCurrentTabID:(BrowserAIAssistantSidebarController *)controller;

/// 打开页面爬虫侧栏并套用草稿配方。
- (void)aiAssistantSidebar:(BrowserAIAssistantSidebarController *)controller
applyScraperDraftRecipe:(id)recipe;
@end

@interface BrowserAIAssistantSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<BrowserAIAssistantSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadUI;

/// 划词 / 页面入口。pageContext=YES 时 context 为页面信息（标题+URL）。
/// pageContext + summarize 会走正文采集（Page Context）。
- (void)presentAction:(NSString *)actionKey
              context:(NSString *)context
          pageContext:(BOOL)pageContext
             autoSend:(BOOL)autoSend;

/// 运行内置页面 Recipe（如 summarize-page）：采集当前页 → 挂 Citation → 填提示 → 可选发送。
- (void)presentPageRecipe:(NSString *)recipeId autoSend:(BOOL)autoSend;

/// 将当前 Bundle 草稿导入页面爬虫侧栏（由 WindowController 打开爬虫）。
- (void)exportCurrentBundleToPasteboard;
- (void)exportCurrentBundleToDownloads;
- (void)startPickPageSubtreeForCitation;
- (void)applyCurrentContextToScraperDraft;
- (void)showRegexLab;

/// 右键「加入引用」：只加入输入区引用条，不自动发送。
/// payload: kind / text / url / title / thumb(data URL)
- (void)addCitationFromPayload:(NSDictionary *)payload;
/// 为图片引用补缩略图（data:image/...）
- (void)applyPreviewDataURL:(nullable NSString *)dataURL forImageURLString:(nullable NSString *)imageURL;
- (void)applyPreviewImage:(nullable NSImage *)image forImageURLString:(nullable NSString *)imageURL;

@end

NS_ASSUME_NONNULL_END
