#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserDownloadPreferencesDidChangeNotification;

/// 下载目录偏好（UserDefaults）。当前非沙盒，存 POSIX 路径；若日后启用 App Sandbox，改为 security-scoped bookmark。
@interface BrowserDownloadPreferences : NSObject

+ (instancetype)sharedPreferences;

/// 用户选定的目录；nil 表示使用系统「下载」。
@property (nonatomic, copy, nullable) NSURL *customDirectoryURL;

/// 实际写入用：自定义目录可用则用之，否则系统「下载」（必要时 create:YES）。
@property (nonatomic, copy, readonly, nullable) NSURL *effectiveDirectoryURL;

@property (nonatomic, assign, readonly) BOOL usesCustomDirectory;
@property (nonatomic, assign, readonly) BOOL customDirectoryIsReachable;

- (void)resetToSystemDownloadsDirectory;

/// 设置里展示的路径（带 ~）；自定义不可达时仍显示该自定义路径。
- (NSString *)displayPath;

@end

NS_ASSUME_NONNULL_END
