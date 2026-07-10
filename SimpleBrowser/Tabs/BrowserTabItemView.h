#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 与工具栏背景一致的活动标签填充色
NSColor *BrowserTabActiveFillColor(void);

@interface BrowserTabItemView : NSView

@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, copy) NSString *tabTitle;
@property (nonatomic, copy, nullable) void (^onSelect)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);

- (void)setTabTitle:(NSString *)tabTitle;
- (void)setTabHeight:(CGFloat)height;

@end

NS_ASSUME_NONNULL_END
