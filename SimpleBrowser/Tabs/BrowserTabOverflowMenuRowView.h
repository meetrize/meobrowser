#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 标签溢出 ▾ 菜单行：勾选 + favicon + 标题。
@interface BrowserTabOverflowMenuRowView : NSView

@property (nonatomic, assign) BOOL checked;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *pageURLString;

@property (nonatomic, copy, nullable) void (^onSelect)(void);

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)reloadAppearance;

@end

NS_ASSUME_NONNULL_END
