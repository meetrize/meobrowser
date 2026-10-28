#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserAIAssistantSidebarController;

@protocol BrowserAIAssistantSidebarControllerDelegate <NSObject>
- (void)aiAssistantSidebarDidRequestClose:(BrowserAIAssistantSidebarController *)controller;
- (void)aiAssistantSidebarDidRequestOpenBridge:(BrowserAIAssistantSidebarController *)controller;
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

@end

NS_ASSUME_NONNULL_END
