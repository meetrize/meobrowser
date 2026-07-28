#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 内存缩略图 LRU：tabID → NSImage；最长边约 480pt，最多约 20 张。
@interface BrowserTabThumbnailCache : NSObject

+ (instancetype)sharedCache;

- (nullable NSImage *)imageForTabID:(NSUUID *)tabID;
- (void)setImage:(NSImage *)image forTabID:(NSUUID *)tabID;
- (void)removeImageForTabID:(NSUUID *)tabID;
- (void)removeAll;

/// 异步截取可见区并写入缓存（缩放至最长边上限）。completion 在主线程。
- (void)captureFromWebView:(WKWebView *)webView
                   forTabID:(NSUUID *)tabID
                 completion:(void (^ _Nullable)(NSImage * _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
