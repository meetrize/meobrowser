#import <Cocoa/Cocoa.h>

@class SBTextField;
@class BrowserAddressBarActionGroup;

NS_ASSUME_NONNULL_BEGIN

/// 地址栏 + 可选安全徽章；工具按钮已迁至标签栏 Chrome 区（actionGroup 可空）。
@interface BrowserAddressBarRowView : NSView

@property (nonatomic, strong, readonly) SBTextField *addressField;
@property (nonatomic, strong, readonly, nullable) NSView *securityBadge;
@property (nonatomic, strong, readonly, nullable) BrowserAddressBarActionGroup *actionGroup;

- (instancetype)initWithAddressField:(SBTextField *)addressField
                       securityBadge:(nullable NSView *)securityBadge
                         actionGroup:(nullable BrowserAddressBarActionGroup *)actionGroup NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 显示/隐藏安全徽章；隐藏时不占布局宽度。preferredWidth 为文字实测宽度。
- (void)setSecurityBadgeVisible:(BOOL)visible preferredWidth:(CGFloat)preferredWidth;

@end

NS_ASSUME_NONNULL_END
