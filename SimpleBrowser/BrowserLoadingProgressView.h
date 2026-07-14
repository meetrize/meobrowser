#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat BrowserLoadingProgressHeight;

/// 贴在内容区顶部的细加载进度条（Chrome 风格）。
@interface BrowserLoadingProgressView : NSView

- (void)beginLoading;
- (void)setProgress:(double)progress animated:(BOOL)animated;
/// 进度到 1 后短暂保持并淡出；若当前未显示则无操作。
- (void)completeIfVisible;
/// 立即隐藏并复位（切标签、失败、新标签页等）。
- (void)resetHidden;

@end

NS_ASSUME_NONNULL_END
