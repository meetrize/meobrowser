#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgeServiceStateDidChangeNotification;

@interface AIBridgeRequestLogEntry : NSObject
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSTimeInterval durationSec;
@property (nonatomic, copy, nullable) NSString *detail;
@end

@interface AIBridgeService : NSObject

@property (class, readonly, strong) AIBridgeService *sharedService;

@property (nonatomic, assign, readonly, getter=isListening) BOOL listening;
@property (nonatomic, assign, readonly) NSInteger listeningPort;
@property (nonatomic, copy, readonly) NSArray<AIBridgeRequestLogEntry *> *recentRequests;
@property (nonatomic, copy, readonly) NSString *statusText;

- (BOOL)startServer:(NSError *_Nullable *_Nullable)error;
- (void)stopServer;

- (void)bindCurrentTab:(BrowserTab *)tab
             pageURL:(nullable NSURL *)url
          providerId:(NSString *)providerId
               error:(NSError *_Nullable *_Nullable)error;
- (void)unbindProviderId:(NSString *)providerId;
- (void)unbindAllProviders;

- (void)cancelAllJobs;
- (void)newChatForProviderId:(NSString *)providerId completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;

- (NSString *)baseURLString;
- (NSString *)curlExampleForModel:(NSString *)modelId;

@end

NS_ASSUME_NONNULL_END
