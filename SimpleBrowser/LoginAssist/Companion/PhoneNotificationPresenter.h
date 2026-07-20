#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 将 Companion 推送的手机通知 / OTP 转为 macOS 系统通知。
/// NM-0：空实现；NM-2 接入 UNUserNotificationCenter。
@interface PhoneNotificationPresenter : NSObject

+ (instancetype)sharedPresenter;

/// 申请系统通知权限（可重复调用，内部只真正请求一次）。
- (void)requestAuthorizationIfNeeded;

/// 展示 `phone_notification` 载荷。返回 YES 表示已处理（含因设置关闭而跳过）。
- (BOOL)presentFromPayload:(NSDictionary *)payload;

/// 在 OTP 入 Inbox 后可选弹横幅；若近期已镜像过通知则应跳过（NM-2）。
- (void)presentOTPBannerIfNeededWithCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
