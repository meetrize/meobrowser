#import <Foundation/Foundation.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

/// 系统 Web Inspector 接入（inspectable / show）。
@interface BrowserWebInspector : NSObject

/// macOS 13.3+ 支持 `WKWebView.inspectable`。
+ (BOOL)isInspectionSupported;

/// 按当前偏好设置 `inspectable`；不支持的系统上为 no-op。
+ (void)applyInspectableToWebView:(nullable WKWebView *)webView;

/// 尝试程序化打开系统 Web Inspector。成功返回 YES；失败由调用方降级到 Safari 附加说明。
/// 会先按偏好 apply inspectable（调用方应已确保偏好开启）。
+ (BOOL)showInspectorForWebView:(nullable WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
