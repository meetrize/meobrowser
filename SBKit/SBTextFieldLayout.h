#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Square bezel 下紧凑文字区边距（矮输入框避免下行裁切；勿为修裁切加高控件）。
FOUNDATION_EXPORT const CGFloat kSBTextFieldCompactHorizontalInset;
FOUNDATION_EXPORT const CGFloat kSBTextFieldCompactVerticalInset;

/// 单行字高（用于垂直居中计算）。
CGFloat SBTextFieldLineHeight(NSFont * _Nullable font);

/// 在已扣除 leading/trailing content inset 的 area 上套用紧凑 inset。
NSRect SBTextFieldApplyCompactInsets(NSRect area);

/// 在紧凑区内再从「视觉上沿」增加空白（地址栏等单独加厚上边距；默认 0）。
NSRect SBTextFieldApplyAdditionalTopInset(NSRect area, CGFloat topInset, NSView * _Nullable controlView);

/// 将文字区整体移向视觉上沿（可与 topInset 组合：先抵消 inset，再继续上移）。
NSRect SBTextFieldApplyUpwardBias(NSRect area, CGFloat upwardBias, NSView * _Nullable controlView);

/// topInset 与 upwardBias 合成后的文字区（upwardBias 优先抵消 topInset）。
NSRect SBTextFieldApplyTopInsetWithUpwardBias(NSRect area,
                                              CGFloat topInset,
                                              CGFloat upwardBias,
                                              NSView * _Nullable controlView);

/// 未聚焦时标题贴紧凑区上沿绘制（避免 cell 垂直居中显得离上边过远；与 field editor 顶对齐一致）。
NSRect SBTextFieldTopAlignedTitleRect(NSRect area, NSFont * _Nullable font, NSView * _Nullable controlView);

/// 将给定高度的内容框在 area 内垂直居中（编辑态 field editor 用）。
NSRect SBTextFieldVerticallyCenteredRect(NSRect area, CGFloat contentHeight);

NS_ASSUME_NONNULL_END
