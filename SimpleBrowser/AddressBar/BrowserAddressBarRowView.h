#import <Cocoa/Cocoa.h>

@class SBTextField;
@class BrowserAddressBarActionGroup;

NS_ASSUME_NONNULL_BEGIN

/// 地址栏 + 按钮组横向容器，使用显式约束分配宽度（避免 NSStackView 吞掉宽度约束）。
@interface BrowserAddressBarRowView : NSView

@property (nonatomic, strong, readonly) SBTextField *addressField;
@property (nonatomic, strong, readonly) BrowserAddressBarActionGroup *actionGroup;

- (instancetype)initWithAddressField:(SBTextField *)addressField
                         actionGroup:(BrowserAddressBarActionGroup *)actionGroup NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
