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

@end
