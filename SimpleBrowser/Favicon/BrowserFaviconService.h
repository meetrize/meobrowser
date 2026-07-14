#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserFaviconFetchReason) {
    BrowserFaviconFetchReasonSilent = 0,
    BrowserFaviconFetchReasonUserAction = 1,
};

typedef NS_ENUM(NSInteger, BrowserFaviconErrorCode) {
    BrowserFaviconErrorInvalidURL = 1,
    BrowserFaviconErrorAllChannelsFailed = 2,
    BrowserFaviconErrorCancelled = 3,
    BrowserFaviconErrorDecodeFailed = 4,
    BrowserFaviconErrorNegativeCached = 5,
};

FOUNDATION_EXPORT NSErrorDomain const BrowserFaviconErrorDomain;
FOUNDATION_EXPORT NSNotificationName const BrowserFaviconDidUpdateNotification;
FOUNDATION_EXPORT NSString * const BrowserFaviconHostUserInfoKey;

@interface BrowserFaviconService : NSObject

+ (instancetype)sharedService;

/// 显示用：优先磁盘 / 内存；没有则可选触发 Silent 瀑布。
- (void)imageForPageURLString:(NSString *)pageURLString
              preferredIconURL:(nullable NSString *)iconURLString
                   triggerFetch:(BOOL)triggerFetch
                     completion:(void (^)(NSImage * _Nullable image))completion;

/// 完整瀑布；成功写入磁盘缓存。completion 始终在主线程。
- (void)fetchAndCacheForPageURLString:(NSString *)pageURLString
                      preferredIconURL:(nullable NSString *)preferredIconURL
                                reason:(BrowserFaviconFetchReason)reason
                            completion:(void (^ _Nullable)(NSURL * _Nullable iconURL,
                                                           NSImage * _Nullable image,
                                                           NSError * _Nullable error))completion;

- (nullable NSImage *)cachedImageForHost:(NSString *)host;

- (void)cancelFetchForHost:(NSString *)host;
- (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
