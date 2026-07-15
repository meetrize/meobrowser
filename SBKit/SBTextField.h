#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 项目标准单行输入框。禁止直接使用裸 `NSTextField`，统一经此类或配置类创建。
@interface SBTextField : NSTextField

+ (instancetype)standardField;

/// 为左侧内嵌控件（如安全指示）预留的文字区域宽度。
@property (nonatomic) CGFloat leadingContentInset;

/// 为右侧内嵌控件（如收藏按钮）预留的文字区域宽度。
@property (nonatomic) CGFloat trailingContentInset;

/// 鼠标点击获得焦点时全选文字（再次点击已聚焦时不全选，便于移动光标）。
@property (nonatomic) BOOL selectsAllOnMouseFocus;

@end

NS_ASSUME_NONNULL_END
