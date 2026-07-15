#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 进程内会话的 HTTPS 证书例外（host:port）。不持久化。
@interface BrowserSSLExceptionStore : NSObject

+ (instancetype)sharedStore;

+ (NSString *)hostKeyForHost:(NSString *)host port:(NSInteger)port;
+ (nullable NSString *)hostKeyForURL:(nullable NSURL *)url;

- (BOOL)allowsHostKey:(NSString *)hostKey;
- (BOOL)allowsURL:(nullable NSURL *)url;
- (void)allowHostKey:(NSString *)hostKey;
- (void)revokeHostKey:(NSString *)hostKey;
- (void)removeAll;

@end

NS_ASSUME_NONNULL_END
