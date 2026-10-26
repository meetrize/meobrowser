#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserLaunchpadBackgroundPresetDidChangeNotification;

/// 新标签页预置背景（深色渐变）。无自定义壁纸图时使用。
@interface BrowserLaunchpadBackgroundPreset : NSObject

+ (NSInteger)count;
+ (NSInteger)defaultIndex;
+ (NSInteger)selectedIndex;
+ (void)setSelectedIndex:(NSInteger)index;

+ (NSString *)nameAtIndex:(NSInteger)index;
/// 对角渐变起止色（至少 2 个）。
+ (NSArray<NSColor *> *)colorsAtIndex:(NSInteger)index;
/// 快捷方式标题色（预置均为深色 → 白字）。
+ (NSColor *)shortcutTitleColorAtIndex:(NSInteger)index;
+ (NSColor *)selectedShortcutTitleColor;

/// 配置已有 CAGradientLayer（起止点为左上→右下）。
+ (void)applyIndex:(NSInteger)index toGradientLayer:(CAGradientLayer *)layer;

@end

NS_ASSUME_NONNULL_END
