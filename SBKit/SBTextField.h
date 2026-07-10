#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 项目标准单行输入框。禁止直接使用裸 `NSTextField`，统一经此类或配置类创建。
@interface SBTextField : NSTextField

+ (instancetype)standardField;

@end

NS_ASSUME_NONNULL_END
