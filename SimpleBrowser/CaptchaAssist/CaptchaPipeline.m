#import "CaptchaPipeline.h"
#import "CaptchaHelperBridge.h"
#import "MathCaptchaAdapter.h"
#import "OCRCaptchaAdapter.h"
#import "CaptchaActor.h"
#import "CaptchaCaptureService.h"
#import "CaptchaSessionLog.h"
#import <AppKit/AppKit.h>

@implementation CaptchaPipeline

+ (CaptchaDetection *)preferredSolvableDetectionFrom:(NSArray<CaptchaDetection *> *)detections {
    NSArray<NSString *> *priority = @[@"math", @"text_ocr"];
    for (NSString *kind in priority) {
        for (CaptchaDetection *d in detections) {
            if ([d.kind isEqualToString:kind]) {
                return d;
            }
        }
    }
    return nil;
}

+ (BOOL)isSolvableKind:(NSString *)kind {
    return [kind isEqualToString:@"math"] || [kind isEqualToString:@"text_ocr"];
}

+ (void)solveAllSolvableFrom:(NSArray<CaptchaDetection *> *)detections
                   inWebView:(WKWebView *)webView
                  completion:(CaptchaPipelineCompletion)completion {
    NSMutableArray<CaptchaDetection *> *queue = [NSMutableArray array];
    for (NSString *kind in @[@"math", @"text_ocr"]) {
        for (CaptchaDetection *d in detections) {
            if ([d.kind isEqualToString:kind]) {
                [queue addObject:d];
            }
        }
    }
    if (queue.count == 0) {
        if (completion) {
            completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline"
                                                     code:9
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无可求解的 OCR/算术项"}]);
        }
        return;
    }
    [self solveQueue:queue index:0 webView:webView messages:[NSMutableArray array] completion:completion];
}

+ (void)solveQueue:(NSArray<CaptchaDetection *> *)queue
             index:(NSUInteger)index
           webView:(WKWebView *)webView
          messages:(NSMutableArray<NSString *> *)messages
        completion:(CaptchaPipelineCompletion)completion {
    if (index >= queue.count) {
        BOOL any = messages.count > 0;
        NSString *joined = [messages componentsJoinedByString:@"；"];
        if (completion) {
            completion(any, joined.length > 0 ? joined : nil,
                       any ? nil : [NSError errorWithDomain:@"CaptchaPipeline" code:10 userInfo:@{NSLocalizedDescriptionKey: @"全部求解失败"}]);
        }
        return;
    }
    CaptchaDetection *d = queue[index];
    [self solveDetection:d inWebView:webView completion:^(BOOL success, NSString *message, NSError *error) {
        if (success && message.length > 0) {
            [messages addObject:message];
        } else if (!success && error.localizedDescription.length > 0) {
            [messages addObject:[NSString stringWithFormat:@"%@ 失败：%@", [d summaryLabel], error.localizedDescription]];
        }
        [self solveQueue:queue index:index + 1 webView:webView messages:messages completion:completion];
    }];
}

+ (void)solveDetection:(CaptchaDetection *)detection
             inWebView:(WKWebView *)webView
            completion:(CaptchaPipelineCompletion)completion {
    if (!detection || !webView) {
        if (completion) {
            completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"缺少检测或页面"}]);
        }
        return;
    }
    if ([detection.kind isEqualToString:@"math"]) {
        [self solveMath:detection inWebView:webView completion:completion];
        return;
    }
    if ([detection.kind isEqualToString:@"text_ocr"]) {
        [self solveOCR:detection inWebView:webView completion:completion];
        return;
    }
    if (completion) {
        completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey: @"当前类型暂不支持自动求解（CA-1 仅 OCR/算术）"}]);
    }
}

#pragma mark - Math

+ (void)solveMath:(CaptchaDetection *)detection
        inWebView:(WKWebView *)webView
       completion:(CaptchaPipelineCompletion)completion {
    void (^finishSolve)(NSString *) = ^(NSString *mathText) {
        NSString *answer = [MathCaptchaAdapter solveMathText:mathText];
        if (!answer) {
            // 回退 Python helper
            [self solveMathViaHelper:mathText detection:detection webView:webView completion:completion];
            return;
        }
        [self fillAndVerify:answer detection:detection webView:webView completion:completion];
    };

    if (detection.mathText.length > 0) {
        finishSolve(detection.mathText);
        return;
    }

    NSString *container = detection.containerSelector;
    [CaptchaActor extractMathTextNearSelector:container inWebView:webView completion:^(NSString *text, NSError *error) {
        if (error || text.length == 0) {
            if (completion) {
                completion(NO, nil, error ?: [NSError errorWithDomain:@"CaptchaPipeline" code:3 userInfo:@{NSLocalizedDescriptionKey: @"无法读取算术题"}]);
            }
            return;
        }
        finishSolve(text);
    }];
}

