#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Square bezel 下紧凑文字区边距（矮输入框避免下行裁切；勿为修裁切加高控件）。
FOUNDATION_EXPORT const CGFloat kSBTextFieldCompactHorizontalInset;
FOUNDATION_EXPORT const CGFloat kSBTextFieldCompactVerticalInset;

/// 在已扣除 leading/trailing content inset 的 area 上套用紧凑 inset。
NSRect SBTextFieldApplyCompactInsets(NSRect area);

/// 未聚焦时标题贴紧凑区上沿绘制（避免 cell 垂直居中显得离上边过远；与 field editor 顶对齐一致）。
/// `controlView` 用于判断是否 flipped（`NSTextField` 默认 NO）。
NSRect SBTextFieldTopAlignedTitleRect(NSRect area, NSFont * _Nullable font, NSView * _Nullable controlView);

NS_ASSUME_NONNULL_END
