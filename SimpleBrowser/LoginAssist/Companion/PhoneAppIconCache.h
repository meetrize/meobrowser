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

- (NSArray<NSString *> *)packagesMissingFrom:(NSArray<NSString *> *)packages;

/// 28×28 首字占位（无缓存时）。
+ (NSImage *)placeholderImageWithLabel:(nullable NSString *)label package:(nullable NSString *)packageName;
/// OTP 行占位。
+ (NSImage *)otpPlaceholderImage;

@end

NS_ASSUME_NONNULL_END
