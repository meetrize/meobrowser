#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 与工具栏背景一致的活动标签填充色
NSColor *BrowserTabActiveFillColor(void);

FOUNDATION_EXPORT const CGFloat BrowserTabItemMinWidth;
FOUNDATION_EXPORT const CGFloat BrowserTabItemMaxWidth;

@interface BrowserTabItemView : NSView

@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, copy) NSString *tabTitle;
@property (nonatomic, copy, nullable) void (^onSelect)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);

- (void)setTabTitle:(NSString *)tabTitle;
- (void)setTabHeight:(CGFloat)height;

/// 由标签条布局写入当前分配宽度，用于关闭按钮显隐策略
- (void)applyAvailableWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
