#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "SBApplicationMenus.h"
#import "BrowsingPreferences.h"

@implementation AppDelegate {
    BrowserWindowController *_browserWindowController;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [SBApplicationMenus installStandardMenusWithAppName:@"SimpleBrowser"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _browserWindowController = [[BrowserWindowController alloc] init];
    [_browserWindowController showWindow:nil];
    [_browserWindowController.window center];
    [_browserWindowController scheduleTrafficLightPositioning];
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
