#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserMenus : NSObject

/// 安装文件 / 查看 / 标签页菜单一次；窗口动作走 First Responder，新建窗口指向 AppDelegate。
+ (void)installBrowserChromeMenus;

+ (void)installTabMenuForTarget:(id)target;
+ (void)installSettingsMenuForTarget:(id)target;
+ (void)installDownloadMenuForTarget:(id)target;
+ (void)installViewMenuForTarget:(id)target;

@end

NS_ASSUME_NONNULL_END
