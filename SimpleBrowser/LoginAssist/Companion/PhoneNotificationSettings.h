#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 手机通知镜像相关开关（UserDefaults）。
@interface PhoneNotificationSettings : NSObject

+ (instancetype)sharedSettings;

/// 是否以系统通知横幅展示 `phone_notification`（默认 YES）。收件箱入库见 `PhoneNotificationInboxSettings.inboxEnabled`。
@property (nonatomic, assign) BOOL mirrorEnabled;

/// 收到纯 `otp` 时是否弹系统通知（默认 YES；若刚展示过镜像则由 Presenter 抑制双弹）。
@property (nonatomic, assign) BOOL otpBannerEnabled;

@end

NS_ASSUME_NONNULL_END
