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
                                                     keyEquivalent:@""];
            captchaAssist.target = nil;

            NSMenuItem *domInspector = [fileMenu addItemWithTitle:@"DOM 探针"
                                                           action:@selector(toggleDOMInspector:)
                                                    keyEquivalent:@"c"];
            domInspector.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
            domInspector.target = nil;

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

            [viewMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *splitRoot = [[NSMenuItem alloc] initWithTitle:@"分栏" action:nil keyEquivalent:@""];
            NSMenu *splitMenu = [[NSMenu alloc] initWithTitle:@"分栏"];
            NSArray *layouts = @[
                @[@"单栏", @"splitLayoutSingle:", @""],
                @[@"左右双栏", @"splitLayoutLR:", @""],
                @[@"上下双栏", @"splitLayoutUD:", @""],
                @[@"左中右三栏", @"splitLayoutLCR:", @""],
                @[@"上中下三栏", @"splitLayoutUMD:", @""],
                @[@"四方格", @"splitLayoutQuad:", @""],
                @[@"九宫格", @"splitLayoutNine:", @""],
            ];
            for (NSArray *e in layouts) {
                NSMenuItem *it = [splitMenu addItemWithTitle:e[0] action:NSSelectorFromString(e[1]) keyEquivalent:e[2]];
                it.target = nil;
            }
            [splitMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *fn = [splitMenu addItemWithTitle:@"聚焦下一栏" action:@selector(splitFocusNext:) keyEquivalent:@"]"];
            fn.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
            fn.target = nil;
            [splitMenu addItem:[NSMenuItem separatorItem]];
            NSArray *chromes = @[
                @[@"地址栏:总是显示", @"splitChromeAlways:"],
                @[@"地址栏:自动隐藏", @"splitChromeAutohide:"],
                @[@"地址栏:隐藏", @"splitChromeHidden:"],
            ];
            for (NSArray *e in chromes) {
                NSMenuItem *it = [splitMenu addItemWithTitle:e[0] action:NSSelectorFromString(e[1]) keyEquivalent:@""];
                it.target = nil;
            }
            [splitMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *saveP = [splitMenu addItemWithTitle:@"保存当前为预设…" action:@selector(splitSaveCurrentAsPreset:) keyEquivalent:@""];
            saveP.target = nil;
            NSMenuItem *delP = [splitMenu addItemWithTitle:@"删除预设…" action:@selector(splitDeletePreset:) keyEquivalent:@""];
            [splitMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *syncT = [splitMenu addItemWithTitle:@"同步输入开/关" action:@selector(togglePaneSync:) keyEquivalent:@""];
            syncT.target = nil;
            delP.target = nil;
            // 预设动态项由 BrowserWindowController 在菜单打开时重建(tag 9000+)
            splitRoot.submenu = splitMenu;

            [viewMenu addItem:splitRoot];

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

        // 工具：插在「窗口」之前
        if (![self menuExistsWithTitle:@"工具"]) {
            NSMenuItem *toolsItem = [[NSMenuItem alloc] init];
            NSMenu *tools = [[NSMenu alloc] initWithTitle:@"工具"];
            NSMenuItem *aiBridge = [tools addItemWithTitle:@"AI Bridge…"
                                                     action:@selector(toggleAIBridgeSidebar:)
                                              keyEquivalent:@""];
            aiBridge.target = nil;
            toolsItem.submenu = tools;
            NSInteger windowIndex = [self indexOfMenuTitled:@"窗口"];
            if (windowIndex == NSNotFound) {
                [mainMenu addItem:toolsItem];
            } else {
                [mainMenu insertItem:toolsItem atIndex:windowIndex];
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
