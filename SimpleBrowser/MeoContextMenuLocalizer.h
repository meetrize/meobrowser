#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 将 WebKit / 系统英文右键菜单项统一翻译为简体中文（identifier 映射 + 标题兜底）。
@interface MeoContextMenuLocalizer : NSObject

+ (void)localizeMenu:(NSMenu *)menu;

@end

NS_ASSUME_NONNULL_END
