#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 将受信任网页的通知请求转为 macOS 系统通知（与手机镜像解耦）。
@interface BrowserPageNotificationPresenter : NSObject

+ (instancetype)sharedPresenter;

/// 打开系统「通知」设置（便于用户手动允许 MeoBrowser）。
+ (void)openSystemNotificationSettings;

/// 申请系统通知权限（可重复调用，内部只真正请求一次）。
- (void)requestAuthorizationIfNeeded;

/// 查询 / 申请系统通知权限；若已拒绝则自动打开系统通知设置。
- (void)ensureAuthorizationWithCompletion:(void (^)(BOOL granted))completion;

/// 展示网页通知。identifier 为 `page-notify-{host}-{tag}`（截断 ≤180）。
- (void)presentWithTitle:(NSString *)title
                    body:(NSString *)body
                     tag:(NSString *)tag
                    host:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
