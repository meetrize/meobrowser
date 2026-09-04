#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 与工具栏背景一致的活动标签填充色
NSColor *BrowserTabActiveFillColor(void);

/// 渐进压缩档位（见 tab-strip-lru-favicon-design.md §3.2）
typedef NS_ENUM(NSInteger, BrowserTabDisplayMode) {
    /// favicon + 完整标题 + 关闭（≥108 pt 非选中）
    BrowserTabDisplayModeComfortable = 0,
    /// favicon + 短标题；关闭仅选中/悬停（56～107 pt）
    BrowserTabDisplayModeCompact,
    /// 仅 favicon（<56 pt；非选中绝对最小 32 pt，选中 Minimal 48 pt）
    BrowserTabDisplayModeMinimal,
};

FOUNDATION_EXPORT BrowserTabDisplayMode BrowserTabDisplayModeForWidth(CGFloat width, BOOL isSelected);

/// Comfortable 下限；与 `BrowserTabItemComfortMinWidth` 同值（历史别名）
FOUNDATION_EXPORT const CGFloat BrowserTabItemMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemMaxWidth;
/// 固定标签最小宽（与普通标签一致，仍显示标题）
FOUNDATION_EXPORT const CGFloat BrowserTabPinnedWidth;

/// LRU 渐进压缩宽度常量（TS-LRU-0+）
FOUNDATION_EXPORT const CGFloat BrowserTabItemAbsoluteMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemMinimalSelectedWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemCompactMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemCompactMaxWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemComfortMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabActiveWidthBonus;
FOUNDATION_EXPORT const CGFloat BrowserTabFaviconSize;
FOUNDATION_EXPORT const CGFloat BrowserTabFaviconLeadingPad;
FOUNDATION_EXPORT const CGFloat BrowserTabFaviconTitleGap;

@interface BrowserTabItemView : NSView

@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, assign) BOOL tabPinned;
@property (nonatomic, copy) NSString *tabTitle;
/// 页面 URL，用于 favicon 占位与后续 Service 绑定（TS-LRU-1+）
@property (nonatomic, copy, nullable) NSString *pageURLString;
/// 悬停完整提示（标题 + 网址）；标题栏 accessory 内系统 toolTip 不可靠，由自定义浮层展示。
@property (nonatomic, copy, nullable) NSString *tabToolTip;
@property (nonatomic, copy, nullable) void (^onSelect)(void);
/// 按下开始选中手势时调用（tracking 前）；用于预热休眠 WebView，勿做重 UI。
@property (nonatomic, copy, nullable) void (^onSelectGestureBegan)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// Option+点击关闭按钮时调用；未设置时退回 onClose
@property (nonatomic, copy, nullable) void (^onCloseTabsToTheRight)(void);
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^contextMenuProvider)(void);
/// 拖拽超过阈值后开始；参数为当前指针相对窗口的坐标。
@property (nonatomic, copy, nullable) void (^onReorderDragBegan)(NSPoint locationInWindow);
@property (nonatomic, copy, nullable) void (^onReorderDragMoved)(NSPoint locationInWindow);
/// 拖拽结束；locationInWindow 为松手时相对窗口的坐标。
@property (nonatomic, copy, nullable) void (^onReorderDragEnded)(NSPoint locationInWindow);

- (void)setTabTitle:(NSString *)tabTitle;
- (void)setPageURLString:(nullable NSString *)pageURLString;
- (void)setTabHeight:(CGFloat)height;

/// 由标签条布局写入当前分配宽度，用于关闭按钮显隐策略
- (void)applyAvailableWidth:(CGFloat)width;

/// 最近一次 `applyAvailableWidth:` 对应的显示档位
@property (nonatomic, readonly, assign) BrowserTabDisplayMode tabDisplayMode;

@end

NS_ASSUME_NONNULL_END
