#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "BrowserSettingsWindowController.h"
#import "BrowserLoginAssistSettingsWindowController.h"
#import "BrowserMenus.h"
#import "BrowserAppInfo.h"
#import "SBApplicationMenus.h"
#import "BrowsingPreferences.h"
#import "BrowserTab.h"
#import "BrowserTabStripView.h"
#import "CompanionChannel.h"
#import "ServerSyncEngine.h"
#import "ServerSyncSettings.h"
#import "ServerSyncKeychain.h"
#import "BrowserHistoryStore.h"
#import "BrowserDeveloperPreferences.h"
#import "BrowserUserAgent.h"
#import "BrowserStatusItemController.h"

@implementation AppDelegate {
    NSMutableArray<BrowserWindowController *> *_browserWindows;
    BrowserSettingsWindowController *_settingsWindowController;
    BrowserLoginAssistSettingsWindowController *_loginAssistSettingsController;
    NSMutableArray<NSURL *> *_pendingExternalURLs;
    NSInteger _windowCascadeIndex;
    /// 退出流程中窗口会先关闭再走 terminate；此标志避免关窗时把已保存的会话覆盖成空。
    BOOL _isTerminating;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    // 地址栏等工具按钮悬停时立刻显示功能名 Tooltip（单位：毫秒）
    NSMutableDictionary *defaults = [@{@"NSInitialToolTipDelay": @1} mutableCopy];
#if DEBUG
    // Debug 构建默认允许网页检查，便于本机调试；Release 仍默认关。
    defaults[@"MeoBrowserAllowWebInspection"] = @YES;
#endif
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    _browserWindows = [NSMutableArray array];
    _pendingExternalURLs = [NSMutableArray array];
    [SBApplicationMenus installStandardMenusWithAppName:BrowserAppDisplayName];
    [BrowserMenus installSettingsMenuForTarget:self];
    [BrowserMenus installBrowserChromeMenus];
    [BrowserUserAgent warmUpInBackground];
    [ServerSyncKeychain warmMemoryCacheInBackground];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(developerPreferencesDidChange:)
                                                 name:BrowserDeveloperPreferencesDidChangeNotification
                                               object:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [BrowserUserAgent scheduleMainQueueSampleIfNeeded];
    [[CompanionChannel sharedChannel] start];
    // startIfNeeded 内部会判登录；此处勿再先读一次钥匙串 token。
    if (ServerSyncSettings.sharedSettings.enabled) {
        [[ServerSyncEngine sharedEngine] startIfNeeded];
    }
    NSArray<NSDictionary *> *sessions = [BrowsingPreferences savedWindowSessions];
    if (sessions.count == 0) {
        [self createBrowserWindowWithSession:nil];
    } else {
        for (NSDictionary *session in sessions) {
            [self createBrowserWindowWithSession:session];
        }
    }
    [self flushPendingExternalURLs];
    [[BrowserStatusItemController sharedController] install];
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

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    (void)sender;
    if (filename.length == 0) {
        return NO;
    }
    NSURL *url = [NSURL fileURLWithPath:filename];
    [self application:NSApp openURLs:@[ url ]];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    (void)sender;
    if (filenames.count == 0) {
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:filenames.count];
    for (NSString *path in filenames) {
        if (path.length == 0) {
            continue;
        }
        [urls addObject:[NSURL fileURLWithPath:path]];
    }
    if (urls.count == 0) {
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
        return;
    }
    [self application:NSApp openURLs:urls];
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
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

- (void)showBrowserSettingsSelectingTabIdentifier:(NSString *)identifier {
    [self showBrowserSettings:nil];
    [_settingsWindowController selectTabWithIdentifier:identifier];
}

- (void)showLoginAssistSettings:(id)sender {
    (void)sender;
    BrowserWindowController *keyBrowser = [self keyBrowserWindowController];
    if (keyBrowser) {
        [keyBrowser showLoginAssistSettings:sender];
        return;
    }
    if (!_loginAssistSettingsController) {
        _loginAssistSettingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
    }
    [_loginAssistSettingsController showWindow:nil];
    [_loginAssistSettingsController.window center];
    [_loginAssistSettingsController.window makeKeyAndOrderFront:nil];
}

- (void)showFormMemoSettings:(id)sender {
    (void)sender;
    BrowserWindowController *keyBrowser = [self keyBrowserWindowController];
    if (keyBrowser) {
        [keyBrowser showFormMemoSettings:sender];
        return;
    }
    if (!_loginAssistSettingsController) {
        _loginAssistSettingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
    }
    [_loginAssistSettingsController showWindow:nil];
    [_loginAssistSettingsController.window center];
    [_loginAssistSettingsController.window makeKeyAndOrderFront:nil];
    [_loginAssistSettingsController revealMemoSection];
}

- (void)showCompanionLinkSettings:(id)sender {
    (void)sender;
    BrowserWindowController *keyBrowser = [self keyBrowserWindowController];
    if (keyBrowser) {
        [keyBrowser showCompanionLinkSettings:sender];
        return;
    }
    if (!_loginAssistSettingsController) {
        _loginAssistSettingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
    }
    [_loginAssistSettingsController showWindow:nil];
    [_loginAssistSettingsController.window center];
    [_loginAssistSettingsController.window makeKeyAndOrderFront:nil];
    [_loginAssistSettingsController revealCompanionSection];
}

- (void)browserWindowControllerWillClose:(BrowserWindowController *)controller {
    if (!controller) {
        return;
    }

    BOOL isLastBrowserWindow = (_browserWindows.count == 1 &&
                                [_browserWindows containsObject:controller]);

    if (_isTerminating) {
        // ⌘Q 等路径已在 applicationShouldTerminate: 写过完整会话，勿再以空列表覆盖。
        [_browserWindows removeObject:controller];
        return;
    }

    if (isLastBrowserWindow) {
        // 关最后一窗会触发退出：先写入含本窗的会话，再移出列表。
        [self persistAllBrowserWindowSessions];
        _isTerminating = YES;
        [_browserWindows removeObject:controller];
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

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    // Cmd+Q / Dock 退出：在 AppKit 关闭各窗口之前先落盘当前全部窗口+标签。
    if (!_isTerminating) {
        [self persistAllBrowserWindowSessions];
        _isTerminating = YES;
    }
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (!_isTerminating) {
        [self persistAllBrowserWindowSessions];
        _isTerminating = YES;
    }
    [[BrowserHistoryStore sharedStore] clearIfConfiguredOnQuit];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)developerPreferencesDidChange:(NSNotification *)notification {
    (void)notification;
    [BrowserWindowController applyWebInspectionPreferenceAcrossWindows];
}

@end
