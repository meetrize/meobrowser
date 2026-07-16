#import "CaptchaCaptureService.h"

@implementation CaptchaCaptureService

+ (void)captureVisibleInWebView:(WKWebView *)webView
                     completion:(CaptchaCaptureCompletion)completion {
    [self captureInWebView:webView viewportRect:CGRectNull completion:completion];
}

+ (void)captureInWebView:(WKWebView *)webView
            viewportRect:(CGRect)rect
              completion:(CaptchaCaptureCompletion)completion {
    if (!completion) {
        return;
    }
    if (!webView) {
        NSError *err = [NSError errorWithDomain:@"CaptchaCapture"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"WebView 不可用"}];
        completion(nil, err);
        return;
    }

    if (@available(macOS 10.13, *)) {
        WKSnapshotConfiguration *config = [[WKSnapshotConfiguration alloc] init];
        if (!CGRectIsNull(rect) && rect.size.width > 1 && rect.size.height > 1) {
            // WKSnapshotConfiguration.rect 使用视图坐标（点），与 CSS 像素在默认缩放下近似 1:1
            config.rect = rect;
        }
        [webView takeSnapshotWithConfiguration:config completionHandler:^(NSImage *snapshot, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !snapshot) {
                    completion(nil, error ?: [NSError errorWithDomain:@"CaptchaCapture"
                                                                 code:2
                                                             userInfo:@{NSLocalizedDescriptionKey: @"截图失败"}]);
                    return;
                }
                completion(snapshot, nil);
            });
        }];
        return;
    }

    NSError *err = [NSError errorWithDomain:@"CaptchaCapture"
                                       code:3
                                   userInfo:@{NSLocalizedDescriptionKey: @"系统版本过低，无法截图"}];
    completion(nil, err);
}

@end
