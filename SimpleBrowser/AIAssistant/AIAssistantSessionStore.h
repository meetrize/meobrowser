#import <Foundation/Foundation.h>
#import "AIAssistantSession.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIAssistantSessionStoreDidChangeNotification;

@interface AIAssistantSessionStore : NSObject

@property (class, readonly, strong) AIAssistantSessionStore *sharedStore;

@property (nonatomic, copy, nullable) NSString *currentSessionId;

- (NSArray<AIAssistantSession *> *)allSessionsSorted;
- (nullable AIAssistantSession *)sessionForId:(NSString *)sessionId;
- (nullable AIAssistantSession *)currentSession;

- (AIAssistantSession *)createSessionWithProviderId:(NSString *)providerId
                                          bindingId:(nullable NSString *)bindingId
                                            modelId:(nullable NSString *)modelId
                                              title:(nullable NSString *)title;

- (void)saveSession:(AIAssistantSession *)session;
- (void)deleteSessionId:(NSString *)sessionId;
- (void)deleteAllSessions;
- (void)setCurrentSessionId:(nullable NSString *)currentSessionId;

/// 标题/预览模糊匹配
- (NSArray<AIAssistantSession *> *)sessionsMatchingQuery:(NSString *)query;

- (void)touchAndPersist:(AIAssistantSession *)session;

@end

NS_ASSUME_NONNULL_END
