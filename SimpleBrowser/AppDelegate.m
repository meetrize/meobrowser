#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "SBApplicationMenus.h"

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
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end
