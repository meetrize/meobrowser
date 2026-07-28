#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ServerSyncAPIClient : NSObject

+ (instancetype)sharedClient;

- (void)postJSON:(NSString *)path
            body:(NSDictionary *)body
           token:(nullable NSString *)token
      completion:(void (^)(NSDictionary * _Nullable json, NSError * _Nullable error))completion;

- (void)patchJSON:(NSString *)path
             body:(NSDictionary *)body
            token:(NSString *)token
       completion:(void (^)(NSDictionary * _Nullable json, NSError * _Nullable error))completion;

- (void)getJSON:(NSString *)path
          token:(NSString *)token
     completion:(void (^)(NSDictionary * _Nullable json, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
