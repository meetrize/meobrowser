#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 与工具栏背景一致的活动标签填充色
NSColor *BrowserTabActiveFillColor(void);

FOUNDATION_EXPORT const CGFloat BrowserTabItemMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemMaxWidth;
/// 固定标签最小宽（与普通标签一致，仍显示标题）
FOUNDATION_EXPORT const CGFloat BrowserTabPinnedWidth;

@interface BrowserTabItemView : NSView

@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, assign) BOOL tabPinned;
@property (nonatomic, copy) NSString *tabTitle;
@property (nonatomic, copy, nullable) void (^onSelect)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// Option+点击关闭按钮时调用；未设置时退回 onClose
@property (nonatomic, copy, nullable) void (^onCloseTabsToTheRight)(void);
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^contextMenuProvider)(void);
/// 水平拖拽超过阈值后开始排序；参数为相对按下时窗口坐标的位移
@property (nonatomic, copy, nullable) void (^onReorderDragBegan)(void);
@property (nonatomic, copy, nullable) void (^onReorderDragMoved)(CGFloat deltaX);
@property (nonatomic, copy, nullable) void (^onReorderDragEnded)(void);

- (void)setTabTitle:(NSString *)tabTitle;
- (void)setTabHeight:(CGFloat)height;

/// 由标签条布局写入当前分配宽度，用于关闭按钮显隐策略
- (void)applyAvailableWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
