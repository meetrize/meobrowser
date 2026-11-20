#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTabDragGhostStyle) {
    BrowserTabDragGhostStyleInStrip = 0,
    BrowserTabDragGhostStyleDetach,
    BrowserTabDragGhostStyleForeign,
};

/// 标签拖拽半透明影子：截图跟手，不参与命中，不持有 WKWebView。
/// Detach 态扩展为透明「整窗」预览（标题栏 + 内容区），不再只显示标签条碎片。
@interface BrowserTabDragGhostController : NSObject

@property (nonatomic, assign, readonly) BOOL visible;
@property (nonatomic, assign, readonly) BrowserTabDragGhostStyle style;
@property (nonatomic, assign, readonly) NSSize ghostSize;

/// 从源标签显示影子；先空壳跟手，截图延后到下一 runloop（afterCapture 在截图尝试后回调，可能已取消）。
/// grabPointInSource 为按下点相对源视图 bounds 的坐标。
- (void)beginWithSourceView:(NSView *)sourceView
          grabPointInSource:(NSPoint)grabPointInSource
               afterCapture:(void (^ _Nullable)(void))afterCapture;

/// 配置拖出成新窗口时的整窗预览尺寸与内容缩略图（可在 begin 之后、进入 Detach 前调用）。
- (void)prepareDetachPreviewWithWindowSize:(NSSize)windowSize
                              contentImage:(NSImage * _Nullable)contentImage;

/// 更新 Detach 预览内容图（异步截图完成后调用；非 Detach 时仅缓存）。
- (void)updateDetachContentImage:(NSImage * _Nullable)contentImage;

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
