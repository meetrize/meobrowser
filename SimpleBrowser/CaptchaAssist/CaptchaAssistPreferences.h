#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CaptchaAssistPreferences : NSObject

+ (BOOL)assistEnabled;
+ (void)setAssistEnabled:(BOOL)enabled;

/// 保留最近会话数，默认 20。
+ (NSInteger)maxSessionCount;
+ (void)setMaxSessionCount:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
