#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 浏览 `_meocompanion._tcp`，向已配对手机发送短连接 `invite`。
@interface CompanionPhoneDiscovery : NSObject

/// 开始浏览；仅向 `allowedDeviceIds` 中的设备发 invite（空集合则不发）。
- (void)startWithAllowedDeviceIds:(NSSet<NSString *> *)allowedDeviceIds
                         hostName:(NSString *)hostName;

- (void)stop;

/// 立即对当前已发现且允许的设备再发一轮 invite（带冷却）。
- (void)inviteNow;

@property (nonatomic, assign, readonly, getter=isBrowsing) BOOL browsing;

@end

NS_ASSUME_NONNULL_END
