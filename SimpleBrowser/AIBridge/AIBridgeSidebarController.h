#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AIBridgeSidebarController;
@class BrowserTab;

@protocol AIBridgeSidebarControllerDelegate <NSObject>
- (void)aiBridgeSidebarDidRequestClose:(AIBridgeSidebarController *)controller;
- (nullable BrowserTab *)aiBridgeSidebarCurrentTab:(AIBridgeSidebarController *)controller;
- (nullable NSURL *)aiBridgeSidebarCurrentURL:(AIBridgeSidebarController *)controller;
- (nullable WKWebView *)aiBridgeSidebarCurrentWebView:(AIBridgeSidebarController *)controller;
/// 智能绑定：已有匹配标签则选中绑定；否则打开首页再绑定。
- (void)aiBridgeSidebar:(AIBridgeSidebarController *)controller
 bindOrOpenProviderId:(NSString *)providerId
           completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;
@end

@interface AIBridgeSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<AIBridgeSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadUI;

@end

NS_ASSUME_NONNULL_END
