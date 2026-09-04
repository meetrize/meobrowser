#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 主框架 provisional 超时（秒）。短于 NSURLRequest 默认 60s。
FOUNDATION_EXPORT const NSTimeInterval BrowserMainFrameNavigationTimeout;

/// 从 loadURL / loadRequest 起算的总导航超时（秒）。覆盖「从未 didStartProvisional」的空等。
FOUNDATION_EXPORT const NSTimeInterval BrowserNavigationOverallTimeout;

/// commit 后文档仍 isLoading 的宽限（秒）。到期 stopLoading 并清加载 UI，不换错误页（默认 10s）。
FOUNDATION_EXPORT const NSTimeInterval BrowserDocumentLoadGraceTimeout;

/// `__meo_hf` / hash 恢复等短宽限（秒），给 window.stop() 与 SPA 留出时间。
FOUNDATION_EXPORT const NSTimeInterval BrowserDocumentLoadGraceTimeoutShort;

/// 超时 stop 后仍僵死再硬恢复的延迟（秒）。NH-3 使用。
FOUNDATION_EXPORT const NSTimeInterval BrowserStuckWebViewHardRecoverDelay;

NS_ASSUME_NONNULL_END
