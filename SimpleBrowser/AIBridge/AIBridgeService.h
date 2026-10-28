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

/// Provider 期望域名（绑定匹配 / 智能找标签）
- (NSArray<NSString *> *)matchHostsForProviderId:(NSString *)providerId;
- (BOOL)host:(NSString *)host matchesProviderId:(NSString *)providerId;
/// 未打开标签时用于新建标签的首页
- (nullable NSURL *)homeURLForProviderId:(NSString *)providerId;

@end

NS_ASSUME_NONNULL_END
