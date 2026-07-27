#import <Foundation/Foundation.h>

@class PhoneNotificationSidebarController;
@class AssistSidebarController;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTrailingSidebarKind) {
    BrowserTrailingSidebarKindNone = 0,
    BrowserTrailingSidebarKindNotification = 1,
    BrowserTrailingSidebarKindAssist = 2,
};

/// 统一管理 trailing 侧栏互斥（通知收件箱 / 助手侧栏）。
@interface BrowserTrailingSidebarSlot : NSObject

@property (nonatomic, weak, nullable) PhoneNotificationSidebarController *notificationSidebar;
@property (nonatomic, weak, nullable) AssistSidebarController *assistSidebar;
@property (nonatomic, assign, readonly) BrowserTrailingSidebarKind activeKind;

- (void)setNotificationVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setAssistVisible:(BOOL)visible animated:(BOOL)animated;
- (void)hideAllAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
