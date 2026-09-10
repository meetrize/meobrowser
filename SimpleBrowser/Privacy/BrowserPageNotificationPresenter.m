#import "BrowserPageNotificationPresenter.h"
#import "MeoApplication.h"
#import <UserNotifications/UserNotifications.h>
#import <AppKit/AppKit.h>
#import <os/log.h>

static NSString * const kPageNotifCategory = @"MEO_PAGE_NOTIFICATION";

@interface BrowserPageNotificationPresenter () <UNUserNotificationCenterDelegate>
@property (nonatomic, assign) BOOL didRequestAuthorization;
@property (nonatomic, assign) BOOL didInstallDelegate;
@end

@implementation BrowserPageNotificationPresenter

+ (instancetype)sharedPresenter {
    static BrowserPageNotificationPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presenter = [[self alloc] init];
    });
    return presenter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _didRequestAuthorization = NO;
        _didInstallDelegate = NO;
    }
    return self;
}

- (void)requestAuthorizationIfNeeded {
    [self ensureAuthorizationIfNeeded];
}

- (void)installDelegateIfNeeded {
    if (self.didInstallDelegate) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        // 若手机镜像 Presenter 已占用 delegate，其 willPresent 已覆盖任意 category，勿抢占。
        if (center.delegate != nil) {
            return;
        }
        self.didInstallDelegate = YES;
        center.delegate = self;
    }
}

- (void)ensureAuthorizationIfNeeded {
    [self installDelegateIfNeeded];
    if (self.didRequestAuthorization) {
        return;
    }
    self.didRequestAuthorization = YES;
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "page notif auth error: %{public}@", error.localizedDescription);
            } else {
                os_log_info(OS_LOG_DEFAULT, "page notif auth granted=%{public}d", granted);
            }
        }];
    }
}

- (void)presentWithTitle:(NSString *)title
                    body:(NSString *)body
                     tag:(NSString *)tag
                    host:(NSString *)host {
    NSString *safeTitle = title.length > 0 ? title : @"通知";
    NSString *safeBody = body ?: @"";
    if (safeBody.length == 0) {
        return;
    }
    NSString *safeTag = tag.length > 0 ? tag : @"default";
    NSString *safeHost = host.length > 0 ? host : @"unknown";

    [self ensureAuthorizationIfNeeded];

    os_log_info(OS_LOG_DEFAULT,
                "page notif present host=%{public}@ tag=%{public}@ titleLen=%lu bodyLen=%lu",
                safeHost,
                safeTag,
                (unsigned long)safeTitle.length,
                (unsigned long)safeBody.length);

    if (@available(macOS 10.14, *)) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = safeTitle;
        content.body = safeBody;
        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = kPageNotifCategory;
        content.threadIdentifier = safeHost;

        NSString *identifier = [NSString stringWithFormat:@"page-notify-%@-%@", safeHost, safeTag];
        if (identifier.length > 180) {
            identifier = [identifier substringToIndex:180];
        }

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:^(NSError * _Nullable error) {
                 if (error) {
                     os_log_error(OS_LOG_DEFAULT, "page notif deliver failed: %{public}@", error.localizedDescription);
                 }
             }];
    }
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
API_AVAILABLE(macos(10.14)) {
    (void)center;
    (void)notification;
    if (@available(macOS 11.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound |
                          UNNotificationPresentationOptionList);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
#pragma clang diagnostic pop
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler
API_AVAILABLE(macos(10.14)) {
    (void)center;
    (void)response;
    // 仅激活前台窗口；不打开 Companion 收件箱。
    [MeoApplication activateFrontWindowOnlyPreferring:NSApp.keyWindow];
    if (completionHandler) {
        completionHandler();
    }
}

@end
