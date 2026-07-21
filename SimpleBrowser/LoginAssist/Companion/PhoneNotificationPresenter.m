#import "PhoneNotificationPresenter.h"
#import "PhoneNotificationSettings.h"
#import <UserNotifications/UserNotifications.h>
#import <AppKit/AppKit.h>
#import <os/log.h>

NSNotificationName const PhoneNotificationInboxRevealItemNotification = @"PhoneNotificationInboxRevealItemNotification";
NSString * const PhoneNotificationInboxRevealItemIDKey = @"id";

static NSString * const kPhoneNotifCategory = @"MEO_PHONE_NOTIFICATION";
static NSString * const kPhoneNotifUserInfoItemID = @"meoInboxItemID";
static const NSTimeInterval kRecentMirrorSuppressOTPSeconds = 3.0;

@interface PhoneNotificationPresenter () <UNUserNotificationCenterDelegate>
@property (nonatomic, assign) BOOL didRequestAuthorization;
@property (nonatomic, assign) BOOL didInstallDelegate;
@property (nonatomic, assign) NSTimeInterval lastMirrorPresentedAt;
@property (nonatomic, copy, nullable) NSString *lastMirrorPackage;
@end

@implementation PhoneNotificationPresenter

+ (instancetype)sharedPresenter {
    static PhoneNotificationPresenter *presenter;
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
        _lastMirrorPresentedAt = 0;
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
    self.didInstallDelegate = YES;
    if (@available(macOS 10.14, *)) {
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
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
                os_log_error(OS_LOG_DEFAULT, "phone notif auth error: %{public}@", error.localizedDescription);
            } else {
                os_log_info(OS_LOG_DEFAULT, "phone notif auth granted=%{public}d", granted);
            }
        }];
    }
}

- (BOOL)presentFromPayload:(NSDictionary *)payload {
    if (![PhoneNotificationSettings sharedSettings].mirrorEnabled) {
        return YES; // 已处理（跳过展示）— 不标记 recent mirror，允许 OTP 横幅
    }
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return YES;
    }

    [self ensureAuthorizationIfNeeded];

    NSString *appLabel = [self stringFrom:payload[@"appLabel"]];
    NSString *packageName = [self stringFrom:payload[@"packageName"]];
    NSString *title = [self stringFrom:payload[@"title"]];
    NSString *body = [self stringFrom:payload[@"body"]];
    NSString *payloadId = [self stringFrom:payload[@"id"]];

    NSString *label = appLabel.length > 0 ? appLabel
        : (packageName.length > 0 ? packageName : @"手机通知");
    NSString *displayTitle = nil;
    if (title.length > 0 && ![title isEqualToString:label]) {
        displayTitle = [NSString stringWithFormat:@"%@ · %@", label, title];
    } else {
        displayTitle = label;
    }

    NSString *bodyText = body;
    if (bodyText.length == 0) {
        if (title.length > 0 && ![title isEqualToString:label]) {
            bodyText = title;
        }
    }
    if (bodyText.length == 0) {
        os_log_info(OS_LOG_DEFAULT, "phone notif skip empty body pkg=%{public}@", packageName);
        return YES;
    }

    NSTimeInterval ts = [payload[@"ts"] doubleValue];
    if (ts > 0) {
        NSTimeInterval age = fabs([NSDate date].timeIntervalSince1970 - ts);
        if (age > 300) {
            os_log_info(OS_LOG_DEFAULT, "phone notif stale ts age=%.0f still presenting pkg=%{public}@", age, packageName);
        }
    }

    os_log_info(OS_LOG_DEFAULT,
                "phone notif present pkg=%{public}@ titleLen=%lu bodyLen=%lu",
                packageName,
                (unsigned long)displayTitle.length,
                (unsigned long)bodyText.length);

    if (@available(macOS 10.14, *)) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = displayTitle;
        content.body = bodyText;
        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = kPhoneNotifCategory;
        if (packageName.length > 0) {
            content.threadIdentifier = packageName;
        }
        if (payloadId.length > 0) {
            content.userInfo = @{kPhoneNotifUserInfoItemID: payloadId};
        }

        NSString *identifier = payloadId.length > 0
            ? [NSString stringWithFormat:@"phone-notif-%@", payloadId]
            : [NSString stringWithFormat:@"phone-notif-%f", [NSDate date].timeIntervalSince1970];
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
                     os_log_error(OS_LOG_DEFAULT, "phone notif deliver failed: %{public}@", error.localizedDescription);
                 }
             }];
        // 仅在真正尝试展示后抑制紧随其后的 OTP 横幅
        self.lastMirrorPresentedAt = [NSDate date].timeIntervalSince1970;
        self.lastMirrorPackage = packageName;
    }

    return YES;
}

- (void)presentOTPBannerIfNeededWithCode:(NSString *)code {
    if (code.length == 0) {
        return;
    }
    if (![PhoneNotificationSettings sharedSettings].otpBannerEnabled) {
        return;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.lastMirrorPresentedAt > 0 &&
        (now - self.lastMirrorPresentedAt) < kRecentMirrorSuppressOTPSeconds) {
        os_log_info(OS_LOG_DEFAULT, "otp banner suppressed (recent mirror)");
        return;
    }

    [self ensureAuthorizationIfNeeded];

    if (@available(macOS 10.14, *)) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = @"验证码";
        content.body = code;
        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = kPhoneNotifCategory;
        content.threadIdentifier = @"otp";
        // OTP 收件箱 id 含时间桶，点击时用 code 键让侧栏尽力匹配
        content.userInfo = @{kPhoneNotifUserInfoItemID: [NSString stringWithFormat:@"otp-code:%@", code]};

        NSString *identifier = [NSString stringWithFormat:@"otp-banner-%@-%.0f", code, now];
        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:^(NSError * _Nullable error) {
                 if (error) {
                     os_log_error(OS_LOG_DEFAULT, "otp banner deliver failed: %{public}@", error.localizedDescription);
                 }
             }];
    }
}

- (nullable NSString *)stringFrom:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
API_AVAILABLE(macos(10.14)) {
    (void)center;
    (void)notification;
    // 前台也弹横幅，否则用户盯着浏览器时看不到镜像
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
    [NSApp activateIgnoringOtherApps:YES];

    NSString *itemID = nil;
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    id raw = userInfo[kPhoneNotifUserInfoItemID];
    if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] > 0) {
        itemID = (NSString *)raw;
    } else {
        NSString *reqID = response.notification.request.identifier;
        if ([reqID hasPrefix:@"phone-notif-"]) {
            itemID = [reqID substringFromIndex:@"phone-notif-".length];
        }
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (itemID.length > 0) {
        info[PhoneNotificationInboxRevealItemIDKey] = itemID;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PhoneNotificationInboxRevealItemNotification
                                                        object:self
                                                      userInfo:info];

    if (completionHandler) {
        completionHandler();
    }
}

@end
