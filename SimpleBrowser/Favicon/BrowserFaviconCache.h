#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFaviconCache : NSObject

+ (instancetype)sharedCache;

+ (NSURL *)cacheDirectoryURL;
+ (NSURL *)blobsDirectoryURL;
+ (NSURL *)indexFileURL;

/// 仅查内存热缓存；miss 返回 nil（不堵主线程读盘）。
- (nullable NSImage *)imageForHost:(NSString *)host;

/// 内存 miss 时异步读盘，完成后回调主线程；若写入内存则一并 post 由 Service 发通知。
- (void)loadImageForHost:(NSString *)host
              completion:(void (^)(NSImage * _Nullable image))completion;

/// 仅在后台队列调用：同步读盘并填充内存（供瀑布 fetch 使用）。
- (nullable NSImage *)imageForHostLoadingFromDiskIfNeeded:(NSString *)host;

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
