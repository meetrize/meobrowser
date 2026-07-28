#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const CloudSyncSettingsDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const CloudSyncEngineStateDidChangeNotification;

FOUNDATION_EXPORT NSString * const CloudSyncContainerIdentifier;

@interface CloudSyncSettings : NSObject

+ (instancetype)sharedSettings;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL shortcutEnabled;
@property (nonatomic, assign) BOOL formMemoEnabled;
@property (nonatomic, assign) NSTimeInterval lastSyncAt;
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
/// 是否已对「首次打开总开关」应用过分项默认值。
@property (nonatomic, assign) BOOL didApplyDefaultKinds;

- (void)enableWithDefaultKindsIfNeeded;

@end

NS_ASSUME_NONNULL_END
