#import "BrowserMenus.h"

@implementation BrowserMenus

+ (BOOL)menuExistsWithTitle:(NSString *)title {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return NO;
    }
    for (NSMenuItem *item in mainMenu.itemArray) {
        if ([item.submenu.title isEqualToString:title]) {
            return YES;
        }
    }
    return NO;
}

+ (NSInteger)indexOfMenuTitled:(NSString *)title {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return NSNotFound;
    }
    for (NSInteger i = 0; i < mainMenu.numberOfItems; i++) {
        if ([mainMenu.itemArray[i].submenu.title isEqualToString:title]) {
            return i;
        }
    }
    return NSNotFound;
}

+ (void)installBrowserChromeMenus {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMenu *mainMenu = [NSApp mainMenu];
        if (!mainMenu) {
            return;
        }

        // 文件：插在「编辑」之前 → App / 文件 / 编辑 / …
        if (![self menuExistsWithTitle:@"文件"]) {
            NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
            NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"文件"];

            NSMenuItem *newWindow = [fileMenu addItemWithTitle:@"新建窗口"
                                                        action:@selector(newBrowserWindow:)
                                                 keyEquivalent:@"n"];
            newWindow.target = NSApp.delegate;

            NSMenuItem *openInNewWindow = [fileMenu addItemWithTitle:@"在新窗口打开当前页"
                                                              action:@selector(openCurrentPageInNewBrowserWindow:)
                                                       keyEquivalent:@""];
            openInNewWindow.target = nil;

            NSMenuItem *downloads = [fileMenu addItemWithTitle:@"下载"
                                                        action:@selector(toggleDownloadsPanel:)
                                                 keyEquivalent:@"j"];
            downloads.target = nil;

            NSMenuItem *loginAssist = [fileMenu addItemWithTitle:@"一键登录"
                                                          action:@selector(oneClickLogin:)
                                                   keyEquivalent:@"l"];
            loginAssist.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            loginAssist.target = nil;

            NSMenuItem *loginSettings = [fileMenu addItemWithTitle:@"登录助手…"
                                                            action:@selector(showLoginAssistSettings:)
                                                     keyEquivalent:@""];
            loginSettings.target = nil;

            NSMenuItem *captchaAssist = [fileMenu addItemWithTitle:@"验证码助手"
                                                            action:@selector(toggleCaptchaAssistPanel:)
                                                     keyEquivalent:@"c"];
            captchaAssist.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            captchaAssist.target = nil;

            fileMenuItem.submenu = fileMenu;
            NSInteger editIndex = [self indexOfMenuTitled:@"编辑"];
            if (editIndex == NSNotFound) {
                [mainMenu addItem:fileMenuItem];
            } else {
                [mainMenu insertItem:fileMenuItem atIndex:editIndex];
            }
        }

        // 查看：插在「窗口」之前
        if (![self menuExistsWithTitle:@"查看"]) {
            NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
            NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"查看"];

            NSMenuItem *zoomIn = [viewMenu addItemWithTitle:@"放大"
                                                     action:@selector(zoomIn:)
                                              keyEquivalent:@"="];
            zoomIn.target = nil;

            NSMenuItem *zoomOut = [viewMenu addItemWithTitle:@"缩小"
                                                      action:@selector(zoomOut:)
                                               keyEquivalent:@"-"];
            zoomOut.target = nil;

            NSMenuItem *actualSize = [viewMenu addItemWithTitle:@"实际大小"
                                                         action:@selector(actualSize:)
                                                  keyEquivalent:@"0"];
            actualSize.target = nil;

            viewMenuItem.submenu = viewMenu;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:viewMenuItem];
            } else {
                [mainMenu insertItem:viewMenuItem atIndex:windowIndex];
            }
        }

        // 标签页：插在「窗口」之前（查看之后）
        if (![self menuExistsWithTitle:@"标签页"]) {
            NSMenuItem *tabMenuItem = [[NSMenuItem alloc] init];
            NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"标签页"];

            NSMenuItem *newTab = [tabMenu addItemWithTitle:@"新建标签页"
                                                    action:@selector(newBrowserTab:)
                                             keyEquivalent:@"t"];
            newTab.target = nil;

            NSMenuItem *closeTab = [tabMenu addItemWithTitle:@"关闭标签页"
                                                      action:@selector(closeBrowserTab:)
                                               keyEquivalent:@"w"];
            closeTab.target = nil;

            NSMenuItem *restoreTab = [tabMenu addItemWithTitle:@"恢复最近关闭的标签页"
                                                        action:@selector(restoreRecentlyClosedBrowserTab:)
                                                 keyEquivalent:@"t"];
            restoreTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            restoreTab.target = nil;

            [tabMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *prevTab = [tabMenu addItemWithTitle:@"上一个标签页"
                                                     action:@selector(selectPreviousBrowserTab:)
                                              keyEquivalent:@"["];
            prevTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            prevTab.target = nil;

            NSMenuItem *nextTab = [tabMenu addItemWithTitle:@"下一个标签页"
                                                     action:@selector(selectNextBrowserTab:)
                                              keyEquivalent:@"]"];
            nextTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            nextTab.target = nil;

            tabMenuItem.submenu = tabMenu;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:tabMenuItem];
            } else {
                [mainMenu insertItem:tabMenuItem atIndex:windowIndex];
            }
        }
    });
}

+ (void)installTabMenuForTarget:(id)target {
    (void)target;
    [self installBrowserChromeMenus];
}

+ (void)installSettingsMenuForTarget:(id)target {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu || mainMenu.numberOfItems == 0) {
        return;
    }

    NSMenu *appMenu = mainMenu.itemArray[0].submenu;
    if (!appMenu) {
        return;
    }

    for (NSMenuItem *item in appMenu.itemArray) {
        if (item.action == @selector(showBrowserSettings:)) {
            return;
        }
    }

    NSInteger quitIndex = appMenu.numberOfItems - 1;
    if (quitIndex > 0) {
        [appMenu insertItem:[NSMenuItem separatorItem] atIndex:quitIndex];
        quitIndex += 1;
    }

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"设置…"
                                                          action:@selector(showBrowserSettings:)
                                                   keyEquivalent:@","];
    settingsItem.target = target;
    [appMenu insertItem:settingsItem atIndex:quitIndex];
}

+ (void)installDownloadMenuForTarget:(id)target {
    (void)target;
    [self installBrowserChromeMenus];
}

+ (void)installViewMenuForTarget:(id)target {
    (void)target;
    [self installBrowserChromeMenus];
}

@end
