#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserFeedURLScheme; // @"meo-feed"

@interface BrowserFeedReader : NSObject

/// 是否应按 Feed 可读页处理（而非下载 / 原始 XML）。
+ (BOOL)shouldHandleNavigationResponse:(WKNavigationResponse *)navigationResponse;

/// 根据 MIME / URL 判断是否为 Feed。
+ (BOOL)isFeedMIMEType:(nullable NSString *)mimeType URL:(nullable NSURL *)url;

/// 将真实 Feed URL 转为可进入后退栈的内部阅读地址。
+ (NSURL *)readerURLForFeedURL:(NSURL *)feedURL;

/// 从内部阅读地址还原真实 Feed URL。
+ (nullable NSURL *)feedURLFromReaderURL:(nullable NSURL *)readerURL;

/// 地址栏 / 会话用：meo-feed → 真实 http(s) Feed URL。
+ (nullable NSURL *)publicURLForInternalURL:(nullable NSURL *)url;

+ (BOOL)isFeedReaderURL:(nullable NSURL *)url;

/// 拉取并渲染可读 HTML，成功时回调 html；失败时 error。
+ (void)loadReadableHTMLForFeedURL:(NSURL *)feedURL
                 completionHandler:(void (^)(NSString * _Nullable html, NSError * _Nullable error))completionHandler;

/// 将 XML 正文转为可读 HTML（已在主线程外可调用）。
+ (nullable NSString *)readableHTMLFromFeedData:(NSData *)data
                                       feedURL:(NSURL *)feedURL
                                         error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
