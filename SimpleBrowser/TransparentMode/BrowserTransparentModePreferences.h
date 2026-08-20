#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserTransparentModePreferencesDidChangeNotification;

/// 预设字典键：id / title / textColorHex / shadowColorHex / shadowStrength / shadowRadius
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetIDKey;
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetTitleKey;
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetTextColorHexKey;
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetShadowColorHexKey;
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetShadowStrengthKey;
FOUNDATION_EXPORT NSString * const BrowserTransparentModeStylePresetShadowRadiusKey;

/// 透明模式页面样式偏好（统一文字色、文字阴影等）。
@interface BrowserTransparentModePreferences : NSObject

/// 默认近白，保证暗色站透明后仍可读。
+ (NSColor *)defaultTextColor;
+ (NSColor *)defaultTextShadowColor;

+ (NSColor *)textColor;
+ (void)setTextColor:(NSColor *)color;

/// CSS 用 `#rrggbb`（小写）。
+ (NSString *)textColorCSSHex;

+ (void)resetTextColorToDefault;

/// 文字阴影颜色（默认近黑）。
+ (NSColor *)textShadowColor;
+ (void)setTextShadowColor:(NSColor *)color;
+ (NSString *)textShadowColorCSSHex;

/// 文字阴影不透明度/深浅，范围 0…1，默认 0.9。
+ (CGFloat)textShadowStrength;
+ (void)setTextShadowStrength:(CGFloat)strength;

/// 文字阴影模糊半径（pt），范围 0…24，默认 3。
+ (CGFloat)textShadowRadius;
+ (void)setTextShadowRadius:(CGFloat)radius;

+ (void)resetTextShadowToDefault;

/// 一次性写入文字色 + 阴影色/深浅/大小（只发一次变更通知）。
+ (void)applyTextColor:(NSColor *)textColor
           shadowColor:(NSColor *)shadowColor
       shadowStrength:(CGFloat)strength
         shadowRadius:(CGFloat)radius;

/// 配色风格预设（月光 / 墨影 / 暖阅 / 青辉）。
+ (NSArray<NSDictionary *> *)availableStylePresets;
+ (void)applyStylePresetWithID:(NSString *)presetID;

/// 供 JS `apply({...})` 使用的参数字典。
+ (NSDictionary *)pageStyleApplyOptions;

@end

NS_ASSUME_NONNULL_END
