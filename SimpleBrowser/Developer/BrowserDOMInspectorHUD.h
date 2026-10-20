#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 气泡内容视图。整体鼠标穿透，仅「复制选择器」按钮热区接收点击。
@interface BrowserDOMInspectorHUDView : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, copy) NSArray<NSString *> *attributeRows;
@property (nonatomic, assign) NSRect copyButtonRect;
@property (nonatomic, copy, nullable) void (^onCopySelector)(void);
@end

/// DOM 探针悬停气泡。
/// 实现为浏览器窗口 contentView 的子视图（非独立窗口），因此天然与网页处于
/// 同一块屏幕，多屏下不会漂移；且不会像容器子视图那样被父视图边界裁剪。
@interface BrowserDOMInspectorHUD : NSObject

/// geometry 为元素在窗口 contentView 坐标系下的矩形（调用方负责换算）。
/// webViewRect 为 webView 在 contentView 中的矩形，用于把气泡约束在网页区域内，
/// 避免跑到标签栏等 chrome 区域被遮挡。
- (void)showSnapshot:(NSDictionary *)snapshot
   geometryInContent:(NSRect)geometry
     webViewInContent:(NSRect)webViewRect
            inWindow:(NSWindow *)window;

/// 复制选择器按钮被点击。
@property (nonatomic, copy, nullable) void (^onCopySelector)(NSString *selector);

- (void)hide;

@end

NS_ASSUME_NONNULL_END
