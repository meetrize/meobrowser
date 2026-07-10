#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装 macOS 标准菜单栏（应用 / 编辑 / 窗口），使 ⌘C ⌘V ⌘X ⌘A ⌘Z 等快捷键经响应链生效。
@interface SBApplicationMenus : NSObject

+ (void)installStandardMenusWithAppName:(NSString *)appName;

@end

NS_ASSUME_NONNULL_END
