#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgePreferencesDidChangeNotification;

@interface AIBridgePreferences : NSObject

@property (class, readonly, strong) AIBridgePreferences *sharedPreferences;

@property (nonatomic, assign) NSInteger port; // default 3921
@property (nonatomic, copy) NSString *bearerToken;
@property (nonatomic, assign, getter=isServerEnabled) BOOL serverEnabled; // UI intent; actual listen via Service

- (void)ensureToken;
- (void)regenerateToken;

@end

NS_ASSUME_NONNULL_END
