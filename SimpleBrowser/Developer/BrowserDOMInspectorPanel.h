#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// DOM 探针钉住面板：分组展示元素全部属性，值区分段可复制。
@interface BrowserDOMInspectorPanel : NSView

@property (nonatomic, assign, readwrite, getter=isVisible) BOOL visible;

/// 展示一次 pinned 快照。
- (void)showSnapshot:(NSDictionary *)snapshot;
- (void)hidePanel;

/// 复制成功提示回调。
@property (nonatomic, copy, nullable) void (^onCopy)(NSString *description);
/// 用户请求关闭面板。
@property (nonatomic, copy, nullable) void (^onRequestClose)(void);

@end

NS_ASSUME_NONNULL_END
