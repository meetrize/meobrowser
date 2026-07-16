#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 叠在下载工具栏按钮上的圆形进度环；不拦截鼠标事件。
@interface BrowserDownloadProgressRingView : NSView

/// 0…1；仅在 `indeterminate == NO` 时绘制确定弧段。
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) BOOL indeterminate;
@property (nonatomic, assign, getter=isActive) BOOL active;

@end

NS_ASSUME_NONNULL_END
