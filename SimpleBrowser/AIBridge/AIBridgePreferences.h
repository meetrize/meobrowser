#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIBridgePreferencesDidChangeNotification;

@interface AIBridgePreferences : NSObject

@property (class, readonly, strong) AIBridgePreferences *sharedPreferences;

@property (nonatomic, assign) NSInteger port; // default 3921
@property (nonatomic, copy) NSString *bearerToken;
@property (nonatomic, assign, getter=isServerEnabled) BOOL serverEnabled; // UI intent; actual listen via Service

/// Ollama OpenAI-compatible base，默认 http://127.0.0.1:11434/v1
@property (nonatomic, copy) NSString *ollamaBaseURL;
/// 任意 OpenAI 兼容上游 base（含 /v1），默认空
@property (nonatomic, copy) NSString *openaiBaseURL;
@property (nonatomic, copy) NSString *openaiApiKey;

- (void)ensureToken;
- (void)regenerateToken;

@end

NS_ASSUME_NONNULL_END
