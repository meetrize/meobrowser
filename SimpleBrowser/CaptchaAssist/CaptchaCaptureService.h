#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CaptchaCaptureCompletion)(NSImage * _Nullable image, NSError * _Nullable error);

@interface CaptchaCaptureService : NSObject

/// 整页可见区域截图。
+ (void)captureVisibleInWebView:(WKWebView *)webView
                     completion:(CaptchaCaptureCompletion)completion;

/// 按 CSS 视口矩形裁剪（原点左上）；rect 无效时退化为整页。
+ (void)captureInWebView:(WKWebView *)webView
              viewportRect:(CGRect)rect
                completion:(CaptchaCaptureCompletion)completion;

@end

NS_ASSUME_NONNULL_END
