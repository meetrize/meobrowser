#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserSitePermissionDecision) {
    BrowserSitePermissionDecisionUnknown = 0,
    BrowserSitePermissionDecisionAllow,
    BrowserSitePermissionDecisionDeny,
};

/// 按 host 存储网站权限决策（UserDefaults JSON）。
@interface BrowserSitePermissionStore : NSObject

+ (instancetype)sharedStore;

+ (nullable NSString *)normalizedHostFromString:(nullable NSString *)host;

- (BrowserSitePermissionDecision)geolocationDecisionForHost:(NSString *)host;
- (void)setGeolocationDecision:(BrowserSitePermissionDecision)decision forHost:(NSString *)host;
- (void)removeGeolocationDecisionForHost:(NSString *)host;
- (void)removeAllGeolocationDecisions;

@end

NS_ASSUME_NONNULL_END
