#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompanionChannelState) {
    CompanionChannelStateStopped = 0,
    CompanionChannelStateAdvertising,
    CompanionChannelStateConnected,
};

extern NSNotificationName const CompanionChannelStateDidChangeNotification;

/// Bonjour 收码通道：hello 配对 → otp → OTPInbox。
@interface CompanionChannel : NSObject

@property (nonatomic, assign, readonly) CompanionChannelState state;
@property (nonatomic, copy, readonly, nullable) NSString *statusText;
@property (nonatomic, assign, readonly) NSInteger listeningPort;
@property (nonatomic, copy, readonly, nullable) NSString *lastConnectedDeviceId;

+ (instancetype)sharedChannel;

- (void)start;
- (void)stop;

/// 确保有可用配对码；已配对时不会自动刷新。
- (NSString *)ensurePairingCode;
/// 用户主动刷新配对码（新设备配对）。
- (NSString *)refreshPairingCodeForNewDevice;

@end

NS_ASSUME_NONNULL_END
