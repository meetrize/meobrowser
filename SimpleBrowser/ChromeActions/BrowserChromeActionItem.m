#import "BrowserChromeActionItem.h"

NSString * const BrowserChromeActionCompactModeID = @"compactMode";
NSString * const BrowserChromeActionAlwaysOnTopID = @"alwaysOnTop";

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

@end
