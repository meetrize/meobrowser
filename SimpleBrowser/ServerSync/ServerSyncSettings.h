#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const ServerSyncSettingsDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ServerSyncEngineStateDidChangeNotification;
FOUNDATION_EXPORT NSString * const ServerSyncAppId;

@interface ServerSyncSettings : NSObject

+ (instancetype)sharedSettings;

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL shortcutEnabled;
@property (nonatomic, assign) BOOL formMemoEnabled;
@property (nonatomic, assign) NSTimeInterval lastSyncAt;
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
@property (nonatomic, assign) BOOL didApplyDefaultKinds;
@property (nonatomic, copy, nullable) NSString *userId;

- (void)enableWithDefaultKindsIfNeeded;
- (nullable NSURL *)normalizedBaseURL;

@end

NS_ASSUME_NONNULL_END
