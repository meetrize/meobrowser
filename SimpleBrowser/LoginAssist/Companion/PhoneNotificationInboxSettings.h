#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 手机通知收件箱侧栏相关开关（UserDefaults）。与 `PhoneNotificationSettings.mirrorEnabled`（系统横幅）解耦。
@interface PhoneNotificationInboxSettings : NSObject

+ (instancetype)sharedSettings;

/// 是否将通知写入本地收件箱（默认 YES）。
@property (nonatomic, assign) BOOL inboxEnabled;

/// 是否将纯 `otp` 合成条目写入收件箱（默认 YES）。
@property (nonatomic, assign) BOOL otpToInbox;

/// 保留天数；`0` 表示永久（默认 7）。钉选条目豁免淘汰。
@property (nonatomic, assign) NSInteger retentionDays;

/// 侧栏可见行停留后自动已读（默认 YES）。NI-1b 使用。
@property (nonatomic, assign) BOOL autoMarkReadOnVisible;

/// 侧栏宽度（pt），默认 360；建议钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

@end

NS_ASSUME_NONNULL_END
