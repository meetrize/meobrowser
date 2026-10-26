#import "BrowserLaunchpadBackgroundPreset.h"

NSString * const BrowserLaunchpadBackgroundPresetDidChangeNotification =
    @"BrowserLaunchpadBackgroundPresetDidChangeNotification";

static NSString * const kSelectedIndexDefaultsKey = @"launchpadBackgroundPresetIndex";

typedef struct {
    const char *name;
    CGFloat r0, g0, b0;
    CGFloat r1, g1, b1;
} BrowserLaunchpadBackgroundPresetSpec;

/// 深色对角渐变；索引 0 为默认。
static const BrowserLaunchpadBackgroundPresetSpec kPresets[] = {
    { "午夜", 0.043, 0.063, 0.149, 0.102, 0.153, 0.267 }, // #0B1026 → #1A2744
    { "炭灰", 0.110, 0.110, 0.118, 0.173, 0.173, 0.180 }, // #1C1C1E → #2C2C2E
    { "深海", 0.039, 0.086, 0.157, 0.051, 0.231, 0.298 }, // #0A1628 → #0D3B4C
    { "余烬", 0.102, 0.059, 0.078, 0.239, 0.122, 0.169 }, // #1A0F14 → #3D1F2B
    { "墨林", 0.047, 0.078, 0.063, 0.102, 0.184, 0.141 }, // #0C1410 → #1A2F24
    { "紫夜", 0.071, 0.063, 0.110, 0.165, 0.122, 0.271 }, // #12101C → #2A1F45
};

static const NSInteger kPresetCount = (NSInteger)(sizeof(kPresets) / sizeof(kPresets[0]));

@implementation BrowserLaunchpadBackgroundPreset

+ (NSInteger)count {
    return kPresetCount;
}

+ (NSInteger)defaultIndex {
    return 0;
}

+ (NSInteger)clampedIndex:(NSInteger)index {
    if (index < 0 || index >= kPresetCount) {
        return [self defaultIndex];
    }
    return index;
}

+ (NSInteger)selectedIndex {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSelectedIndexDefaultsKey] == nil) {
        return [self defaultIndex];
    }
    return [self clampedIndex:[defaults integerForKey:kSelectedIndexDefaultsKey]];
}

+ (void)setSelectedIndex:(NSInteger)index {
    NSInteger clamped = [self clampedIndex:index];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSelectedIndexDefaultsKey] != nil
        && [defaults integerForKey:kSelectedIndexDefaultsKey] == clamped) {
        return;
    }
    [defaults setInteger:clamped forKey:kSelectedIndexDefaultsKey];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BrowserLaunchpadBackgroundPresetDidChangeNotification
                      object:nil];
}

+ (NSString *)nameAtIndex:(NSInteger)index {
    NSInteger i = [self clampedIndex:index];
    return @(kPresets[i].name);
}

+ (NSColor *)colorWithR:(CGFloat)r g:(CGFloat)g b:(CGFloat)b {
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}

+ (NSArray<NSColor *> *)colorsAtIndex:(NSInteger)index {
    NSInteger i = [self clampedIndex:index];
    const BrowserLaunchpadBackgroundPresetSpec *spec = &kPresets[i];
    return @[
        [self colorWithR:spec->r0 g:spec->g0 b:spec->b0],
        [self colorWithR:spec->r1 g:spec->g1 b:spec->b1],
    ];
}

+ (NSColor *)shortcutTitleColorAtIndex:(NSInteger)index {
    (void)index;
    return [NSColor whiteColor];
}

+ (NSColor *)selectedShortcutTitleColor {
    return [self shortcutTitleColorAtIndex:[self selectedIndex]];
}

+ (void)applyIndex:(NSInteger)index toGradientLayer:(CAGradientLayer *)layer {
    if (layer == nil) {
        return;
    }
    NSArray<NSColor *> *colors = [self colorsAtIndex:index];
    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (NSColor *color in colors) {
        NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
        [cgColors addObject:(id)rgb.CGColor];
    }
    layer.colors = cgColors;
    layer.startPoint = CGPointMake(0.0, 1.0);
    layer.endPoint = CGPointMake(1.0, 0.0);
    layer.locations = @[ @0.0, @1.0 ];
}

@end
