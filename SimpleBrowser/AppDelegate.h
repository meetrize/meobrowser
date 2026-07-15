#import <Cocoa/Cocoa.h>

@class BrowserWindowController;
@class BrowserTab;

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

@end

NS_ASSUME_NONNULL_END
