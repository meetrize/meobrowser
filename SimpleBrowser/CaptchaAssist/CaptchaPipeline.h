#import <WebKit/WebKit.h>
#import "CaptchaDetection.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^CaptchaPipelineCompletion)(BOOL success, NSString * _Nullable message, NSError * _Nullable error);

@interface CaptchaPipeline : NSObject

/// 从检测列表中选取可 CA-1 求解的项（math / text_ocr）。
+ (nullable CaptchaDetection *)preferredSolvableDetectionFrom:(NSArray<CaptchaDetection *> *)detections;

+ (BOOL)isSolvableKind:(NSString *)kind;

+ (void)solveDetection:(CaptchaDetection *)detection
             inWebView:(WKWebView *)webView
            completion:(CaptchaPipelineCompletion)completion;

/// 按优先级依次求解页上全部可解检测项（math → text_ocr）。
+ (void)solveAllSolvableFrom:(NSArray<CaptchaDetection *> *)detections
                   inWebView:(WKWebView *)webView
                  completion:(CaptchaPipelineCompletion)completion;

@end

NS_ASSUME_NONNULL_END
