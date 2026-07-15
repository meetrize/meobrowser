#import <Cocoa/Cocoa.h>

@class BrowserWindowController;
@class BrowserTab;
@class BrowserTabStripView;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)newBrowserWindow:(nullable id)sender;
- (void)openURLInNewBrowserWindow:(NSURL *)url;
- (void)persistAllBrowserWindowSessions;
- (void)browserWindowControllerWillClose:(BrowserWindowController *)controller;
- (nullable BrowserWindowController *)keyBrowserWindowController;
- (BrowserWindowController *)createBrowserWindowWithSession:(nullable NSDictionary *)session;
- (BrowserWindowController *)createBrowserWindowAdoptingTab:(BrowserTab *)tab
                                                      frame:(NSRect)frame;
- (nullable BrowserWindowController *)browserWindowAtScreenPoint:(NSPoint)screenPoint
                                                       excluding:(nullable BrowserWindowController *)source;
- (void)hideForeignDropPlaceholdersExcludingStrip:(nullable BrowserTabStripView *)strip;

@end

NS_ASSUME_NONNULL_END
