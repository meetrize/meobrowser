#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 将 Bundle 内置种子 Page Pack 安装到 Application Support（已存在则默认不覆盖）。
@interface PagePackSeedInstaller : NSObject

/// App 启动时调用：安装全部内置种子（Maps / Earth 叠加校准等）。
+ (void)installBundledSeedsIfNeeded;

/// @param force YES 时用 Bundle 覆盖本地同 id Pack（「恢复官方种子」）。
+ (BOOL)installSeedNamed:(NSString *)seedFolderName
                   force:(BOOL)force
                   error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
