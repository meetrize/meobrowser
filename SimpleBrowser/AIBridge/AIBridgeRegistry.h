#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgeRegistryDidChangeNotification;

@interface AIBridgeBinding : NSObject
@property (nonatomic, copy) NSString *providerId;  // deepseek | kimi | iwencai | doubao | gemini | chatgpt | mock
@property (nonatomic, copy) NSString *modelId;     // bridge__deepseek 等
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, weak, nullable) BrowserTab *tab;
@property (nonatomic, copy, nullable) NSString *tabTitle;
@property (nonatomic, copy, nullable) NSString *pageURL;
@end

@interface AIBridgeRegistry : NSObject

@property (class, readonly, strong) AIBridgeRegistry *sharedRegistry;

/// providerId → binding（一 provider 一绑定）
- (NSArray<AIBridgeBinding *> *)allBindings;
- (nullable AIBridgeBinding *)bindingForModelId:(NSString *)modelId;
- (nullable AIBridgeBinding *)bindingForProviderId:(NSString *)providerId;

- (void)bindTab:(BrowserTab *)tab
     providerId:(NSString *)providerId
       modelId:(NSString *)modelId
   displayName:(NSString *)displayName
       pageURL:(nullable NSString *)pageURL;

- (void)unbindProviderId:(NSString *)providerId;
- (void)unbindTab:(BrowserTab *)tab;
- (void)unbindAll;

@end

NS_ASSUME_NONNULL_END
