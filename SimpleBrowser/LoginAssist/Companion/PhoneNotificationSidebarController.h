#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PhoneNotificationSidebarController;

@protocol PhoneNotificationSidebarControllerDelegate <NSObject>
- (void)notificationSidebarDidRequestClose:(PhoneNotificationSidebarController *)controller;
- (void)notificationSidebarDidRequestCompanionSettings:(PhoneNotificationSidebarController *)controller;
- (void)notificationSidebar:(PhoneNotificationSidebarController *)controller didChangeWidth:(CGFloat)width;
@end

/// 右侧手机通知收件箱侧栏（壳 + 列表管理）。
@interface PhoneNotificationSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<PhoneNotificationSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadList;
- (void)refreshEmptyState;
/// 打开后定位并高亮条目；`itemID` 可为 `otp-code:123456` 以匹配最近 OTP。
- (void)revealItemID:(nullable NSString *)itemID;
- (nullable NSString *)selectedItemID;

@end

NS_ASSUME_NONNULL_END