+ (void)solveMathViaHelper:(NSString *)mathText
                 detection:(CaptchaDetection *)detection
                 webView:(WKWebView *)webView
                completion:(CaptchaPipelineCompletion)completion {
    [CaptchaHelperBridge evaluateMathExpression:mathText completion:^(NSString *answer, NSError *error) {
        if (error || answer.length == 0) {
            if (completion) {
                completion(NO, nil, error ?: [NSError errorWithDomain:@"CaptchaPipeline" code:4 userInfo:@{NSLocalizedDescriptionKey: @"算术求解失败"}]);
            }
            return;
        }
        [self fillAndVerify:answer detection:detection webView:webView completion:completion];
    }];
}

#pragma mark - OCR

+ (void)solveOCR:(CaptchaDetection *)detection
       inWebView:(WKWebView *)webView
      completion:(CaptchaPipelineCompletion)completion {
    NSString *imageSelector = detection.imageSelector.length > 0 ? detection.imageSelector : @"img.captcha-image";

    [CaptchaActor exportImageDataURLForSelector:imageSelector inWebView:webView completion:^(NSString *dataURL, NSError *exportError) {
        if (exportError || dataURL.length == 0) {
            // 退化为视口截图
            CGRect rect = CGRectIsNull(detection.rect) ? CGRectNull : detection.rect;
            [CaptchaCaptureService captureInWebView:webView viewportRect:rect completion:^(NSImage *image, NSError *capError) {
                if (capError || !image) {
                    if (completion) {
                        completion(NO, nil, exportError ?: capError);
                    }
                    return;
                }
                [self recognizeAndFill:image detection:detection webView:webView completion:completion];
            }];
            return;
        }
        NSImage *image = [self imageFromDataURL:dataURL];
        if (!image) {
            if (completion) {
                completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline" code:5 userInfo:@{NSLocalizedDescriptionKey: @"无法解析验证码图片"}]);
            }
            return;
        }
        [self recognizeAndFill:image detection:detection webView:webView completion:completion];
    }];
}

+ (NSImage *)imageFromDataURL:(NSString *)dataURL {
    NSRange comma = [dataURL rangeOfString:@","];
    if (comma.location == NSNotFound) {
        return nil;
    }
    NSString *b64 = [dataURL substringFromIndex:comma.location + 1];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) {
        return nil;
    }
    return [[NSImage alloc] initWithData:data];
}

+ (void)recognizeAndFill:(NSImage *)image
               detection:(CaptchaDetection *)detection
               webView:(WKWebView *)webView
              completion:(CaptchaPipelineCompletion)completion {
    [OCRCaptchaAdapter recognizeImage:image completion:^(NSString *text, NSError *error) {
        if (error || text.length == 0) {
            if (completion) {
                completion(NO, nil, error ?: [NSError errorWithDomain:@"CaptchaPipeline" code:6 userInfo:@{NSLocalizedDescriptionKey: @"OCR 无结果"}]);
            }
            return;
        }
        [CaptchaSessionLog writeSessionWithDetection:detection image:image note:[NSString stringWithFormat:@"ocr:%@", text] error:nil];
        [self fillAndVerify:text detection:detection webView:webView completion:completion];
    }];
}

#pragma mark - Fill & Verify

+ (void)fillAndVerify:(NSString *)answer
            detection:(CaptchaDetection *)detection
            webView:(WKWebView *)webView
           completion:(CaptchaPipelineCompletion)completion {
    NSString *inputSelector = detection.inputSelector;
    if (inputSelector.length == 0) {
        if (completion) {
            completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline" code:7 userInfo:@{NSLocalizedDescriptionKey: @"缺少输入框选择器"}]);
        }
        return;
    }

    [CaptchaActor fillText:answer inputSelector:inputSelector inWebView:webView completion:^(BOOL success, NSError *fillError) {
        if (!success) {
            if (completion) {
                completion(NO, nil, fillError);
            }
            return;
        }
        [CaptchaActor readValueForSelector:inputSelector inWebView:webView completion:^(NSString *value, NSError *readError) {
            if (readError) {
                if (completion) {
                    completion(NO, nil, readError);
                }
                return;
            }
            BOOL verified = value.length > 0;
            if (verified) {
                NSString *msg = [NSString stringWithFormat:@"已填入：%@", value];
                if (completion) {
                    completion(YES, msg, nil);
                }
            } else {
                if (completion) {
                    completion(NO, nil, [NSError errorWithDomain:@"CaptchaPipeline" code:8 userInfo:@{NSLocalizedDescriptionKey: @"填入后验证失败"}]);
                }
            }
        }];
    }];
}

@end
