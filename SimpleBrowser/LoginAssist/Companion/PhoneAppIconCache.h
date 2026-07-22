#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PhoneAppIconCacheDidChangeNotification;
extern NSString * const PhoneAppIconCachePackageNameKey;

/// 按 Android packageName 缓存应用小图标（PNG 落盘）。
@interface PhoneAppIconCache : NSObject

+ (instancetype)sharedCache;

- (nullable NSImage *)imageForPackage:(nullable NSString *)packageName;
- (nullable NSString *)hashForPackage:(nullable NSString *)packageName;

- (BOOL)storePNGData:(NSData *)data
             package:(NSString *)packageName
            iconHash:(NSString *)iconHash
            appLabel:(nullable NSString *)appLabel
               error:(NSError * _Nullable * _Nullable)error;

/// 单条通知自带图标（厂商代理包无法归因时）；与 package 缓存隔离。
- (nullable NSImage *)imageForNotificationItemID:(nullable NSString *)itemID;
- (BOOL)storeNotificationItemIconPNGData:(NSData *)data
                                  itemID:(NSString *)itemID
                                iconHash:(NSString *)iconHash
                                   error:(NSError * _Nullable * _Nullable)error;
- (void)removeNotificationItemIconForID:(nullable NSString *)itemID;

- (NSArray<NSString *> *)packagesMissingFrom:(NSArray<NSString *> *)packages;

/// 28×28 首字占位（无缓存时）。
+ (NSImage *)placeholderImageWithLabel:(nullable NSString *)label package:(nullable NSString *)packageName;
/// OTP 行占位。
+ (NSImage *)otpPlaceholderImage;

@end

NS_ASSUME_NONNULL_END
