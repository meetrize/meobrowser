#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTabDragGhostStyle) {
    BrowserTabDragGhostStyleInStrip = 0,
    BrowserTabDragGhostStyleDetach,
    BrowserTabDragGhostStyleForeign,
};

/// 标签拖拽半透明影子：截图跟手，不参与命中，不持有 WKWebView。
@interface BrowserTabDragGhostController : NSObject

@property (nonatomic, assign, readonly) BOOL visible;
@property (nonatomic, assign, readonly) BrowserTabDragGhostStyle style;
@property (nonatomic, assign, readonly) NSSize ghostSize;

/// 从源标签截图并显示；grabPointInSource 为按下点相对源视图 bounds 的坐标。
- (void)beginWithSourceView:(NSView *)sourceView grabPointInSource:(NSPoint)grabPointInSource;

/// 指针屏幕坐标（AppKit 原点左下）。
- (void)moveToScreenPoint:(NSPoint)screenPoint;

- (void)setStyle:(BrowserTabDragGhostStyle)style animated:(BOOL)animated;

/// 兼容：等价于 Detach / InStrip。
- (void)setDetachMode:(BOOL)detachMode animated:(BOOL)animated;

/// 吸附到目标屏幕矩形后移除；Reduce Motion 时立即移除。
- (void)animateToScreenRect:(NSRect)screenRect
                 completion:(void (^ _Nullable)(void))completion;

/// 短淡出后移除（跨窗提交用）。
- (void)fadeOutWithCompletion:(void (^ _Nullable)(void))completion;

- (void)endAndRemoveImmediately;

@end

NS_ASSUME_NONNULL_END
