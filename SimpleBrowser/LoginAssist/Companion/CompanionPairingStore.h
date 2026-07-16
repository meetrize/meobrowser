#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CompanionPairedDevice : NSObject
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *deviceToken;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, assign) NSTimeInterval pairedAt;
@end

/// Companion 配对状态（Keychain + UserDefaults 元数据）。
@interface CompanionPairingStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, copy, readonly, nullable) NSString *pendingPairingCode;
@property (nonatomic, assign, readonly) NSTimeInterval pendingPairingExpiresAt;
@property (nonatomic, copy, readonly) NSArray<CompanionPairedDevice *> *pairedDevices;

/// 生成或刷新 6 位配对码（默认 5 分钟有效）。
- (NSString *)refreshPendingPairingCode;

- (BOOL)isPendingPairingCodeValid:(NSString *)code;
- (nullable NSString *)issueDeviceTokenForDeviceId:(NSString *)deviceId
                                      pairingCode:(NSString *)pairingCode
                                            error:(NSError * _Nullable * _Nullable)error;
- (BOOL)validateDeviceToken:(NSString *)deviceToken deviceId:(nullable NSString *)deviceId;
- (void)revokeAllDevices;
- (void)revokeDeviceToken:(NSString *)deviceToken;

@end

NS_ASSUME_NONNULL_END
