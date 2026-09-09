#import <Foundation/Foundation.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

/// 标签 / 切页 UI 诊断。默认开启；关闭：
/// `defaults write com.example.MeoBrowser MeoBrowserTabUIDiagnostics -bool NO`
///
/// 查看日志（任选其一）：
/// 1. `tail -f ~/Library/Logs/MeoBrowser/tab-ui.log`   ← 最稳
/// 2. 终端直接跑 App：`./build/MeoBrowser.app/Contents/MacOS/MeoBrowser`
/// 3. `log stream --predicate 'subsystem == "com.example.MeoBrowser" AND category == "TabUI"' --level debug`
///
/// 前缀 `[MeoTabUI]`。主线程卡顿超过阈值时自动打 HANG。
FOUNDATION_EXPORT BOOL BrowserTabUIDiagnosticsEnabled(void);
FOUNDATION_EXPORT void BrowserTabUILog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// 超过该毫秒才标 SLOW（默认 50）。可用 defaults：MeoBrowserTabUISlowMs
FOUNDATION_EXPORT NSTimeInterval BrowserTabUISlowThresholdMs(void);

/// 主线程卡顿监测阈值（默认 120ms）。可用 defaults：MeoBrowserTabUIHangMs
FOUNDATION_EXPORT NSTimeInterval BrowserTabUIHangThresholdMs(void);

/// 应用启动后调用一次；仅在诊断开启时真正启动。
FOUNDATION_EXPORT void BrowserTabUIDiagnosticsStartHangWatchdogIfNeeded(void);
FOUNDATION_EXPORT void BrowserTabUIDiagnosticsStopHangWatchdog(void);

/// 打一条当前标签库存摘要（live / mediaHeavy / protected 等）。
FOUNDATION_EXPORT void BrowserTabUILogInventory(NSArray<BrowserTab *> *tabs,
                                               BrowserTab *_Nullable selectedTab,
                                               NSUInteger liveInWindow,
                                               NSUInteger liveGlobal);

/// 测量一段同步代码；durationMs 始终带回，超过慢阈值时自动打 SLOW 日志。
FOUNDATION_EXPORT NSTimeInterval BrowserTabUIMeasure(NSString *label, NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
