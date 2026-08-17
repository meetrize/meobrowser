#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 导航诊断日志。Debug 默认开；Release 需 `defaults write … MeoBrowserNavigationDiagnostics -bool YES`。
FOUNDATION_EXPORT BOOL BrowserNavigationDiagnosticsEnabled(void);
FOUNDATION_EXPORT void BrowserNavigationLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
