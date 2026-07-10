#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 统一文本输入控件的默认配置（单行 / 多行 / 密码）。
@interface SBTextInputConfiguration : NSObject

+ (void)configureSingleLineTextField:(NSTextField *)textField;
+ (void)configureSecureTextField:(NSSecureTextField *)textField;
+ (void)configureMultiLineTextView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
