#import "BrowserChromeActionItem.h"

NSString * const BrowserChromeActionAfkModeID = @"afkMode";
NSString * const BrowserChromeActionTransparentModeID = @"transparentMode";
NSString * const BrowserChromeActionCompactModeID = @"compactMode";
NSString * const BrowserChromeActionAlwaysOnTopID = @"alwaysOnTop";
NSString * const BrowserChromeActionAutoScrollID = @"autoScroll";
NSString * const BrowserChromeActionScrollSpeedID = @"scrollSpeed";
NSString * const BrowserChromeActionWindowLayoutID = @"windowLayout";

NSString * const BrowserChromeActionTabOverviewID = @"tabOverview";
NSString * const BrowserChromeActionFindInPageID = @"findInPage";
NSString * const BrowserChromeActionHistoryID = @"history";
NSString * const BrowserChromeActionDownloadID = @"download";
NSString * const BrowserChromeActionLoginAssistID = @"loginAssist";
NSString * const BrowserChromeActionCompanionLinkID = @"companionLink";
NSString * const BrowserChromeActionSendToPhoneID = @"sendToPhone";
NSString * const BrowserChromeActionNotificationInboxID = @"notificationInbox";
NSString * const BrowserChromeActionPhonePolicyID = @"phonePolicy";
NSString * const BrowserChromeActionCaptchaAssistID = @"captchaAssist";
NSString * const BrowserChromeActionRSSFeedID = @"rssFeed";
NSString * const BrowserChromeActionShareID = @"share";
NSString * const BrowserChromeActionScreenshotID = @"screenshot";
NSString * const BrowserChromeActionExtensionID = @"extension";

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

+ (NSArray<NSString *> *)addressBarMigratedActionIDs {
    return @[
        BrowserChromeActionTabOverviewID,
        BrowserChromeActionFindInPageID,
        BrowserChromeActionHistoryID,
        BrowserChromeActionDownloadID,
        BrowserChromeActionLoginAssistID,
        BrowserChromeActionCompanionLinkID,
        BrowserChromeActionSendToPhoneID,
        BrowserChromeActionNotificationInboxID,
        BrowserChromeActionPhonePolicyID,
        BrowserChromeActionCaptchaAssistID,
        BrowserChromeActionRSSFeedID,
        BrowserChromeActionShareID,
        BrowserChromeActionScreenshotID,
        BrowserChromeActionExtensionID,
    ];
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
                                    toolTip:@"设置"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionWindowLayoutID
                                 symbolName:@"arrow.down.right.and.arrow.up.left"
                               onSymbolName:@"arrow.up.left.and.arrow.down.right"
                                    toolTip:@"窗口缩小"
                                  onToolTip:@"窗口放大"
                                    toggles:YES],

        [BrowserChromeActionItem itemWithID:BrowserChromeActionTabOverviewID
                                 symbolName:@"square.grid.2x2"
                               onSymbolName:nil
                                    toolTip:@"标签概览"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionFindInPageID
                                 symbolName:@"magnifyingglass"
                               onSymbolName:nil
                                    toolTip:@"查找"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionHistoryID
                                 symbolName:@"clock"
                               onSymbolName:nil
                                    toolTip:@"历史"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionDownloadID
                                 symbolName:@"arrow.down.circle"
                               onSymbolName:nil
                                    toolTip:@"下载"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionLoginAssistID
                                 symbolName:@"key.horizontal"
                               onSymbolName:nil
                                    toolTip:@"登录助手"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionCompanionLinkID
                                 symbolName:@"link"
                               onSymbolName:nil
                                    toolTip:@"互联"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionSendToPhoneID
                                 symbolName:@"iphone.and.arrow.forward"
                               onSymbolName:nil
                                    toolTip:@"发送到手机"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionNotificationInboxID
                                 symbolName:@"bell"
                               onSymbolName:nil
                                    toolTip:@"手机通知"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionPhonePolicyID
                                 symbolName:@"phone.badge.waveform"
                               onSymbolName:nil
                                    toolTip:@"号码策略"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionCaptchaAssistID
                                 symbolName:@"checkerboard.rectangle"
                               onSymbolName:nil
                                    toolTip:@"验证码助手"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionRSSFeedID
                                 symbolName:@"dot.radiowaves.up.forward"
                               onSymbolName:nil
                                    toolTip:@"RSS"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionShareID
                                 symbolName:@"square.and.arrow.up"
                               onSymbolName:nil
                                    toolTip:@"分享"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionScreenshotID
                                 symbolName:@"camera"
                               onSymbolName:nil
                                    toolTip:@"截图"
                                  onToolTip:nil
                                    toggles:NO],
        [BrowserChromeActionItem itemWithID:BrowserChromeActionExtensionID
                                 symbolName:@"puzzlepiece.extension"
                               onSymbolName:nil
                                    toolTip:@"扩展"
                                  onToolTip:nil
                                    toggles:NO],
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
