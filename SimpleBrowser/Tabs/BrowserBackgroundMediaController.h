#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 失活标签时暂停页面媒体，减轻直播等重页对 UI/GPU 的争抢。
@interface BrowserBackgroundMediaController : NSObject

/// 暂停并静音 document 内 video/audio。completion 在主线程；foundMedia 表示至少处理过一个元素。
+ (void)pauseMediaInWebView:(WKWebView *)webView
                 completion:(void (^ _Nullable)(BOOL foundMedia))completion;

@end

NS_ASSUME_NONNULL_END
