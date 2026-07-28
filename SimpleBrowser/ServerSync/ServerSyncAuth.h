#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ServerSyncAuth : NSObject

+ (instancetype)sharedAuth;

@property (nonatomic, readonly, getter=isLoggedIn) BOOL loggedIn;

- (void)registerWithEmail:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(NSError * _Nullable error))completion;

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^)(NSError * _Nullable error))completion;

- (void)logout;

@end

NS_ASSUME_NONNULL_END
