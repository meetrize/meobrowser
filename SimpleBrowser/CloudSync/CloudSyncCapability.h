#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 检测当前进程签名是否真正带有 CloudKit 容器 entitlement。
/// adhoc 本地签名通常剥离受限 entitlement，此时调用 CKContainer 会直接 SIGTRAP。
@interface CloudSyncCapability : NSObject

+ (BOOL)isCloudKitEntitled;
+ (NSString *)unavailableReason;

@end

NS_ASSUME_NONNULL_END
