#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CaptchaActorCompletion)(BOOL success, NSError * _Nullable error);

@interface CaptchaActor : NSObject

+ (void)fillText:(NSString *)text
    inputSelector:(NSString *)inputSelector
        inWebView:(WKWebView *)webView
       completion:(CaptchaActorCompletion)completion;

/// 读取输入框当前值，用于 Verify。
+ (void)readValueForSelector:(NSString *)selector
                   inWebView:(WKWebView *)webView
                  completion:(void (^)(NSString * _Nullable value, NSError * _Nullable error))completion;

/// 从页面提取算术题文本或 OCR 图片 data URL。
+ (void)extractMathTextNearSelector:(nullable NSString *)containerSelector
                          inWebView:(WKWebView *)webView
                         completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

+ (void)exportImageDataURLForSelector:(NSString *)imageSelector
                            inWebView:(WKWebView *)webView
                           completion:(void (^)(NSString * _Nullable dataURL, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
