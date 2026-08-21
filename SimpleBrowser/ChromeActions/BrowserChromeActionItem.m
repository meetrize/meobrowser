#import "BrowserChromeActionItem.h"

NSString * const BrowserChromeActionAfkModeID = @"afkMode";
NSString * const BrowserChromeActionTransparentModeID = @"transparentMode";
NSString * const BrowserChromeActionCompactModeID = @"compactMode";
NSString * const BrowserChromeActionAlwaysOnTopID = @"alwaysOnTop";
NSString * const BrowserChromeActionAutoScrollID = @"autoScroll";
NSString * const BrowserChromeActionScrollSpeedID = @"scrollSpeed";
NSString * const BrowserChromeActionWindowLayoutID = @"windowLayout";
NSString * const BrowserChromeActionMoreMenuID = @"moreMenu";

@implementation BrowserChromeActionItem

+ (instancetype)itemWithID:(NSString *)itemID
                symbolName:(NSString *)symbolName
              onSymbolName:(NSString *)onSymbolName
                   toolTip:(NSString *)toolTip
                 onToolTip:(NSString *)onToolTip
                   toggles:(BOOL)toggles {
    BrowserChromeActionItem *item = [[BrowserChromeActionItem alloc] init];
    item.itemID = itemID;
    item.symbolName = symbolName;
    item.onSymbolName = onSymbolName;
    item.toolTip = toolTip;
    item.onToolTip = onToolTip;
    item.toggles = toggles;
    return item;
}

+ (NSArray<BrowserChromeActionItem *> *)catalogItemsExcludingMoreMenu {
    return @[
        [BrowserChromeActionItem itemWithID:BrowserChromeActionAfkModeID
                                 symbolName:@"eye"
                               onSymbolName:@"eye.slash"
                                    toolTip:@"摸鱼模式"
                                  onToolTip:@"退出摸鱼模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionTransparentModeID
                                 symbolName:@"cube.transparent"
                               onSymbolName:@"cube.transparent"
                                    toolTip:@"透明模式"
                                  onToolTip:@"退出透明模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionCompactModeID
                                 symbolName:@"rectangle.topthird.inset.filled"
                               onSymbolName:@"rectangle.topthird.inset.filled"
                                    toolTip:@"精简模式"
                                  onToolTip:@"退出精简模式"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionAlwaysOnTopID
                                 symbolName:@"pin"
                               onSymbolName:@"pin.fill"
                                    toolTip:@"窗口置顶"
                                  onToolTip:@"取消置顶"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionAutoScrollID
                                 symbolName:@"arrow.down.to.line"
                               onSymbolName:@"arrow.down.to.line"
                                    toolTip:@"自动滚动"
                                  onToolTip:@"停止自动滚动"
                                    toggles:YES],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionScrollSpeedID
                                 symbolName:@"slider.horizontal.3"
                               onSymbolName:nil
                                    toolTip:@"滚动速度…"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionWindowLayoutID
                                 symbolName:@"arrow.down.right.and.arrow.up.left"
                               onSymbolName:@"arrow.up.left.and.arrow.down.right"
                                    toolTip:@"窗口缩小"
                                  onToolTip:@"窗口放大"
                                    toggles:YES],
    ];
}

+ (BrowserChromeActionItem *)moreMenuItem {
    return [BrowserChromeActionItem itemWithID:BrowserChromeActionMoreMenuID
                                    symbolName:@"ellipsis"
                                  onSymbolName:nil
                                       toolTip:@"更多"
                                     onToolTip:nil
                                       toggles:NO];
}

+ (nullable BrowserChromeActionItem *)catalogItemWithID:(NSString *)itemID {
    if (itemID.length == 0) {
        return nil;
    }
    if ([itemID isEqualToString:BrowserChromeActionMoreMenuID]) {
        return [self moreMenuItem];
    }
    for (BrowserChromeActionItem *item in [self catalogItemsExcludingMoreMenu]) {
        if ([item.itemID isEqualToString:itemID]) {
            return item;
        }
    }
    return nil;
}

@end
