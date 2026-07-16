#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CaptchaHelperBridge : NSObject

/// App Bundle 内 helpers/captcha_helper.py；开发构建时回退到源码树。
+ (nullable NSURL *)helperScriptURL;

+ (BOOL)isHelperAvailable:(NSError * _Nullable * _Nullable)outError;

/// OCR：图片路径 → 识别文本。
+ (void)recognizeTextInImageAtPath:(NSString *)imagePath
                        completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

/// 算术：表达式 → 答案文本（也可走原生 MathCaptchaAdapter）。
+ (void)evaluateMathExpression:(NSString *)expression
                    completion:(void (^)(NSString * _Nullable answer, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
