#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 菜单栏 Status Item：进入/退出透明模式、退出应用（App 级单例）。
@interface BrowserStatusItemController : NSObject

+ (instancetype)sharedController;

/// 安装菜单栏图标（可重复调用，仅首次生效）。
- (void)install;

/// 菜单即将弹出时刷新「进入/退出」文案与勾选。
- (void)refreshMenuAppearance;

@end

NS_ASSUME_NONNULL_END
