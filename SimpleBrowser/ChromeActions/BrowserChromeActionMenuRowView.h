#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// ⋯ 菜单自定义行：左侧图标 + 标题（可勾选）+ 右侧图钉。
@interface BrowserChromeActionMenuRowView : NSView

@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *titleText;
/// 与条上 `BrowserChromeActionItem.symbolName` 一致。
@property (nonatomic, copy, nullable) NSString *symbolName;
/// 与条上 `onSymbolName` 一致；勾选开态时优先显示。
@property (nonatomic, copy, nullable) NSString *onSymbolName;
@property (nonatomic, assign) BOOL checked;
@property (nonatomic, assign) BOOL pinnedToToolbar;
@property (nonatomic, assign) BOOL titleEnabled;

@property (nonatomic, copy, nullable) void (^onTitleClick)(NSString *itemID);
@property (nonatomic, copy, nullable) void (^onPinClick)(NSString *itemID);

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)reloadAppearance;

@end

NS_ASSUME_NONNULL_END
