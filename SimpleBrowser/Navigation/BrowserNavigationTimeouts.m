#import "BrowserNavigationTimeouts.h"

const NSTimeInterval BrowserMainFrameNavigationTimeout = 12.0;
const NSTimeInterval BrowserNavigationOverallTimeout = 15.0;
/// commit 后子资源宽限：不可达/境外挂起资源尽快 stop，保留已绘内容。
const NSTimeInterval BrowserDocumentLoadGraceTimeout = 10.0;
const NSTimeInterval BrowserDocumentLoadGraceTimeoutShort = 3.0;
const NSTimeInterval BrowserStuckWebViewHardRecoverDelay = 8.0;
