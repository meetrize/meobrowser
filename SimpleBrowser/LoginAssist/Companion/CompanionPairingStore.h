#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompanionAuthMode) {
    /// 临时 6 位配对码（5 分钟、一次性）
    CompanionAuthModePairingCode = 0,
    /// 用户自设固定安全码（可重复使用，适合日常自动连接）
    CompanionAuthModeSecurityCode = 1,
};

@interface CompanionPairedDevice : NSObject
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *deviceToken;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, assign) NSTimeInterval pairedAt;
@end

/// Companion 配对状态（Keychain + UserDefaults 元数据）。
@interface CompanionPairingStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, assign) CompanionAuthMode authMode;
@property (nonatomic, copy, readonly, nullable) NSString *pendingPairingCode;
@property (nonatomic, assign, readonly) NSTimeInterval pendingPairingExpiresAt;
@property (nonatomic, copy, readonly, nullable) NSString *securityCode;
@property (nonatomic, assign) NSInteger stickyListeningPort;
@property (nonatomic, copy, readonly) NSArray<CompanionPairedDevice *> *pairedDevices;

/// 已配对数量提示（仅 UserDefaults，不触发钥匙串读取；供启动态文案使用）。
@property (nonatomic, assign, readonly) NSUInteger pairedDeviceCountHint;

/// 生成或刷新 6 位配对码（默认 5 分钟有效）。
- (NSString *)refreshPendingPairingCode;

- (BOOL)isPendingPairingCodeValid:(NSString *)code;

/// 设置固定安全码（4～12 位数字/字母）。空字符串视为清除。
- (BOOL)setSecurityCode:(NSString *)code error:(NSError * _Nullable * _Nullable)error;
- (BOOL)isSecurityCodeValid:(NSString *)code;

/// 用配对码或安全码签发长期 deviceToken。安全码模式下成功后不清除安全码。
- (nullable NSString *)issueDeviceTokenForDeviceId:(NSString *)deviceId
                                      pairingCode:(NSString *)pairingCode
                                            error:(NSError * _Nullable * _Nullable)error;
- (BOOL)validateDeviceToken:(NSString *)deviceToken deviceId:(nullable NSString *)deviceId;
- (void)revokeAllDevices;
- (void)revokeDeviceToken:(NSString *)deviceToken;

@end

NS_ASSUME_NONNULL_END
