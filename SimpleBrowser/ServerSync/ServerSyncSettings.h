#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const ServerSyncSettingsDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ServerSyncEngineStateDidChangeNotification;
FOUNDATION_EXPORT NSString * const ServerSyncAppId;

/// 云同步方向（与「启用哪些数据类型」正交）。
typedef NS_ENUM(NSInteger, ServerSyncDirection) {
    /// 拉取云端 → 与本地 LWW 合并 → 写回本地并上传胜出记录
    ServerSyncDirectionBidirectional = 0,
    /// 只把本地推到云端（不改本地）
    ServerSyncDirectionUploadOnly = 1,
    /// 只把云端合并进本地（不上传）
    ServerSyncDirectionDownloadOnly = 2,
};

@interface ServerSyncSettings : NSObject

+ (instancetype)sharedSettings;

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL shortcutEnabled;
@property (nonatomic, assign) BOOL formMemoEnabled;
/// 默认同向双向。
@property (nonatomic, assign) ServerSyncDirection syncDirection;
@property (nonatomic, assign) NSTimeInterval lastSyncAt;
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
@property (nonatomic, assign) BOOL didApplyDefaultKinds;
@property (nonatomic, copy, nullable) NSString *userId;

- (void)enableWithDefaultKindsIfNeeded;
- (nullable NSURL *)normalizedBaseURL;
+ (NSString *)displayNameForSyncDirection:(ServerSyncDirection)direction;

@end

NS_ASSUME_NONNULL_END
