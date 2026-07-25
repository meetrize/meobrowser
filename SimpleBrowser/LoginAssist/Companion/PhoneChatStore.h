#import <Foundation/Foundation.h>
#import "PhoneChatModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PhoneChatStoreDidChangeNotification;
extern NSString * const PhoneChatStoreThreadIDKey;
extern NSString * const PhoneChatStoreWeChatPackageName;

/// 微信（及可扩展）通知衍生会话库：线程 + 消息落盘。
@interface PhoneChatStore : NSObject

+ (instancetype)sharedStore;

+ (NSString *)normalizeTitle:(NSString *)raw;
+ (NSString *)threadIDForPackageName:(NSString *)packageName title:(NSString *)title;

- (PhoneChatThread *)ensureThreadForPackageName:(NSString *)packageName title:(NSString *)title;

/// 微信入站：正文相对上次入站有变化才追加。返回是否追加。
- (BOOL)appendInboundIfNeededForPackageName:(NSString *)packageName
                                      title:(NSString *)title
                                       body:(NSString *)body
                             notificationID:(nullable NSString *)notificationID
                                 postTimeMs:(long long)postTimeMs;

- (PhoneChatMessage *)beginOutboundMessageForThreadID:(NSString *)threadID
                                                 text:(NSString *)text
                                            requestID:(NSString *)requestID;

- (void)markOutboundSentForRequestID:(NSString *)requestID;
- (void)markOutboundFailedForRequestID:(NSString *)requestID;

- (nullable PhoneChatThread *)threadForID:(NSString *)threadID;
- (nullable PhoneChatThread *)threadForPackageName:(NSString *)packageName title:(NSString *)title;
- (NSArray<PhoneChatMessage *> *)messagesForThreadID:(NSString *)threadID;
- (void)markThreadRead:(NSString *)threadID;

@end

NS_ASSUME_NONNULL_END
