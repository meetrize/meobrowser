#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class BrowserDownloadItem;
@class BrowserDownloadManager;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserDownloadManagerDidChangeNotification;

@protocol BrowserDownloadManagerObserver <NSObject>
- (void)downloadManagerDidChange:(BrowserDownloadManager *)manager;
@end

@interface BrowserDownloadManager : NSObject <WKDownloadDelegate>

+ (instancetype)sharedManager;

/// 在创建 WKWebView 前注入：缓存 createObjectURL(Blob) 与 get_play_info 等媒体地址。
+ (void)installMediaCaptureScriptOnConfiguration:(WKWebViewConfiguration *)configuration;

@property (nonatomic, copy, readonly) NSArray<BrowserDownloadItem *> *items;
@property (nonatomic, assign, readonly) NSUInteger activeCount;
@property (nonatomic, assign, readonly) NSUInteger unreadCompletedCount;
@property (nonatomic, assign, readonly) double aggregateProgress; // 进行中聚合 0...1；无活动为 0
@property (nonatomic, assign, readonly) BOOL aggregateProgressIsDeterminate; // 任一项已知总长则为 YES
@property (nonatomic, assign, readonly) BOOL hasActiveDownloads;

- (void)addObserver:(id<BrowserDownloadManagerObserver>)observer;
- (void)removeObserver:(id<BrowserDownloadManagerObserver>)observer;

/// 接管来自 WKWebView 的 WKDownload（didBecomeDownload）。
- (void)takeOwnershipOfDownload:(WKDownload *)download;
- (void)takeOwnershipOfDownload:(WKDownload *)download
             suggestedFilename:(nullable NSString *)suggestedFilename;

/// 主动发起下载（例如将来扩展菜单）；不问路径，写入当前下载目录（偏好，默认 ~/Downloads）。
- (void)startDownloadWithURL:(NSURL *)url fromWebView:(WKWebView *)webView;
- (void)startDownloadWithURL:(NSURL *)url
          suggestedFilename:(nullable NSString *)suggestedFilename
                fromWebView:(WKWebView *)webView;

/// Safari 对齐：`<a download>` 等应走 WKNavigationActionPolicyDownload。
+ (BOOL)shouldDownloadNavigationAction:(WKNavigationAction *)navigationAction;
/// `<a download="…">` 文件名；当前 SDK 头文件可能未声明该属性，运行时读取。
+ (nullable NSString *)downloadAttributeFromNavigationAction:(WKNavigationAction *)navigationAction;

- (void)cancelItem:(BrowserDownloadItem *)item;
- (void)revealItemInFinder:(BrowserDownloadItem *)item;
- (void)openItem:(BrowserDownloadItem *)item;
- (void)removeItem:(BrowserDownloadItem *)item;
- (void)clearFinishedItems;
- (void)markAllCompletedAsRead;

/// 当前有效下载目录（自定义可用则用之，否则系统「下载」）。
- (nullable NSURL *)downloadDirectoryURL;
/// 用系统默认文件管理器打开下载目录（读取全局 NSFileViewer，如 MeoFind；未设置则 Finder）。
- (BOOL)openDownloadDirectory;

+ (BOOL)shouldDownloadNavigationResponse:(WKNavigationResponse *)navigationResponse;

@end

NS_ASSUME_NONNULL_END
