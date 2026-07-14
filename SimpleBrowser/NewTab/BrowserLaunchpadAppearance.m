#import "BrowserLaunchpadAppearance.h"

NSString * const BrowserLaunchpadAppearanceDidChangeNotification = @"BrowserLaunchpadAppearanceDidChangeNotification";

static NSString * const kIconSizeKey = @"launchpadIconSize";
static NSString * const kHorizontalSpacingKey = @"launchpadHorizontalSpacing";
static NSString * const kVerticalSpacingKey = @"launchpadVerticalSpacing";

static const CGFloat kDefaultIconSize = 64.0;
static const CGFloat kMinIconSize = 48.0;
static const CGFloat kMaxIconSize = 80.0;
static const CGFloat kDefaultHorizontalSpacing = 32.0;
static const CGFloat kMinHorizontalSpacing = 0.0;
static const CGFloat kMaxHorizontalSpacing = 64.0;
static const CGFloat kDefaultVerticalSpacing = 32.0;
static const CGFloat kMinVerticalSpacing = 4.0;
static const CGFloat kMaxVerticalSpacing = 64.0;
/// 标题行预留高度（图标容器下方）。
static const CGFloat kTitleAreaHeight = 22.0;

static CGFloat Clamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static CGFloat LoadCGFloat(NSString *key, CGFloat fallback, CGFloat minValue, CGFloat maxValue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:key]) {
        return fallback;
    }
    return Clamp([defaults doubleForKey:key], minValue, maxValue);
}

@implementation BrowserLaunchpadAppearance

+ (instancetype)current {
    BrowserLaunchpadAppearance *appearance = [[BrowserLaunchpadAppearance alloc] init];
    appearance->_iconSize = LoadCGFloat(kIconSizeKey, kDefaultIconSize, kMinIconSize, kMaxIconSize);
    appearance->_horizontalSpacing = LoadCGFloat(kHorizontalSpacingKey,
                                                 kDefaultHorizontalSpacing,
                                                 kMinHorizontalSpacing,
                                                 kMaxHorizontalSpacing);
    appearance->_verticalSpacing = LoadCGFloat(kVerticalSpacingKey,
                                               kDefaultVerticalSpacing,
                                               kMinVerticalSpacing,
                                               kMaxVerticalSpacing);
    return appearance;
}

+ (CGFloat)defaultIconSize { return kDefaultIconSize; }
+ (CGFloat)minIconSize { return kMinIconSize; }
+ (CGFloat)maxIconSize { return kMaxIconSize; }
+ (CGFloat)defaultHorizontalSpacing { return kDefaultHorizontalSpacing; }
+ (CGFloat)minHorizontalSpacing { return kMinHorizontalSpacing; }
+ (CGFloat)maxHorizontalSpacing { return kMaxHorizontalSpacing; }
+ (CGFloat)defaultVerticalSpacing { return kDefaultVerticalSpacing; }
+ (CGFloat)minVerticalSpacing { return kMinVerticalSpacing; }
+ (CGFloat)maxVerticalSpacing { return kMaxVerticalSpacing; }

+ (CGFloat)cellWidthForIconSize:(CGFloat)iconSize {
    // 单元格宽度贴齐可视图标；阴影画在 bounds 外，左右间距才真正控制图标间距。
    return Clamp(iconSize, kMinIconSize, kMaxIconSize);
}

+ (CGFloat)cellHeightForIconSize:(CGFloat)iconSize {
    CGFloat clamped = Clamp(iconSize, kMinIconSize, kMaxIconSize);
    CGFloat shadowInset = [self iconShadowInsetForIconSize:clamped];
    return clamped + shadowInset * 2.0 + kTitleAreaHeight;
}

+ (CGFloat)iconCornerRadiusForIconSize:(CGFloat)iconSize {
    return 14.0 * (Clamp(iconSize, kMinIconSize, kMaxIconSize) / kDefaultIconSize);
}

+ (CGFloat)iconShadowInsetForIconSize:(CGFloat)iconSize {
    return 10.0 * (Clamp(iconSize, kMinIconSize, kMaxIconSize) / kDefaultIconSize);
}

+ (void)persistIconSize:(CGFloat)iconSize
     horizontalSpacing:(CGFloat)horizontalSpacing
       verticalSpacing:(CGFloat)verticalSpacing {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:Clamp(iconSize, kMinIconSize, kMaxIconSize) forKey:kIconSizeKey];
    [defaults setDouble:Clamp(horizontalSpacing, kMinHorizontalSpacing, kMaxHorizontalSpacing)
                 forKey:kHorizontalSpacingKey];
    [defaults setDouble:Clamp(verticalSpacing, kMinVerticalSpacing, kMaxVerticalSpacing)
                 forKey:kVerticalSpacingKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserLaunchpadAppearanceDidChangeNotification
                                                        object:nil];
}

+ (void)setIconSize:(CGFloat)iconSize {
    BrowserLaunchpadAppearance *current = [self current];
    [self persistIconSize:iconSize
       horizontalSpacing:current.horizontalSpacing
         verticalSpacing:current.verticalSpacing];
}

+ (void)setHorizontalSpacing:(CGFloat)spacing {
    BrowserLaunchpadAppearance *current = [self current];
    [self persistIconSize:current.iconSize
       horizontalSpacing:spacing
         verticalSpacing:current.verticalSpacing];
}

+ (void)setVerticalSpacing:(CGFloat)spacing {
    BrowserLaunchpadAppearance *current = [self current];
    [self persistIconSize:current.iconSize
       horizontalSpacing:current.horizontalSpacing
         verticalSpacing:spacing];
}

+ (void)applyPreset:(BrowserLaunchpadAppearancePreset)preset {
    switch (preset) {
        case BrowserLaunchpadAppearancePresetCompact:
            [self persistIconSize:52 horizontalSpacing:16 verticalSpacing:16];
            break;
        case BrowserLaunchpadAppearancePresetSpacious:
            [self persistIconSize:72 horizontalSpacing:48 verticalSpacing:40];
            break;
        case BrowserLaunchpadAppearancePresetComfortable:
        default:
            [self persistIconSize:kDefaultIconSize
               horizontalSpacing:kDefaultHorizontalSpacing
                 verticalSpacing:kDefaultVerticalSpacing];
            break;
    }
}

+ (void)resetToDefaults {
    [self applyPreset:BrowserLaunchpadAppearancePresetComfortable];
}

@end
