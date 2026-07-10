#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "BrowserSettingsWindowController.h"
#import "BrowserMenus.h"
#import "SBApplicationMenus.h"
#import "BrowsingPreferences.h"

@implementation AppDelegate {
    BrowserWindowController *_browserWindowController;
    BrowserSettingsWindowController *_settingsWindowController;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [SBApplicationMenus installStandardMenusWithAppName:@"SimpleBrowser"];
    [BrowserMenus installSettingsMenuForTarget:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _browserWindowController = [[BrowserWindowController alloc] init];
    [_browserWindowController showWindow:nil];
    [_browserWindowController.window center];
    [_browserWindowController scheduleTrafficLightPositioning];
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
