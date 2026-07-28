#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CloudSyncEngineState) {
    CloudSyncEngineStateIdle = 0,
    CloudSyncEngineStateSyncing,
    CloudSyncEngineStateUnavailable,
    CloudSyncEngineStateError,
};

@interface CloudSyncEngine : NSObject

+ (instancetype)sharedEngine;

@property (nonatomic, readonly) CloudSyncEngineState state;
@property (nonatomic, readonly, copy) NSString *statusText;

- (void)startIfNeeded;
- (void)stop;
- (void)syncNow;
- (void)deleteCloudDataWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;
- (void)refreshAccountStatus;

@end

NS_ASSUME_NONNULL_END
