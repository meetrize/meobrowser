#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CloudSyncAccountStatus) {
    CloudSyncAccountStatusUnknown = 0,
    CloudSyncAccountStatusAvailable,
    CloudSyncAccountStatusNoAccount,
    CloudSyncAccountStatusRestricted,
    CloudSyncAccountStatusCouldNotDetermine,
    CloudSyncAccountStatusTemporarilyUnavailable,
    CloudSyncAccountStatusUnsupportedOS,
};

@interface CloudSyncAccountObserver : NSObject

+ (instancetype)sharedObserver;

@property (nonatomic, readonly) CloudSyncAccountStatus status;
@property (nonatomic, readonly, copy) NSString *statusMessage;

- (void)refreshWithCompletion:(void (^ _Nullable)(CloudSyncAccountStatus status, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END
