#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class PagePackSidebarController;

NS_ASSUME_NONNULL_BEGIN

@protocol PagePackSidebarControllerDelegate <NSObject>
- (void)pagePackSidebarDidRequestClose:(PagePackSidebarController *)controller;
- (void)pagePackSidebar:(PagePackSidebarController *)controller didChangeWidth:(CGFloat)width;
- (nullable NSURL *)pagePackSidebarCurrentURL:(PagePackSidebarController *)controller;
- (nullable WKWebView *)pagePackSidebarCurrentWebView:(PagePackSidebarController *)controller;
- (void)pagePackSidebarDidRequestReloadPage:(PagePackSidebarController *)controller;
@end

@interface PagePackSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<PagePackSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadForCurrentURL;
- (void)revealPackID:(nullable NSString *)packID;

@end

NS_ASSUME_NONNULL_END
