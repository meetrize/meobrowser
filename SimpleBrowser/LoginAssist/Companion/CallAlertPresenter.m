#import "CallAlertPresenter.h"
#import "CallAlertSettings.h"
#import <UserNotifications/UserNotifications.h>
#import <AppKit/AppKit.h>
#import <os/log.h>

static NSString * const kCallAlertCategory = @"MEO_CALL_ALERT";

@implementation CallAlertPresenter

+ (instancetype)sharedPresenter {
    static CallAlertPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presenter = [[self alloc] init];
    });
    return presenter;
}

- (void)requestAuthorizationIfNeeded {
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "call alert auth error: %{public}@", error.localizedDescription);
            } else {
                os_log_info(OS_LOG_DEFAULT, "call alert auth granted=%{public}d", granted);
            }
        }];
    }
}

- (BOOL)presentFromPayload:(NSDictionary *)payload
               displayName:(NSString *)displayName
                 typeLabel:(NSString *)typeLabel {
    CallAlertSettings *settings = [CallAlertSettings sharedSettings];
    if (!settings.alertEnabled || !settings.systemNotificationEnabled) {
        return YES;
    }
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return YES;
    }

    [self requestAuthorizationIfNeeded];

    NSString *state = [self stringFrom:payload[@"state"]];
    NSString *callID = [self stringFrom:payload[@"id"]];
    NSString *number = [self stringFrom:payload[@"number"]];
    if (number.length == 0) {
        number = [self stringFrom:payload[@"numberRaw"]];
    }

    NSString *who = displayName.length > 0 ? displayName
        : (number.length > 0 ? number : @"未知号码");

    NSString *title = nil;
    NSString *body = typeLabel.length > 0 ? typeLabel : @"";
    if ([state isEqualToString:@"ringing"]) {
        title = [NSString stringWithFormat:@"来电 · %@", who];
    } else if ([state isEqualToString:@"active"]) {
        title = [NSString stringWithFormat:@"通话中 · %@", who];
    } else if ([state isEqualToString:@"missed"]) {
        title = [NSString stringWithFormat:@"未接来电 · %@", who];
    } else {
        title = [NSString stringWithFormat:@"通话结束 · %@", who];
    }

    os_log_info(OS_LOG_DEFAULT,
                "call alert present state=%{public}@ numberLen=%lu",
                state,
                (unsigned long)number.length);

    if (@available(macOS 10.14, *)) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = body.length > 0 ? body : @"来自手机 Companion";
        content.sound = [state isEqualToString:@"ringing"] ? [UNNotificationSound defaultSound] : nil;
        content.categoryIdentifier = kCallAlertCategory;
        content.threadIdentifier = @"meo-call-alert";

        NSString *identifier = callID.length > 0
            ? [NSString stringWithFormat:@"call-alert-%@", callID]
            : [NSString stringWithFormat:@"call-alert-%f", [NSDate date].timeIntervalSince1970];
        if (identifier.length > 180) {
            identifier = [identifier substringToIndex:180];
        }

        if ([state isEqualToString:@"ended"] || [state isEqualToString:@"missed"]) {
            // 更新为结束态后短时保留；同 id 覆盖
        }

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:^(NSError * _Nullable error) {
                 if (error) {
                     os_log_error(OS_LOG_DEFAULT, "call alert deliver failed: %{public}@",
                                  error.localizedDescription);
                 }
             }];
    }
    return YES;
}

- (void)removeNotificationForCallID:(NSString *)callID {
    if (callID.length == 0) return;
    if (@available(macOS 10.14, *)) {
        NSString *identifier = [NSString stringWithFormat:@"call-alert-%@", callID];
        if (identifier.length > 180) {
            identifier = [identifier substringToIndex:180];
        }
        [[UNUserNotificationCenter currentNotificationCenter]
            removeDeliveredNotificationsWithIdentifiers:@[identifier]];
    }
}

- (NSString *)stringFrom:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

@end
