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
/// 拖拽标签离开标签条时预热一个隐藏的“收养窗口”，drop 为真窗口时直接复用，
/// 避免现场建整套 chrome 造成的拖出延迟。重复调用无开销。
- (void)prewarmBrowserWindowForTabAdoption;
/// 本次拖拽不会新建窗口（窗内排序 / 拖到其它窗口）时释放预热窗口。
- (void)discardPrewarmedBrowserWindow;
- (nullable BrowserWindowController *)browserWindowAtScreenPoint:(NSPoint)screenPoint
                                                       excluding:(nullable BrowserWindowController *)source;
- (void)hideForeignDropPlaceholdersExcludingStrip:(nullable BrowserTabStripView *)strip;
- (void)showBrowserSettings:(nullable id)sender;
- (void)showBrowserSettingsSelectingTabIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
