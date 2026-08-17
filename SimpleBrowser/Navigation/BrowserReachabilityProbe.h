#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserReachabilityProbeResult) {
    BrowserReachabilityProbeResultUnknown = 0,
    BrowserReachabilityProbeResultReachable,
    BrowserReachabilityProbeResultDNSFailed,
    BrowserReachabilityProbeResultUnreachable,
};

@class BrowserReachabilityProbeHandle;

typedef void (^BrowserReachabilityProbeCompletion)(BrowserReachabilityProbeResult result,
                                                   NSInteger suggestedURLErrorCode);

/// 可取消的并行主机探测句柄。
@interface BrowserReachabilityProbeHandle : NSObject
- (void)cancel;
@end

/// 乐观加载旁路：短超时探测主机是否明显不可达。不阻塞 loadRequest。
@interface BrowserReachabilityProbe : NSObject

+ (instancetype)sharedProbe;

/// UserDefaults `MeoBrowserQuickReachabilityProbe`，缺省 YES。
+ (BOOL)isQuickProbeEnabled;
+ (void)setQuickProbeEnabled:(BOOL)enabled;

/// 是否应对该 URL 发起探测（http(s)、非本地、无系统代理介入）。
+ (BOOL)shouldProbeURL:(nullable NSURL *)url;

/// 异步探测；completion 在主线程。全局并发 ≤4；总预算约 2s。
- (nullable BrowserReachabilityProbeHandle *)probeURL:(NSURL *)url
                                          completion:(BrowserReachabilityProbeCompletion)completion;

@end

/// 不可达 host 短 TTL 负缓存（内存）。
@interface BrowserHostNegativeCache : NSObject

+ (instancetype)sharedCache;

- (nullable NSNumber *)failureCodeForHostKey:(NSString *)hostKey;
- (void)recordFailureCode:(NSInteger)code forHostKey:(NSString *)hostKey;
- (void)clearHostKey:(NSString *)hostKey;
- (void)clearAll;

+ (nullable NSString *)hostKeyForURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
