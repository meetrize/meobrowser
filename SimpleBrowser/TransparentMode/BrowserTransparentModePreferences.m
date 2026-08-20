#import "BrowserTransparentModePreferences.h"

NSNotificationName const BrowserTransparentModePreferencesDidChangeNotification =
    @"BrowserTransparentModePreferencesDidChangeNotification";

NSString * const BrowserTransparentModeStylePresetIDKey = @"id";
NSString * const BrowserTransparentModeStylePresetTitleKey = @"title";
NSString * const BrowserTransparentModeStylePresetTextColorHexKey = @"textColorHex";
NSString * const BrowserTransparentModeStylePresetShadowColorHexKey = @"shadowColorHex";
NSString * const BrowserTransparentModeStylePresetShadowStrengthKey = @"shadowStrength";
NSString * const BrowserTransparentModeStylePresetShadowRadiusKey = @"shadowRadius";

static NSString * const kTransparentModeTextColorKey = @"MeoBrowser.TransparentMode.textColorHex";
static NSString * const kTransparentModeShadowColorKey = @"MeoBrowser.TransparentMode.textShadowColorHex";
static NSString * const kTransparentModeShadowStrengthKey = @"MeoBrowser.TransparentMode.textShadowStrength";
static NSString * const kTransparentModeShadowRadiusKey = @"MeoBrowser.TransparentMode.textShadowRadius";
static NSString * const kDefaultTextColorHex = @"#f2f2f2";
static NSString * const kDefaultShadowColorHex = @"#000000";
static const CGFloat kDefaultShadowStrength = 0.90;
static const CGFloat kDefaultShadowRadius = 3.0;

@implementation BrowserTransparentModePreferences

+ (void)postDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserTransparentModePreferencesDidChangeNotification
                                                        object:nil];
}

+ (NSColor *)defaultTextColor {
    return [self colorFromCSSHex:kDefaultTextColorHex] ?: [NSColor colorWithWhite:0.95 alpha:1.0];
}

+ (NSColor *)defaultTextShadowColor {
    return [self colorFromCSSHex:kDefaultShadowColorHex] ?: [NSColor blackColor];
}

+ (NSColor *)textColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeTextColorKey];
    NSColor *color = [self colorFromCSSHex:hex];
    return color ?: [self defaultTextColor];
}

+ (BOOL)storeTextColorHex:(NSString *)hex {
    if (hex.length == 0) {
        return NO;
    }
    NSString *normalized = hex.lowercaseString;
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeTextColorKey];
    if ([current.lowercaseString isEqualToString:normalized]) {
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kTransparentModeTextColorKey];
    return YES;
}

+ (void)setTextColor:(NSColor *)color {
    if (!color) {
        return;
    }
    NSString *hex = [self cssHexFromColor:color];
    if ([self storeTextColorHex:hex]) {
        [self postDidChange];
    }
}

+ (NSString *)textColorCSSHex {
    NSString *hex = [self cssHexFromColor:[self textColor]];
    return hex.length > 0 ? hex : kDefaultTextColorHex;
}

+ (void)resetTextColorToDefault {
    [self setTextColor:[self defaultTextColor]];
}

+ (NSColor *)textShadowColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeShadowColorKey];
    NSColor *color = [self colorFromCSSHex:hex];
    return color ?: [self defaultTextShadowColor];
}

+ (BOOL)storeShadowColorHex:(NSString *)hex {
    if (hex.length == 0) {
        return NO;
    }
    NSString *normalized = hex.lowercaseString;
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeShadowColorKey];
    if ([current.lowercaseString isEqualToString:normalized]) {
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kTransparentModeShadowColorKey];
    return YES;
}

+ (void)setTextShadowColor:(NSColor *)color {
    if (!color) {
        return;
    }
    NSString *hex = [self cssHexFromColor:color];
    if ([self storeShadowColorHex:hex]) {
        [self postDidChange];
    }
}

+ (NSString *)textShadowColorCSSHex {
    NSString *hex = [self cssHexFromColor:[self textShadowColor]];
    return hex.length > 0 ? hex : kDefaultShadowColorHex;
}

+ (CGFloat)clampStrength:(CGFloat)value {
    if (isnan(value) || isinf(value)) {
        return kDefaultShadowStrength;
    }
    return MAX(0.0, MIN(1.0, value));
}

+ (CGFloat)clampRadius:(CGFloat)value {
    if (isnan(value) || isinf(value)) {
        return kDefaultShadowRadius;
    }
    return MAX(0.0, MIN(24.0, value));
}

+ (CGFloat)textShadowStrength {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kTransparentModeShadowStrengthKey] == nil) {
        return kDefaultShadowStrength;
    }
    return [self clampStrength:[defaults doubleForKey:kTransparentModeShadowStrengthKey]];
}

+ (BOOL)storeShadowStrength:(CGFloat)strength {
    CGFloat clamped = [self clampStrength:strength];
    CGFloat current = [self textShadowStrength];
    if (fabs(current - clamped) < 0.0005) {
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:kTransparentModeShadowStrengthKey];
    return YES;
}

+ (void)setTextShadowStrength:(CGFloat)strength {
    if ([self storeShadowStrength:strength]) {
        [self postDidChange];
    }
}

+ (CGFloat)textShadowRadius {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kTransparentModeShadowRadiusKey] == nil) {
        return kDefaultShadowRadius;
    }
    return [self clampRadius:[defaults doubleForKey:kTransparentModeShadowRadiusKey]];
}

+ (BOOL)storeShadowRadius:(CGFloat)radius {
    CGFloat clamped = [self clampRadius:radius];
    CGFloat current = [self textShadowRadius];
    if (fabs(current - clamped) < 0.05) {
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:kTransparentModeShadowRadiusKey];
    return YES;
}

