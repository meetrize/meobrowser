#import "BrowserSystemURLSession.h"

@implementation BrowserSystemURLSession

+ (NSURLSessionConfiguration *)ephemeralConfigurationWithRequestTimeout:(NSTimeInterval)requestTimeout
                                                         resourceTimeout:(NSTimeInterval)resourceTimeout {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    // 刻意不设置 connectionProxyDictionary：nil = 继承系统「网络」代理 / PAC。
    config.timeoutIntervalForRequest = requestTimeout;
    config.timeoutIntervalForResource = resourceTimeout;
    return config;
}

+ (NSURLSession *)ephemeralSessionWithRequestTimeout:(NSTimeInterval)requestTimeout
                                     resourceTimeout:(NSTimeInterval)resourceTimeout {
    NSURLSessionConfiguration *config =
        [self ephemeralConfigurationWithRequestTimeout:requestTimeout resourceTimeout:resourceTimeout];
    return [NSURLSession sessionWithConfiguration:config];
}

+ (NSURLSession *)ephemeralSessionWithRequestTimeout:(NSTimeInterval)requestTimeout
                                     resourceTimeout:(NSTimeInterval)resourceTimeout
                                            delegate:(id<NSURLSessionDelegate>)delegate
                                       delegateQueue:(NSOperationQueue *)delegateQueue {
    NSURLSessionConfiguration *config =
        [self ephemeralConfigurationWithRequestTimeout:requestTimeout resourceTimeout:resourceTimeout];
    return [NSURLSession sessionWithConfiguration:config
                                         delegate:delegate
                                    delegateQueue:delegateQueue];
}

@end
