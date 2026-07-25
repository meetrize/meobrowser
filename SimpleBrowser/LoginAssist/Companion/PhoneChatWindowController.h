#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PhoneNotificationItem;

/// 微信通知衍生会话窗：展示入/出站历史，发送后不关闭。
@interface PhoneChatWindowController : NSWindowController

+ (void)openOrFocusForContact:(NSString *)contact
                  packageName:(NSString *)packageName
               notificationID:(nullable NSString *)notificationID;

+ (void)openOrFocusForNotificationItem:(PhoneNotificationItem *)item;

@end

NS_ASSUME_NONNULL_END
