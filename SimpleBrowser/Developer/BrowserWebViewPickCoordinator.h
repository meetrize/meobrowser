#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 拾取权被抢占时广播。object 为协调器，userInfo[BrowserWebViewPickYieldedOwnerKey] 为被让出的 owner。
FOUNDATION_EXPORT NSNotificationName const BrowserWebViewPickCoordinatorDidYieldNotification;
FOUNDATION_EXPORT NSString * const BrowserWebViewPickYieldedOwnerKey;

/// 页面「点击拾取」仲裁：同一时刻只允许一个拾取器占用 WebView。
/// 页面爬虫点选与 DOM 探针都通过它申请，避免两套监听同时抢点击。
@protocol BrowserWebViewPickCoordinatorDelegate <NSObject>
/// 另一个拾取器抢占后，本拾取器应立即退出并恢复 UI。
- (void)browserWebViewPickCoordinatorDidYield:(id)owner;
@end

@interface BrowserWebViewPickCoordinator : NSObject

@property (class, nonatomic, readonly) BrowserWebViewPickCoordinator *shared;

/// 当前占用者；无占用时为 nil。
@property (nonatomic, weak, readonly, nullable) id currentOwner;

/// 申请拾取权。成功后返回 YES，并回调旧 owner 的 yield。
- (BOOL)beginPickInWebView:(nullable WKWebView *)webView owner:(id)owner;

/// 释放拾取权（仅当 owner 仍持有时释放）。
- (void)endPickForOwner:(id)owner;

/// 是否是持有者。
- (BOOL)isCurrentOwner:(id)owner;

@end

NS_ASSUME_NONNULL_END
