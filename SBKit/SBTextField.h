#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 项目标准单行输入框。禁止直接使用裸 `NSTextField`，统一经此类或配置类创建。
@interface SBTextField : NSTextField

+ (instancetype)standardField;

/// 为左侧内嵌控件（如安全指示）预留的文字区域宽度。
@property (nonatomic) CGFloat leadingContentInset;

/// 为右侧内嵌控件（如收藏按钮）预留的文字区域宽度。
@property (nonatomic) CGFloat trailingContentInset;

/// 收紧文字上下绘制区（矮输入框内默认 bezel inset 过大时底部易被裁切）。
/// 经 `SBTextInputConfiguration` / `standardField` 创建时默认 YES；仅特殊 UI 可关。
@property (nonatomic) BOOL usesCompactVerticalTextInsets;

/// 在紧凑文字区内，额外增加「距输入框上边缘」的空白。默认 0。
/// 仅地址栏等高框需要光学留白时设置；不影响快捷方式编辑 / 设置等默认贴顶样式。
@property (nonatomic) CGFloat compactTextTopInset;

/// 相对当前紧凑布局，将文字整体上移的像素（未编辑时）。默认 0。
@property (nonatomic) CGFloat compactTextUpwardBias;

/// 编辑中（field editor）时的上移像素。默认 0。
/// 与 `centersCompactTextWhenEditing` 可叠加：先垂直居中，再上移本值。
@property (nonatomic) CGFloat compactTextUpwardBiasWhenEditing;

/// 编辑态将 field editor 垂直居中（地址栏推荐）。默认 NO。
@property (nonatomic) BOOL centersCompactTextWhenEditing;

/// 在控件外框不变的前提下，将文字绘制区向下多扩若干 pt（吃掉底部 bezel 内边距）。
/// 用于非编辑态下移文字后字底被裁；默认 0。
@property (nonatomic) CGFloat compactTextBottomExtend;

/// 内容 inset 变更后，同步正在编辑的 field editor 外框（避免残留左侧留白）。
- (void)syncFieldEditorFrameWithContentInsets;

/// 鼠标点击获得焦点时全选文字（再次点击已聚焦时不全选，便于移动光标）。
@property (nonatomic) BOOL selectsAllOnMouseFocus;

@end

NS_ASSUME_NONNULL_END
