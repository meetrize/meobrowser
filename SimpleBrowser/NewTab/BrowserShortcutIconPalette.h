#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 自定义色块图标色板（固定 16 色，与 Android 同表）。
FOUNDATION_EXPORT NSInteger const BrowserShortcutIconPaletteColorCount;

@interface BrowserShortcutIconPalette : NSObject

+ (NSInteger)colorCount;
+ (NSColor *)colorAtIndex:(NSInteger)index;
+ (NSInteger)clampedIndex:(NSInteger)index;
+ (NSInteger)defaultIndexForURLString:(nullable NSString *)urlString;

/// 取第一个 Unicode 字形；空串返回 @""。
+ (NSString *)normalizedLetterFromString:(nullable NSString *)string;

/// 标题优先，否则域名首字（与 Launchpad 字母占位一致）。
+ (NSString *)defaultLetterForTitle:(nullable NSString *)title
                          urlString:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
