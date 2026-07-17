#import <WebKit/WebKit.h>

@class BrowserFeedItem;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserFeedAssistHandlerName;

@interface BrowserFeedDetector : NSObject

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
                messageHandler:(id<WKScriptMessageHandler>)handler;

/// 页面内扫描 Feed 的 JS（返回 feeds 数组）；供 didFinish 主动再扫。
+ (NSString *)scanFeedsJavaScript;

/// 将 JS / 消息体中的字典数组解析为 Feed 列表。
+ (NSArray<BrowserFeedItem *> *)feedItemsFromDictionaries:(NSArray *)raw;

/// 站点常见 Feed 路径候选（同源根路径）。
+ (NSArray<NSURL *> *)conventionalFeedCandidateURLsForPageURL:(NSURL *)pageURL;

/// 对常见路径做 HEAD/轻量探测；completion 始终在主线程回调。
+ (NSURLSessionTask *)probeConventionalFeedsForPageURL:(NSURL *)pageURL
                                    completionHandler:(void (^)(NSArray<BrowserFeedItem *> *feeds))completionHandler;

@end

NS_ASSUME_NONNULL_END
