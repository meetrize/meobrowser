#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "BrowserSettingsWindowController.h"
#import "BrowserMenus.h"
#import "BrowserAppInfo.h"
#import "SBApplicationMenus.h"
#import "BrowsingPreferences.h"

@implementation AppDelegate {
    BrowserWindowController *_browserWindowController;
    BrowserSettingsWindowController *_settingsWindowController;
    NSMutableArray<NSURL *> *_pendingExternalURLs;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _pendingExternalURLs = [NSMutableArray array];
    [SBApplicationMenus installStandardMenusWithAppName:BrowserAppDisplayName];
    [BrowserMenus installSettingsMenuForTarget:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _browserWindowController = [[BrowserWindowController alloc] init];
    [_browserWindowController showWindow:nil];
    [_browserWindowController.window center];
    [_browserWindowController scheduleTrafficLightPositioning];
    [self flushPendingExternalURLs];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    if (urls.count == 0) {
        return;
    }
    if (_browserWindowController) {
        [_browserWindowController openURLsFromExternalSource:urls];
        return;
    }
    [_pendingExternalURLs addObjectsFromArray:urls];
}

- (void)flushPendingExternalURLs {
    if (_pendingExternalURLs.count == 0 || !_browserWindowController) {
        return;
    }
    NSArray<NSURL *> *urls = [_pendingExternalURLs copy];
    [_pendingExternalURLs removeAllObjects];
    [_browserWindowController openURLsFromExternalSource:urls];
}

- (void)showBrowserSettings:(id)sender {
    (void)sender;
    if (!_settingsWindowController) {
        _settingsWindowController = [[BrowserSettingsWindowController alloc] init];
    }
    [_settingsWindowController showWindow:nil];
    [_settingsWindowController.window center];
    [_settingsWindowController.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_browserWindowController persistTabSession];
}

@end
