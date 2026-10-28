#import <Foundation/Foundation.h>

@class BrowserTab;
@class AIBridgeBinding;

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

/// 新建 binding（多实例）。成功时 *outBinding 非空。
- (nullable AIBridgeBinding *)bindCurrentTab:(BrowserTab *)tab
                                     pageURL:(nullable NSURL *)url
                                  providerId:(NSString *)providerId
                                   sessionId:(nullable NSString *)sessionId
                                       error:(NSError *_Nullable *_Nullable)error;

- (void)unbindBindingId:(NSString *)bindingId;
- (void)unbindProviderId:(NSString *)providerId;
- (void)unbindAllProviders;

- (void)cancelAllJobs;
- (void)newChatForProviderId:(NSString *)providerId completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;
- (void)newChatForBindingId:(NSString *)bindingId completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;

/// 解析 model；多短名绑定时返回 nil 且 error 说明 ambiguous
- (nullable AIBridgeBinding *)resolveBindingForModelId:(NSString *)modelId
                                                 error:(NSError *_Nullable *_Nullable)error;

- (NSString *)baseURLString;
- (NSString *)curlExampleForModel:(NSString *)modelId;

/// Provider 期望域名（绑定匹配 / 智能找标签）
- (NSArray<NSString *> *)matchHostsForProviderId:(NSString *)providerId;
- (BOOL)host:(NSString *)host matchesProviderId:(NSString *)providerId;
/// 未打开标签时用于新建标签的首页
- (nullable NSURL *)homeURLForProviderId:(NSString *)providerId;

@end

NS_ASSUME_NONNULL_END
