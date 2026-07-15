#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 地址栏右侧可拖拽宽度的按钮工具组；宽度不足时自动显示溢出菜单。
/// 组内按钮支持按住拖动调整顺序，顺序会持久化。
@interface BrowserAddressBarActionGroup : NSView

/// 控制整组宽度的约束，由本视图创建并激活。
@property (nonatomic, strong, readonly) NSLayoutConstraint *widthConstraint;

/// 地址栏最小保留宽度，用于拖拽时钳制按钮组扩张。
@property (nonatomic, assign) CGFloat minimumAddressWidth;

/// 用于计算按钮组最大宽度的容器（通常为 BrowserAddressBarRowView）。
@property (nonatomic, weak, nullable) NSView *layoutContainer;

/// 下载按钮（组内首项，优先保持可见）；由窗口控制器设置 target/action 与角标。
@property (nonatomic, strong, readonly) NSButton *downloadButton;

/// 登录助手按钮；由窗口控制器设置 target/action 与点亮态。
@property (nonatomic, strong, readonly, nullable) NSButton *loginAssistButton;

/// 根据拖拽增量调整按钮组宽度（正值为变宽）。
- (void)applyWidthDelta:(CGFloat)deltaX;

- (void)beginWidthResize;
- (void)endWidthResize;

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;

@end

/// 覆盖在地址栏右缘的隐形拖拽区，用于调整地址栏与按钮组宽度。
@interface BrowserAddressBarEdgeResizeView : NSView
@property (nonatomic, copy, nullable) void (^onDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onDrag)(CGFloat deltaX);
@property (nonatomic, copy, nullable) void (^onDragEnded)(void);
@end

NS_ASSUME_NONNULL_END
