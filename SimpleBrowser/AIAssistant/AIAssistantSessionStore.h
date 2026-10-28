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
- (void)setPinned:(BOOL)pinned forSessionId:(NSString *)sessionId;

/// 标题/预览模糊匹配（固定会话排前）
- (NSArray<AIAssistantSession *> *)sessionsMatchingQuery:(NSString *)query;

/// 按「已固定 / 今天 / 昨天 / 更早」分组；每组内固定优先再按更新时间
- (NSArray<NSDictionary *> *)groupedSessionsMatchingQuery:(NSString *)query;
/// 字典: @{ @"title": NSString, @"sessions": NSArray<AIAssistantSession *> }

- (void)touchAndPersist:(AIAssistantSession *)session;

@end

NS_ASSUME_NONNULL_END
