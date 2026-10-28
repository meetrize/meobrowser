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
@end

@interface AIBridgeSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<AIBridgeSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadUI;

@end

NS_ASSUME_NONNULL_END
