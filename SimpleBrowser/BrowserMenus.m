#import "BrowserMenus.h"

@implementation BrowserMenus

+ (void)installTabMenuForTarget:(id)target {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return;
    }

    NSMenuItem *tabMenuItem = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"标签页"];

    NSMenuItem *newTab = [menu addItemWithTitle:@"新建标签页"
                                         action:@selector(newBrowserTab:)
                                  keyEquivalent:@"t"];
    newTab.target = target;

    NSMenuItem *closeTab = [menu addItemWithTitle:@"关闭标签页"
                                           action:@selector(closeBrowserTab:)
                                    keyEquivalent:@"w"];
    closeTab.target = target;

    NSMenuItem *restoreTab = [menu addItemWithTitle:@"恢复最近关闭的标签页"
                                             action:@selector(restoreRecentlyClosedBrowserTab:)
                                      keyEquivalent:@"t"];
    restoreTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    restoreTab.target = target;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prevTab = [menu addItemWithTitle:@"上一个标签页"
                                          action:@selector(selectPreviousBrowserTab:)
                                   keyEquivalent:@"["];
    prevTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    prevTab.target = target;

    NSMenuItem *nextTab = [menu addItemWithTitle:@"下一个标签页"
                                          action:@selector(selectNextBrowserTab:)
                                   keyEquivalent:@"]"];
    nextTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    nextTab.target = target;

    tabMenuItem.submenu = menu;
    [mainMenu addItem:tabMenuItem];
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
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return;
    }

    // 插在「标签页」之前；若尚未安装标签页菜单则追加到末尾。
    NSInteger insertIndex = mainMenu.numberOfItems;
    for (NSInteger i = 0; i < mainMenu.numberOfItems; i++) {
        if ([mainMenu.itemArray[i].submenu.title isEqualToString:@"标签页"]) {
            insertIndex = i;
            break;
        }
    }

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"文件"];

    NSMenuItem *downloads = [menu addItemWithTitle:@"下载"
                                            action:@selector(toggleDownloadsPanel:)
                                     keyEquivalent:@"j"];
    downloads.target = target;

    fileMenuItem.submenu = menu;
    [mainMenu insertItem:fileMenuItem atIndex:insertIndex];
}

+ (void)installViewMenuForTarget:(id)target {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return;
    }

    // 插在「窗口」之前；符合 App / 编辑 / 查看 / 窗口 惯例。
    NSInteger insertIndex = mainMenu.numberOfItems;
    for (NSInteger i = 0; i < mainMenu.numberOfItems; i++) {
        if ([mainMenu.itemArray[i].submenu.title isEqualToString:@"窗口"]) {
            insertIndex = i;
            break;
        }
    }

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"查看"];

    NSMenuItem *zoomIn = [menu addItemWithTitle:@"放大"
                                         action:@selector(zoomIn:)
                                  keyEquivalent:@"="];
    zoomIn.target = target;

    NSMenuItem *zoomOut = [menu addItemWithTitle:@"缩小"
                                          action:@selector(zoomOut:)
                                   keyEquivalent:@"-"];
    zoomOut.target = target;

    NSMenuItem *actualSize = [menu addItemWithTitle:@"实际大小"
                                             action:@selector(actualSize:)
                                      keyEquivalent:@"0"];
    actualSize.target = target;

    viewMenuItem.submenu = menu;
    [mainMenu insertItem:viewMenuItem atIndex:insertIndex];
}

@end
