#import "BrowserTransparentModePreferences.h"

NSNotificationName const BrowserTransparentModePreferencesDidChangeNotification =
    @"BrowserTransparentModePreferencesDidChangeNotification";

static NSString * const kTransparentModeTextColorKey = @"MeoBrowser.TransparentMode.textColorHex";
static NSString * const kDefaultTextColorHex = @"#f2f2f2";

@implementation BrowserTransparentModePreferences

+ (NSColor *)defaultTextColor {
    return [self colorFromCSSHex:kDefaultTextColorHex] ?: [NSColor colorWithWhite:0.95 alpha:1.0];
}

+ (NSColor *)textColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeTextColorKey];
    NSColor *color = [self colorFromCSSHex:hex];
    return color ?: [self defaultTextColor];
}

+ (void)setTextColor:(NSColor *)color {
    if (!color) {
        return;
    }
    NSString *hex = [self cssHexFromColor:color];
    if (hex.length == 0) {
        return;
    }
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:kTransparentModeTextColorKey];
    if ([current.lowercaseString isEqualToString:hex.lowercaseString]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:hex forKey:kTransparentModeTextColorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserTransparentModePreferencesDidChangeNotification
                                                        object:nil];
}

+ (NSString *)textColorCSSHex {
    NSString *hex = [self cssHexFromColor:[self textColor]];
    return hex.length > 0 ? hex : kDefaultTextColorHex;
}

+ (void)resetTextColorToDefault {
    [self setTextColor:[self defaultTextColor]];
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
