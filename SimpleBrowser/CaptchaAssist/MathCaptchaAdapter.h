#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MathCaptchaAdapter : NSObject

/// 解析「3 + 5 = ?」类表达式，返回答案字符串；失败返回 nil。
+ (nullable NSString *)solveMathText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
