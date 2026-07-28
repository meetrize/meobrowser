#import "CloudSyncAccountObserver.h"
#import "CloudSyncSettings.h"
#import "CloudSyncCapability.h"
#import <CloudKit/CloudKit.h>

@interface CloudSyncAccountObserver ()
@property (nonatomic, assign, readwrite) CloudSyncAccountStatus status;
@property (nonatomic, copy, readwrite) NSString *statusMessage;
@end

@implementation CloudSyncAccountObserver

+ (instancetype)sharedObserver {
    static CloudSyncAccountObserver *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (@available(macOS 14.0, *)) {
            if ([CloudSyncCapability isCloudKitEntitled]) {
                _status = CloudSyncAccountStatusUnknown;
                _statusMessage = @"尚未检测 iCloud";
            } else {
                _status = CloudSyncAccountStatusCouldNotDetermine;
                _statusMessage = [CloudSyncCapability unavailableReason];
            }
        } else {
            _status = CloudSyncAccountStatusUnsupportedOS;
            _statusMessage = @"iCloud 同步需要 macOS 14 或更高版本";
        }
    }
    return self;
}

- (void)finishOnMainWithStatus:(CloudSyncAccountStatus)status
                       message:(NSString *)message
                    completion:(void (^)(CloudSyncAccountStatus, NSString *))completion {
    void (^apply)(void) = ^{
        self.status = status;
        self.statusMessage = message ?: @"";
        if (completion) {
            completion(status, self.statusMessage);
        }
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

- (void)refreshWithCompletion:(void (^)(CloudSyncAccountStatus, NSString *))completion {
    if (@available(macOS 14.0, *)) {
        if (![CloudSyncCapability isCloudKitEntitled]) {
            NSString *reason = [CloudSyncCapability unavailableReason];
            [self finishOnMainWithStatus:CloudSyncAccountStatusCouldNotDetermine message:reason completion:completion];
            return;
        }
        // 任何 CK API 在无 entitlement 时都可能 SIGTRAP；上面已拦住。
        CKContainer *container = [CKContainer containerWithIdentifier:CloudSyncContainerIdentifier];
        [container accountStatusWithCompletionHandler:^(CKAccountStatus accountStatus, NSError *error) {
            CloudSyncAccountStatus mapped = CloudSyncAccountStatusCouldNotDetermine;
            NSString *message = @"无法确定 iCloud 状态";
            if (error) {
                mapped = CloudSyncAccountStatusCouldNotDetermine;
                message = error.localizedDescription ?: message;
            } else {
                switch (accountStatus) {
                    case CKAccountStatusAvailable:
                        mapped = CloudSyncAccountStatusAvailable;
                        message = @"已连接 iCloud";
                        break;
                    case CKAccountStatusNoAccount:
                        mapped = CloudSyncAccountStatusNoAccount;
                        message = @"未登录 iCloud";
                        break;
                    case CKAccountStatusRestricted:
                        mapped = CloudSyncAccountStatusRestricted;
                        message = @"iCloud 受限，无法同步";
                        break;
                    case CKAccountStatusCouldNotDetermine:
                        mapped = CloudSyncAccountStatusCouldNotDetermine;
                        message = @"无法确定 iCloud 状态";
                        break;
                    case CKAccountStatusTemporarilyUnavailable:
                        mapped = CloudSyncAccountStatusTemporarilyUnavailable;
                        message = @"iCloud 暂时不可用";
                        break;
                    default:
                        break;
                }
            }
            [self finishOnMainWithStatus:mapped message:message completion:completion];
        }];
    } else {
        [self finishOnMainWithStatus:CloudSyncAccountStatusUnsupportedOS
                             message:@"iCloud 同步需要 macOS 14 或更高版本"
                          completion:completion];
    }
}

@end
