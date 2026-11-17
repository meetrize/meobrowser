#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgeRegistryDidChangeNotification;

@interface AIBridgeBinding : NSObject
/// 主键
@property (nonatomic, copy) NSString *bindingId;
@property (nonatomic, copy) NSString *providerId;  // deepseek | kimi | …
/// 固定名 bridge__deepseek（按 provider，不含随机后缀）
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, weak, nullable) BrowserTab *tab;
@property (nonatomic, copy, nullable) NSString *tabTitle;
@property (nonatomic, copy, nullable) NSString *pageURL;
@property (nonatomic, copy, nullable) NSString *sessionId;
@property (nonatomic, assign) NSTimeInterval createdAt;
@end

@interface AIBridgeRegistry : NSObject

@property (class, readonly, strong) AIBridgeRegistry *sharedRegistry;

- (NSArray<AIBridgeBinding *> *)allBindings;
- (NSArray<AIBridgeBinding *> *)bindingsForProviderId:(NSString *)providerId;

- (nullable AIBridgeBinding *)bindingForId:(NSString *)bindingId;
/// 匹配固定 modelId（bridge__provider）；兼容旧长格式 bridge__provider__short → 按 provider 取最新
- (nullable AIBridgeBinding *)bindingForModelId:(NSString *)modelId;
/// 该平台「最新」一条（可能为 nil）
- (nullable AIBridgeBinding *)bindingForProviderId:(NSString *)providerId;

/// 新建 binding；同 tab / 同 provider 的旧绑定会被移除（固定 modelId 每平台一条）。
- (AIBridgeBinding *)bindTab:(BrowserTab *)tab
                  providerId:(NSString *)providerId
                 displayName:(NSString *)displayName
                     pageURL:(nullable NSString *)pageURL
                   sessionId:(nullable NSString *)sessionId;

- (void)unbindBindingId:(NSString *)bindingId;
/// 解绑该平台下全部实例
- (void)unbindProviderId:(NSString *)providerId;
- (void)unbindTab:(BrowserTab *)tab;
- (void)unbindAll;

+ (NSString *)shortIdFromBindingId:(NSString *)bindingId;
/// 固定 modelId：bridge__<provider>（bindingId 仅兼容旧调用，忽略）
+ (NSString *)modelIdForProviderId:(NSString *)providerId bindingId:(nullable NSString *)bindingId;
/// 解析 bridge__provider 或 bridge__provider__short → provider；失败返回 nil
+ (nullable NSString *)providerIdFromModelId:(NSString *)modelId;

@end

NS_ASSUME_NONNULL_END
