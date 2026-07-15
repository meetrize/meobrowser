#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "BrowserSettingsWindowController.h"
#import "BrowserMenus.h"
#import "BrowserAppInfo.h"
#import "SBApplicationMenus.h"
#import "BrowsingPreferences.h"
#import "BrowserTab.h"
#import "BrowserTabStripView.h"

@implementation AppDelegate {
    NSMutableArray<BrowserWindowController *> *_browserWindows;
    BrowserSettingsWindowController *_settingsWindowController;
    NSMutableArray<NSURL *> *_pendingExternalURLs;
    NSInteger _windowCascadeIndex;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _browserWindows = [NSMutableArray array];
    _pendingExternalURLs = [NSMutableArray array];
    [SBApplicationMenus installStandardMenusWithAppName:BrowserAppDisplayName];
    [BrowserMenus installSettingsMenuForTarget:self];
    [BrowserMenus installBrowserChromeMenus];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSArray<NSDictionary *> *sessions = [BrowsingPreferences savedWindowSessions];
    if (sessions.count == 0) {
        [self createBrowserWindowWithSession:nil];
    } else {
        for (NSDictionary *session in sessions) {
            [self createBrowserWindowWithSession:session];
        }
    }
    [self flushPendingExternalURLs];
}

- (BrowserWindowController *)createBrowserWindowWithSession:(NSDictionary *)session {
    BrowserWindowController *controller = [[BrowserWindowController alloc] initWithSessionDictionary:session];
    [_browserWindows addObject:controller];
    [controller showWindow:nil];

    NSString *frameString = session[BrowserWindowSessionFrameKey];
    BOOL hasValidFrame = NO;
    if ([frameString isKindOfClass:[NSString class]] && frameString.length > 0) {
        NSRect frame = NSRectFromString(frameString);
        if (frame.size.width >= 400 && frame.size.height >= 300) {
            [controller.window setFrame:frame display:YES];
            hasValidFrame = YES;
        }
    }
    if (!hasValidFrame) {
        if (_browserWindows.count == 1) {
            [controller.window center];
        } else {
            [self cascadeWindow:controller.window];
        }
    }

    [controller scheduleTrafficLightPositioning];
    return controller;
}

- (BrowserWindowController *)createBrowserWindowAdoptingTab:(BrowserTab *)tab frame:(NSRect)frame {
    BrowserWindowController *controller = [[BrowserWindowController alloc] initForTabAdoption];
    [_browserWindows addObject:controller];
    [controller adoptTab:tab];
    [controller showWindow:nil];
    if (frame.size.width >= 400 && frame.size.height >= 300) {
        [controller.window setFrame:frame display:YES];
    } else if (_browserWindows.count == 1) {
        [controller.window center];
    } else {
        [self cascadeWindow:controller.window];
    }
    [controller scheduleTrafficLightPositioning];
    return controller;
}

- (nullable BrowserWindowController *)browserWindowAtScreenPoint:(NSPoint)screenPoint
                                                       excluding:(BrowserWindowController *)source {
    for (NSWindow *window in NSApp.orderedWindows) {
        NSWindowController *wc = window.windowController;
        if (![wc isKindOfClass:[BrowserWindowController class]]) {
            continue;
        }
        BrowserWindowController *browser = (BrowserWindowController *)wc;
        if (browser == source) {
            continue;
        }
        if (![_browserWindows containsObject:browser]) {
            continue;
        }
        BrowserTabStripView *strip = browser.tabStripView;
        if (!strip) {
            continue;
        }
        if (NSPointInRect(screenPoint, [strip stripEffectiveZoneInScreen])) {
            return browser;
        }
    }
    return nil;
}

- (void)hideForeignDropPlaceholdersExcludingStrip:(BrowserTabStripView *)strip {
    for (BrowserWindowController *browser in _browserWindows) {
        BrowserTabStripView *candidate = browser.tabStripView;
        if (!candidate || candidate == strip) {
            continue;
        }
        [candidate hideForeignDropPlaceholder];
    }
}

- (void)cascadeWindow:(NSWindow *)window {
    NSRect screenFrame = NSScreen.mainScreen.visibleFrame;
    CGFloat offset = 22.0 * (CGFloat)(_windowCascadeIndex % 8);
    _windowCascadeIndex += 1;
    NSRect frame = window.frame;
    frame.origin.x = NSMinX(screenFrame) + 40.0 + offset;
    frame.origin.y = NSMaxY(screenFrame) - NSHeight(frame) - 40.0 - offset;
    [window setFrame:frame display:YES];
}

- (void)newBrowserWindow:(id)sender {
    (void)sender;
    [self createBrowserWindowWithSession:nil];
}

- (void)openURLInNewBrowserWindow:(NSURL *)url {
    if (!url) {
        [self createBrowserWindowWithSession:nil];
        return;
    }
    NSDictionary *session = @{
        BrowserWindowSessionTabsKey: @[url.absoluteString ?: BrowserTabSessionNewTabMarker],
        BrowserWindowSessionSelectedIndexKey: @0,
        BrowserWindowSessionPinnedCountKey: @0,
    };
    BrowserWindowController *controller = [self createBrowserWindowWithSession:session];
    [controller.window makeKeyAndOrderFront:nil];
}

- (nullable BrowserWindowController *)keyBrowserWindowController {
    NSWindowController *controller = NSApp.keyWindow.windowController;
    if ([controller isKindOfClass:[BrowserWindowController class]]) {
        return (BrowserWindowController *)controller;
    }
    for (BrowserWindowController *browser in _browserWindows) {
        if (browser.window.isVisible) {
            return browser;
        }
    }
    return _browserWindows.firstObject;
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    if (urls.count == 0) {
        return;
    }
    BrowserWindowController *target = [self keyBrowserWindowController];
    if (target) {
        [target openURLsFromExternalSource:urls];
        [target.window makeKeyAndOrderFront:nil];
        return;
    }
    [_pendingExternalURLs addObjectsFromArray:urls];
}

- (void)flushPendingExternalURLs {
    if (_pendingExternalURLs.count == 0) {
        return;
    }
    BrowserWindowController *target = [self keyBrowserWindowController];
    if (!target) {
        target = [self createBrowserWindowWithSession:nil];
    }
    NSArray<NSURL *> *urls = [_pendingExternalURLs copy];
    [_pendingExternalURLs removeAllObjects];
    [target openURLsFromExternalSource:urls];
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

- (void)browserWindowControllerWillClose:(BrowserWindowController *)controller {
    if (!controller) {
        return;
    }
    [_browserWindows removeObject:controller];
    [self persistAllBrowserWindowSessions];
}

- (void)persistAllBrowserWindowSessions {
    NSMutableArray<NSDictionary *> *sessions = [[NSMutableArray alloc] init];
    for (BrowserWindowController *controller in _browserWindows) {
        NSDictionary *session = [controller sessionDictionary];
        if (session.count > 0) {
            [sessions addObject:session];
        }
    }
    [BrowsingPreferences saveWindowSessions:sessions];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self persistAllBrowserWindowSessions];
}

@end
