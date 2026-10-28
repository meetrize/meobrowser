#import <Foundation/Foundation.h>

@class PhoneNotificationSidebarController;
@class AssistSidebarController;
@class BrowserHistorySidebarController;
@class PagePackSidebarController;
@class BrowserScraperSidebarController;
@class AIBridgeSidebarController;
@class BrowserAIAssistantSidebarController;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTrailingSidebarKind) {
    BrowserTrailingSidebarKindNone = 0,
    BrowserTrailingSidebarKindNotification = 1,
    BrowserTrailingSidebarKindAssist = 2,
    BrowserTrailingSidebarKindHistory = 3,
    BrowserTrailingSidebarKindPagePack = 4,
    BrowserTrailingSidebarKindScraper = 5,
    BrowserTrailingSidebarKindAIBridge = 6,
    BrowserTrailingSidebarKindAIAssistant = 7,
};

/// 统一管理 trailing 侧栏互斥（通知 / 助手 / 历史 / 插件 / 爬虫 / AI Bridge / AI 助手）。
@interface BrowserTrailingSidebarSlot : NSObject

@property (nonatomic, weak, nullable) PhoneNotificationSidebarController *notificationSidebar;
@property (nonatomic, weak, nullable) AssistSidebarController *assistSidebar;
@property (nonatomic, weak, nullable) BrowserHistorySidebarController *historySidebar;
@property (nonatomic, weak, nullable) PagePackSidebarController *pagePackSidebar;
@property (nonatomic, weak, nullable) BrowserScraperSidebarController *scraperSidebar;
@property (nonatomic, weak, nullable) AIBridgeSidebarController *aiBridgeSidebar;
@property (nonatomic, weak, nullable) BrowserAIAssistantSidebarController *aiAssistantSidebar;
@property (nonatomic, assign, readonly) BrowserTrailingSidebarKind activeKind;

- (void)setNotificationVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setAssistVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setHistoryVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setPagePackVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setScraperVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setAIBridgeVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setAIAssistantVisible:(BOOL)visible animated:(BOOL)animated;
- (void)hideAllAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
