#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CallAlertPresenter : NSObject

+ (instancetype)sharedPresenter;

- (void)requestAuthorizationIfNeeded;

/// 处理 call_event；返回 YES 表示已处理（含跳过）。
- (BOOL)presentFromPayload:(NSDictionary *)payload
               displayName:(nullable NSString *)displayName
               typeLabel:(nullable NSString *)typeLabel;

- (void)removeNotificationForCallID:(NSString *)callID;

@end

NS_ASSUME_NONNULL_END
