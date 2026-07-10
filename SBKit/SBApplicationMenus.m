#import "SBApplicationMenus.h"

@implementation SBApplicationMenus

+ (void)installStandardMenusWithAppName:(NSString *)appName {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    [mainMenu addItem:[self appMenuItemWithAppName:appName]];
    [mainMenu addItem:[self editMenuItem]];
    [mainMenu addItem:[self windowMenuItem]];

    [NSApp setMainMenu:mainMenu];
}

#pragma mark - Menu Sections

+ (NSMenuItem *)appMenuItemWithAppName:(NSString *)appName {
    NSString *title = [NSString stringWithFormat:@"%@", appName];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];

    [menu addItemWithTitle:[NSString stringWithFormat:@"隐藏 %@", appName]
                    action:@selector(hide:)
             keyEquivalent:@"h"];
    NSMenuItem *hideOthersItem = [menu addItemWithTitle:@"隐藏其他"
                                                 action:@selector(hideOtherApplications:)
                                          keyEquivalent:@"h"];
    hideOthersItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [menu addItemWithTitle:@"显示全部"
                    action:@selector(unhideAllApplications:)
             keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:[NSString stringWithFormat:@"退出 %@", appName]
                    action:@selector(terminate:)
             keyEquivalent:@"q"];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.submenu = menu;
    return item;
}

+ (NSMenuItem *)editMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"编辑"];

    [menu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redoItem = [menu addItemWithTitle:@"重做"
                                           action:@selector(redo:)
                                    keyEquivalent:@"Z"];
    [redoItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [menu addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
    [menu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [menu addItemWithTitle:@"删除" action:@selector(delete:) keyEquivalent:@""];
    [menu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.submenu = menu;
    return item;
}

+ (NSMenuItem *)windowMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [menu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [menu addItemWithTitle:@"缩放" action:@selector(performZoom:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"前置全部窗口"
                    action:@selector(arrangeInFront:)
             keyEquivalent:@""];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.submenu = menu;
    return item;
}

@end
