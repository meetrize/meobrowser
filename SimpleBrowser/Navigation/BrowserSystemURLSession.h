#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 统一创建尊重 macOS 系统代理的 NSURLSession / Configuration。
/// 勿将 connectionProxyDictionary 设为空字典，否则会绕过系统代理。
@interface BrowserSystemURLSession : NSObject

/// ephemeral 配置：不持久化 Cookie/缓存；保留系统代理（不写 connectionProxyDictionary）。
+ (NSURLSessionConfiguration *)ephemeralConfigurationWithRequestTimeout:(NSTimeInterval)requestTimeout
                                                         resourceTimeout:(NSTimeInterval)resourceTimeout;

/// 基于上项配置创建 session（无自定义 delegate）。
+ (NSURLSession *)ephemeralSessionWithRequestTimeout:(NSTimeInterval)requestTimeout
                                     resourceTimeout:(NSTimeInterval)resourceTimeout;

/// 带 delegate 的 ephemeral session。
+ (NSURLSession *)ephemeralSessionWithRequestTimeout:(NSTimeInterval)requestTimeout
                                     resourceTimeout:(NSTimeInterval)resourceTimeout
                                            delegate:(nullable id<NSURLSessionDelegate>)delegate
                                       delegateQueue:(nullable NSOperationQueue *)delegateQueue;

@end

NS_ASSUME_NONNULL_END
