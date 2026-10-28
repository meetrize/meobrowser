#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgeRegistryDidChangeNotification;

@interface AIBridgeBinding : NSObject
/// 主键
@property (nonatomic, copy) NSString *bindingId;
@property (nonatomic, copy) NSString *providerId;  // deepseek | kimi | …
/// bridge__deepseek__a1b2c3
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
/// 精确匹配长 modelId；短名 bridge__provider 仅当该平台恰好 1 条时命中
- (nullable AIBridgeBinding *)bindingForModelId:(NSString *)modelId;
/// 兼容：该平台「最新」一条（可能为 nil）
- (nullable AIBridgeBinding *)bindingForProviderId:(NSString *)providerId;

/// 始终新建 binding；同 tab 的旧绑定会被移除。返回新建对象。
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
+ (NSString *)modelIdForProviderId:(NSString *)providerId bindingId:(NSString *)bindingId;
/// 解析 bridge__provider 或 bridge__provider__short → provider；失败返回 nil
+ (nullable NSString *)providerIdFromModelId:(NSString *)modelId;

@end

NS_ASSUME_NONNULL_END
