#import "BrowserBackgroundMediaController.h"

@implementation BrowserBackgroundMediaController

+ (void)pauseMediaInWebView:(WKWebView *)webView
                 completion:(void (^)(BOOL foundMedia))completion {
    if (webView == nil) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    // 尽力而为：覆盖常见 video/audio；自定义播放器可能无效，由加速休眠兜底。
    NSString *script =
        @"(function(){"
         "var n=0;"
         "function pause(el){"
         "  try{"
         "    if(!el) return;"
         "    if(typeof el.pause==='function' && !el.paused){ el.pause(); }"
         "    try{ el.muted=true; }catch(e){}"
         "    n++;"
         "  }catch(e){}"
         "}"
         "try{"
         "  document.querySelectorAll('video,audio').forEach(pause);"
         "}catch(e){}"
         "return n;"
         "})();";

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)error;
        BOOL found = NO;
        if ([result isKindOfClass:[NSNumber class]]) {
            found = [(NSNumber *)result integerValue] > 0;
        }
        if (completion) {
            completion(found);
        }
    }];
}

@end
