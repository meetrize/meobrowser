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

/// 本机局域网 IPv4（优先 en0/en1 Wi‑Fi），不含端口。
- (NSArray<NSString *> *)localLANIPv4Addresses;
/// 首选 `IP:端口`，无端口时仅 IP；都没有则 nil。
- (nullable NSString *)preferredLANEndpoint;

@end

NS_ASSUME_NONNULL_END
