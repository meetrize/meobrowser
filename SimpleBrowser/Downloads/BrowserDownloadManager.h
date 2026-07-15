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

@property (nonatomic, copy, readonly) NSArray<BrowserDownloadItem *> *items;
@property (nonatomic, assign, readonly) NSUInteger activeCount;
@property (nonatomic, assign, readonly) NSUInteger unreadCompletedCount;
@property (nonatomic, assign, readonly) double aggregateProgress; // 进行中聚合 0...1；无活动为 0
@property (nonatomic, assign, readonly) BOOL hasActiveDownloads;

- (void)addObserver:(id<BrowserDownloadManagerObserver>)observer;
- (void)removeObserver:(id<BrowserDownloadManagerObserver>)observer;

/// 接管来自 WKWebView 的 WKDownload（didBecomeDownload）。
- (void)takeOwnershipOfDownload:(WKDownload *)download;

/// 主动发起下载（例如将来扩展菜单）；不问路径，写入 Downloads。
- (void)startDownloadWithURL:(NSURL *)url fromWebView:(WKWebView *)webView;

- (void)cancelItem:(BrowserDownloadItem *)item;
- (void)revealItemInFinder:(BrowserDownloadItem *)item;
- (void)openItem:(BrowserDownloadItem *)item;
- (void)removeItem:(BrowserDownloadItem *)item;
- (void)clearFinishedItems;
- (void)markAllCompletedAsRead;

+ (BOOL)shouldDownloadNavigationResponse:(WKNavigationResponse *)navigationResponse;

@end

NS_ASSUME_NONNULL_END
