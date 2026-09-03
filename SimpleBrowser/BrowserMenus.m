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

            NSMenuItem *openLocation = [fileMenu addItemWithTitle:@"打开位置…"
                                                           action:@selector(focusAddressBar:)
                                                    keyEquivalent:@"l"];
            openLocation.target = nil;

            NSMenuItem *downloads = [fileMenu addItemWithTitle:@"下载"
                                                        action:@selector(toggleDownloadsPanel:)
                                                 keyEquivalent:@"j"];
            downloads.target = nil;

            NSMenuItem *loginAssist = [fileMenu addItemWithTitle:@"一键登录"
                                                          action:@selector(oneClickLogin:)
                                                   keyEquivalent:@"l"];
            loginAssist.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            loginAssist.target = nil;

            NSMenuItem *fillMemo = [fileMenu addItemWithTitle:@"填入站点备忘"
                                                       action:@selector(fillSiteMemo:)
                                                keyEquivalent:@"m"];
            fillMemo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            fillMemo.target = nil;

            NSMenuItem *assistSidebar = [fileMenu addItemWithTitle:@"助手侧栏"
                                                            action:@selector(toggleAssistSidebar:)
                                                     keyEquivalent:@"a"];
            assistSidebar.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            assistSidebar.target = nil;

            NSMenuItem *loginSettings = [fileMenu addItemWithTitle:@"登录助手…"
                                                            action:@selector(showLoginAssistSettings:)
                                                     keyEquivalent:@""];
            loginSettings.target = nil;

            NSMenuItem *memoSettings = [fileMenu addItemWithTitle:@"站点备忘…"
                                                           action:@selector(showFormMemoSettings:)
                                                    keyEquivalent:@""];
            memoSettings.target = nil;

            NSMenuItem *companionSettings = [fileMenu addItemWithTitle:@"互联与配对…"
                                                                action:@selector(showCompanionLinkSettings:)
                                                         keyEquivalent:@""];
            companionSettings.target = nil;

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

            NSMenuItem *reload = [viewMenu addItemWithTitle:@"刷新"
                                                     action:@selector(reloadPage:)
                                              keyEquivalent:@"r"];
            reload.target = nil;

            NSMenuItem *hardReload = [viewMenu addItemWithTitle:@"强制刷新"
                                                         action:@selector(hardReloadPage:)
                                                  keyEquivalent:@"r"];
            hardReload.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            hardReload.target = nil;

            NSMenuItem *compactMode = [viewMenu addItemWithTitle:@"精简模式"
                                                          action:@selector(toggleCompactMode:)
                                                   keyEquivalent:@""];
            compactMode.target = nil;

            NSMenuItem *afkMode = [viewMenu addItemWithTitle:@"摸鱼模式"
                                                      action:@selector(toggleAfkMode:)
                                               keyEquivalent:@""];
            afkMode.target = nil;

            NSMenuItem *transparentMode = [viewMenu addItemWithTitle:@"透明模式"
                                                              action:@selector(toggleTransparentMode:)
                                                       keyEquivalent:@""];
            transparentMode.target = nil;

            NSMenuItem *presentationFullscreen = [viewMenu addItemWithTitle:@"进入全屏"
                                                                     action:@selector(togglePresentationFullscreen:)
                                                              keyEquivalent:[NSString stringWithFormat:@"%C", (unichar)NSF11FunctionKey]];
            presentationFullscreen.target = nil;

            [viewMenu addItem:[NSMenuItem separatorItem]];

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

            [viewMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *findInPage = [viewMenu addItemWithTitle:@"在页面中查找"
                                                         action:@selector(showFindBar:)
                                                  keyEquivalent:@"f"];
            findInPage.target = nil;

            NSMenuItem *findNext = [viewMenu addItemWithTitle:@"查找下一个"
                                                       action:@selector(findNext:)
                                                keyEquivalent:@"g"];
            findNext.target = nil;

            NSMenuItem *findPrevious = [viewMenu addItemWithTitle:@"查找上一个"
                                                           action:@selector(findPrevious:)
                                                    keyEquivalent:@"g"];
            findPrevious.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            findPrevious.target = nil;

            NSMenuItem *useSelection = [viewMenu addItemWithTitle:@"使用所选内容来查找"
                                                           action:@selector(useSelectionForFind:)
                                                    keyEquivalent:@"e"];
            useSelection.target = nil;

            [viewMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *webInspector = [viewMenu addItemWithTitle:@"打开 Web Inspector"
                                                           action:@selector(openWebInspector:)
                                                    keyEquivalent:@"i"];
            webInspector.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
            webInspector.target = nil;

            NSMenuItem *viewSource = [viewMenu addItemWithTitle:@"查看网页源代码"
                                                         action:@selector(viewPageSource:)
                                                  keyEquivalent:@"u"];
            viewSource.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
            viewSource.target = nil;

            [viewMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *notificationInbox = [viewMenu addItemWithTitle:@"手机通知"
                                                                 action:@selector(toggleNotificationInboxSidebar:)
                                                          keyEquivalent:@"i"];
            notificationInbox.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            notificationInbox.target = nil;

            NSMenuItem *pagePack = [viewMenu addItemWithTitle:@"页面插件"
                                                       action:@selector(togglePagePackSidebar:)
                                                keyEquivalent:@"p"];
            pagePack.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            pagePack.target = nil;

            viewMenuItem.submenu = viewMenu;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:viewMenuItem];
            } else {
                [mainMenu insertItem:viewMenuItem atIndex:windowIndex];
            }
        }

        // 历史：插在「窗口」之前（查看之后）
        if (![self menuExistsWithTitle:@"历史"]) {
            NSMenuItem *historyMenuItem = [[NSMenuItem alloc] init];
            NSMenu *historyMenu = [[NSMenu alloc] initWithTitle:@"历史"];

            NSMenuItem *showHistory = [historyMenu addItemWithTitle:@"显示历史侧栏"
                                                             action:@selector(toggleHistoryPanel:)
                                                      keyEquivalent:@"y"];
            showHistory.target = nil;

            historyMenuItem.submenu = historyMenu;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:historyMenuItem];
            } else {
                [mainMenu insertItem:historyMenuItem atIndex:windowIndex];
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

            NSMenuItem *forceStopTab = [tabMenu addItemWithTitle:@"强制停止此标签"
                                                          action:@selector(forceStopSelectedTab:)
                                                   keyEquivalent:@""];
            forceStopTab.target = nil;

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

            [tabMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *overview = [tabMenu addItemWithTitle:@"显示标签概览"
                                                      action:@selector(toggleTabOverview:)
                                               keyEquivalent:@"\\"];
            overview.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            overview.target = nil;

            [tabMenu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *sendToPhone = [tabMenu addItemWithTitle:@"发送到手机"
                                                         action:@selector(sendCurrentTabToPhone:)
                                                  keyEquivalent:@""];
            sendToPhone.target = nil;

            tabMenuItem.submenu = tabMenu;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:tabMenuItem];
            } else {
                [mainMenu insertItem:tabMenuItem atIndex:windowIndex];
            }
        }

        // 窗口：在系统「窗口」菜单顶部插入「窗口置顶」
        NSInteger windowMenuIndex = [self indexOfMenuTitled:@"窗口"];
        if (windowMenuIndex != NSNotFound) {
            NSMenu *windowMenu = mainMenu.itemArray[windowMenuIndex].submenu;
            BOOL hasPin = NO;
            for (NSMenuItem *item in windowMenu.itemArray) {
                if (item.action == @selector(toggleAlwaysOnTop:)) {
                    hasPin = YES;
                    break;
                }
            }
            if (!hasPin) {
                NSMenuItem *pinItem = [[NSMenuItem alloc] initWithTitle:@"窗口置顶"
                                                                 action:@selector(toggleAlwaysOnTop:)
                                                          keyEquivalent:@""];
                pinItem.target = nil;
                [windowMenu insertItem:pinItem atIndex:0];
                [windowMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
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
