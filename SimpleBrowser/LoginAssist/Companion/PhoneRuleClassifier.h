#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhoneRuleClassifyResult : NSObject
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *label;
@end

/// 轻量号码类型规则（simple_rules.json），无大型号段库。
@interface PhoneRuleClassifier : NSObject

+ (instancetype)sharedClassifier;

- (PhoneRuleClassifyResult *)classifyNumber:(nullable NSString *)number
                              presentation:(nullable NSString *)presentation;

/// 归一化为国内数字串（去 +86）。
+ (NSString *)normalizedDigits:(nullable NSString *)raw;

@end

NS_ASSUME_NONNULL_END
