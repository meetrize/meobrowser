#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 标签拖拽半透明影子：截图跟手，不参与命中，不持有 WKWebView。
@interface BrowserTabDragGhostController : NSObject

@property (nonatomic, assign, readonly) BOOL visible;
@property (nonatomic, assign, readonly) BOOL detachMode;
@property (nonatomic, assign, readonly) NSSize ghostSize;

/// 从源标签截图并显示；grabPointInSource 为按下点相对源视图 bounds 的坐标。
- (void)beginWithSourceView:(NSView *)sourceView grabPointInSource:(NSPoint)grabPointInSource;

/// 指针屏幕坐标（AppKit 原点左下）。
- (void)moveToScreenPoint:(NSPoint)screenPoint;

/// InStrip / Detach 视觉切换。
- (void)setDetachMode:(BOOL)detachMode animated:(BOOL)animated;

/// 吸附到目标屏幕矩形（通常与 ghostSize 同大小），完成后移除。
- (void)animateToScreenRect:(NSRect)screenRect
                 completion:(void (^ _Nullable)(void))completion;

- (void)endAndRemoveImmediately;

@end

NS_ASSUME_NONNULL_END
