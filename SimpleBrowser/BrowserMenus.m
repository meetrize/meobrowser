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

@end
