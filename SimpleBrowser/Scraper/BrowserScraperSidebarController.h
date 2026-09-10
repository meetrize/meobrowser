#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@class BrowserScraperSidebarController;

@protocol BrowserScraperSidebarControllerDelegate <NSObject>
- (void)scraperSidebarDidRequestClose:(BrowserScraperSidebarController *)controller;
- (void)scraperSidebar:(BrowserScraperSidebarController *)controller didChangeWidth:(CGFloat)width;
- (nullable NSURL *)scraperSidebarCurrentURL:(BrowserScraperSidebarController *)controller;
- (nullable WKWebView *)scraperSidebarCurrentWebView:(BrowserScraperSidebarController *)controller;
- (void)scraperSidebar:(BrowserScraperSidebarController *)controller
didReceivePickMessage:(id)body;
@end

@interface BrowserScraperSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<BrowserScraperSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadForCurrentURL;
- (void)handlePickMessageBody:(id)body;

@end

NS_ASSUME_NONNULL_END
