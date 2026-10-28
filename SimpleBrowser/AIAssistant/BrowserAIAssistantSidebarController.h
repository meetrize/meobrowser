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

/// 划词 / 外部入口：填入 prompt；autoSend 且模型已绑定时自动发送。
- (void)presentAction:(NSString *)actionKey
            selection:(NSString *)selection
             autoSend:(BOOL)autoSend;

@end

NS_ASSUME_NONNULL_END
