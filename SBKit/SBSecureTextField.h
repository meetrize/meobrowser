#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SBSecureTextField : NSSecureTextField

+ (instancetype)standardField;

/// 收紧文字上下绘制区。经 `standardField` / configuration 创建时默认 YES。
@property (nonatomic) BOOL usesCompactVerticalTextInsets;

/// 内容 inset 变更后同步 field editor 外框（与 SBTextField 对齐）。
- (void)syncFieldEditorFrameWithContentInsets;

@end

NS_ASSUME_NONNULL_END
