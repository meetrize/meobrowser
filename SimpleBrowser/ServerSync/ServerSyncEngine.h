#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ServerSyncEngineState) {
    ServerSyncEngineStateIdle = 0,
    ServerSyncEngineStateSyncing,
    ServerSyncEngineStateUnavailable,
    ServerSyncEngineStateError,
};

@interface ServerSyncEngine : NSObject

+ (instancetype)sharedEngine;

@property (nonatomic, readonly) ServerSyncEngineState state;
@property (nonatomic, readonly, copy) NSString *statusText;

- (void)startIfNeeded;
- (void)stop;
- (void)syncNow;

@end

NS_ASSUME_NONNULL_END
