#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserLaunchpadAppearanceDidChangeNotification;

typedef NS_ENUM(NSInteger, BrowserLaunchpadAppearancePreset) {
    BrowserLaunchpadAppearancePresetCompact = 0,
    BrowserLaunchpadAppearancePresetComfortable,
    BrowserLaunchpadAppearancePresetSpacious,
};

/// 新标签页快捷方式网格外观（图标大小 / 左右间距 / 上下间距）。
@interface BrowserLaunchpadAppearance : NSObject

@property (nonatomic, assign, readonly) CGFloat iconSize;
@property (nonatomic, assign, readonly) CGFloat horizontalSpacing;
@property (nonatomic, assign, readonly) CGFloat verticalSpacing;

+ (instancetype)current;

+ (CGFloat)defaultIconSize;
+ (CGFloat)minIconSize;
+ (CGFloat)maxIconSize;
+ (CGFloat)defaultHorizontalSpacing;
+ (CGFloat)minHorizontalSpacing;
+ (CGFloat)maxHorizontalSpacing;
+ (CGFloat)defaultVerticalSpacing;
+ (CGFloat)minVerticalSpacing;
+ (CGFloat)maxVerticalSpacing;

+ (CGFloat)cellWidthForIconSize:(CGFloat)iconSize;
+ (CGFloat)cellHeightForIconSize:(CGFloat)iconSize;
+ (CGFloat)iconCornerRadiusForIconSize:(CGFloat)iconSize;
+ (CGFloat)iconShadowInsetForIconSize:(CGFloat)iconSize;

+ (void)setIconSize:(CGFloat)iconSize;
+ (void)setHorizontalSpacing:(CGFloat)spacing;
+ (void)setVerticalSpacing:(CGFloat)spacing;
+ (void)applyPreset:(BrowserLaunchpadAppearancePreset)preset;
+ (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