+ (void)setTextShadowRadius:(CGFloat)radius {
    if ([self storeShadowRadius:radius]) {
        [self postDidChange];
    }
}

+ (void)resetTextShadowToDefault {
    BOOL changed = NO;
    changed = [self storeShadowColorHex:kDefaultShadowColorHex] || changed;
    changed = [self storeShadowStrength:kDefaultShadowStrength] || changed;
    changed = [self storeShadowRadius:kDefaultShadowRadius] || changed;
    if (changed) {
        [self postDidChange];
    }
}

+ (void)applyTextColor:(NSColor *)textColor
           shadowColor:(NSColor *)shadowColor
       shadowStrength:(CGFloat)strength
         shadowRadius:(CGFloat)radius {
    BOOL changed = NO;
    if (textColor) {
        changed = [self storeTextColorHex:[self cssHexFromColor:textColor]] || changed;
    }
    if (shadowColor) {
        changed = [self storeShadowColorHex:[self cssHexFromColor:shadowColor]] || changed;
    }
    changed = [self storeShadowStrength:strength] || changed;
    changed = [self storeShadowRadius:radius] || changed;
    if (changed) {
        [self postDidChange];
    }
}

+ (NSArray<NSDictionary *> *)availableStylePresets {
    return @[
        @{
            BrowserTransparentModeStylePresetIDKey: @"moonlight",
            BrowserTransparentModeStylePresetTitleKey: @"月光",
            BrowserTransparentModeStylePresetTextColorHexKey: @"#f2f2f2",
            BrowserTransparentModeStylePresetShadowColorHexKey: @"#000000",
            BrowserTransparentModeStylePresetShadowStrengthKey: @0.90,
            BrowserTransparentModeStylePresetShadowRadiusKey: @3.0,
        },
        @{
            BrowserTransparentModeStylePresetIDKey: @"ink",
            BrowserTransparentModeStylePresetTitleKey: @"墨影",
            BrowserTransparentModeStylePresetTextColorHexKey: @"#1a1a1a",
            BrowserTransparentModeStylePresetShadowColorHexKey: @"#ffffff",
            BrowserTransparentModeStylePresetShadowStrengthKey: @0.88,
            BrowserTransparentModeStylePresetShadowRadiusKey: @4.0,
        },
        @{
            BrowserTransparentModeStylePresetIDKey: @"parchment",
            BrowserTransparentModeStylePresetTitleKey: @"暖阅",
            BrowserTransparentModeStylePresetTextColorHexKey: @"#3d2b1f",
            BrowserTransparentModeStylePresetShadowColorHexKey: @"#f3e2c0",
            BrowserTransparentModeStylePresetShadowStrengthKey: @0.75,
            BrowserTransparentModeStylePresetShadowRadiusKey: @5.0,
        },
        @{
            BrowserTransparentModeStylePresetIDKey: @"aurora",
            BrowserTransparentModeStylePresetTitleKey: @"青辉",
            BrowserTransparentModeStylePresetTextColorHexKey: @"#e7fff4",
            BrowserTransparentModeStylePresetShadowColorHexKey: @"#0b3d2c",
            BrowserTransparentModeStylePresetShadowStrengthKey: @0.95,
            BrowserTransparentModeStylePresetShadowRadiusKey: @6.0,
        },
    ];
}

+ (void)applyStylePresetWithID:(NSString *)presetID {
    if (presetID.length == 0) {
        return;
    }
    for (NSDictionary *preset in [self availableStylePresets]) {
        if (![preset[BrowserTransparentModeStylePresetIDKey] isEqualToString:presetID]) {
            continue;
        }
        NSColor *text = [self colorFromCSSHex:preset[BrowserTransparentModeStylePresetTextColorHexKey]]
            ?: [self defaultTextColor];
        NSColor *shadow = [self colorFromCSSHex:preset[BrowserTransparentModeStylePresetShadowColorHexKey]]
            ?: [self defaultTextShadowColor];
        CGFloat strength = [preset[BrowserTransparentModeStylePresetShadowStrengthKey] doubleValue];
        CGFloat radius = [preset[BrowserTransparentModeStylePresetShadowRadiusKey] doubleValue];
        [self applyTextColor:text shadowColor:shadow shadowStrength:strength shadowRadius:radius];
        return;
    }
}

+ (NSDictionary *)pageStyleApplyOptions {
    return @{
        @"color": [self textColorCSSHex],
        @"shadowColor": [self textShadowColorCSSHex],
        @"shadowStrength": @([self textShadowStrength]),
        @"shadowRadius": @([self textShadowRadius]),
    };
}

#pragma mark - Hex helpers

+ (nullable NSColor *)colorFromCSSHex:(NSString *)hex {
    if (hex.length == 0) {
        return nil;
    }
    NSString *value = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([value hasPrefix:@"#"]) {
        value = [value substringFromIndex:1];
    }
    if (value.length == 3) {
        unichar r = [value characterAtIndex:0];
        unichar g = [value characterAtIndex:1];
        unichar b = [value characterAtIndex:2];
        value = [NSString stringWithFormat:@"%c%c%c%c%c%c", r, r, g, g, b, b];
    }
    if (value.length != 6) {
        return nil;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned int rgb = 0;
    if (![scanner scanHexInt:&rgb]) {
        return nil;
    }
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

+ (NSString *)cssHexFromColor:(NSColor *)color {
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgb) {
        return kDefaultTextColorHex;
    }
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [rgb getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02x%02x%02x",
            (unsigned)lround(MAX(0, MIN(1, r)) * 255.0),
            (unsigned)lround(MAX(0, MIN(1, g)) * 255.0),
            (unsigned)lround(MAX(0, MIN(1, b)) * 255.0)];
}

@end
