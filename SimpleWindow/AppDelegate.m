#import "AppDelegate.h"
#import "MainWindowController.h"

@implementation AppDelegate {
    MainWindowController *_mainWindowController;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _mainWindowController = [[MainWindowController alloc] init];
    [_mainWindowController showWindow:nil];
    [_mainWindowController.window center];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end
