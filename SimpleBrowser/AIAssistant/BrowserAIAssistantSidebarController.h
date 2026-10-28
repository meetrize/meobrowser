#import <AppKit/AppKit.h>

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
@end

@interface BrowserAIAssistantSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<BrowserAIAssistantSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadUI;

/// 划词 / 页面入口。pageContext=YES 时 context 为页面信息（标题+URL）。
- (void)presentAction:(NSString *)actionKey
              context:(NSString *)context
          pageContext:(BOOL)pageContext
             autoSend:(BOOL)autoSend;

/// 右键「加入引用」：只加入输入区引用条，不自动发送。
/// payload: kind / text / url / title
- (void)addCitationFromPayload:(NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
