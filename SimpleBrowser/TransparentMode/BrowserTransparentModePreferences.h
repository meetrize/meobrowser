#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserTransparentModePreferencesDidChangeNotification;

/// 透明模式页面样式偏好（统一文字色等）。
@interface BrowserTransparentModePreferences : NSObject

/// 默认近白，保证暗色站透明后仍可读。
+ (NSColor *)defaultTextColor;

+ (NSColor *)textColor;
+ (void)setTextColor:(NSColor *)color;

/// CSS 用 `#rrggbb`（小写）。
+ (NSString *)textColorCSSHex;

+ (void)resetTextColorToDefault;

@end

NS_ASSUME_NONNULL_END
