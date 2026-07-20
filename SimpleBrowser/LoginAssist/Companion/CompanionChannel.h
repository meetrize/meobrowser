#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompanionChannelState) {
    CompanionChannelStateStopped = 0,
    CompanionChannelStateAdvertising,
    CompanionChannelStateConnected,
};

extern NSNotificationName const CompanionChannelStateDidChangeNotification;

/// Bonjour 收码通道：hello 配对 → otp / phone_notification → OTPInbox / 系统通知。
@interface CompanionChannel : NSObject

@property (nonatomic, assign, readonly) CompanionChannelState state;
@property (nonatomic, copy, readonly, nullable) NSString *statusText;
@property (nonatomic, assign, readonly) NSInteger listeningPort;
@property (nonatomic, copy, readonly, nullable) NSString *lastConnectedDeviceId;
/// 首选端口被占用时临时落到其他端口，此时为 YES（需用户确认是否更换固定端口）。
@property (nonatomic, assign, readonly) BOOL usingTemporaryPort;

+ (instancetype)sharedChannel;

- (void)start;
- (void)stop;

/// 停止后按 sticky 端口重新启动；若 clearSticky=YES 则先清 sticky，由系统重新分配并写入 sticky。
- (void)restartListeningClearingStickyPort:(BOOL)clearSticky;

/// 确保有可用配对码；已配对时不会自动刷新。安全码模式下返回固定安全码。
- (NSString *)ensurePairingCode;
/// 用户主动刷新配对码（新设备配对）。安全码模式下无效，返回当前安全码。
- (NSString *)refreshPairingCodeForNewDevice;

/// 本机局域网 IPv4（优先 en0/en1 Wi‑Fi），不含端口。
- (NSArray<NSString *> *)localLANIPv4Addresses;
/// 首选 `IP:端口`，无端口时仅 IP；都没有则 nil。
- (nullable NSString *)preferredLANEndpoint;

@end

NS_ASSUME_NONNULL_END
