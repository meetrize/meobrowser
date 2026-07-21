#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 来电提醒开关（UserDefaults）。总开关默认关。
@interface CallAlertSettings : NSObject

+ (instancetype)sharedSettings;

/// 是否处理 `call_event`（默认 NO）。
@property (nonatomic, assign) BOOL alertEnabled;

/// 是否显示浏览器内跨窗横幅（默认 YES；受 alertEnabled 门控）。
@property (nonatomic, assign) BOOL bannerEnabled;

/// 是否弹系统通知（默认 YES；受 alertEnabled 门控）。
@property (nonatomic, assign) BOOL systemNotificationEnabled;

@end

NS_ASSUME_NONNULL_END
