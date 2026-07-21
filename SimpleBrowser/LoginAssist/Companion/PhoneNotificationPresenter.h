#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PhoneNotificationInboxRevealItemNotification;
/// userInfo[@"id"] 为收件箱条目 id（可空，仍应打开侧栏）。
extern NSString * const PhoneNotificationInboxRevealItemIDKey;

/// 将 Companion 推送的手机通知 / OTP 转为 macOS 系统通知。
@interface PhoneNotificationPresenter : NSObject

+ (instancetype)sharedPresenter;

/// 申请系统通知权限（可重复调用，内部只真正请求一次）。
- (void)requestAuthorizationIfNeeded;

/// 展示 `phone_notification` 载荷。返回 YES 表示已处理（含因设置关闭而跳过）。
- (BOOL)presentFromPayload:(NSDictionary *)payload;

/// 在 OTP 入 Inbox 后可选弹横幅；若近期已镜像过通知则应跳过。
- (void)presentOTPBannerIfNeededWithCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
