#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFaviconCache : NSObject

+ (instancetype)sharedCache;

+ (NSURL *)cacheDirectoryURL;
+ (NSURL *)blobsDirectoryURL;
+ (NSURL *)indexFileURL;

/// 优先内存，其次磁盘；均无则 nil。
- (nullable NSImage *)imageForHost:(NSString *)host;

- (nullable NSString *)sourceURLForHost:(NSString *)host;
- (nullable NSString *)sourceChannelForHost:(NSString *)host;

/// 缩放落盘（最长边 ≤ 128）并更新内存。成功返回 YES。
- (BOOL)storeImage:(NSImage *)image
           forHost:(NSString *)host
         sourceURL:(nullable NSString *)sourceURL
           channel:(nullable NSString *)channel;

- (void)removeHost:(NSString *)host;

/// 测试 / 维护：清空内存热缓存（不删磁盘）。
- (void)clearMemoryCache;

@end

NS_ASSUME_NONNULL_END
