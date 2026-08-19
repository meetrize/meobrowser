#import "BrowserShortcutIconPalette.h"

NSInteger const BrowserShortcutIconPaletteColorCount = 16;

@implementation BrowserShortcutIconPalette

+ (NSInteger)colorCount {
    return BrowserShortcutIconPaletteColorCount;
}

+ (NSInteger)clampedIndex:(NSInteger)index {
    if (index < 0) {
        return 0;
    }
    NSInteger count = BrowserShortcutIconPaletteColorCount;
    if (index >= count) {
        return 0;
    }
    return index;
}

+ (NSColor *)colorAtIndex:(NSInteger)index {
    // 16 色均匀分布色相；饱和度/亮度贴近 ColorFromURLString（s=0.45, b=0.85）。
    static const CGFloat kHues[16] = {
        0.00, 0.0625, 0.125, 0.1875,
        0.25, 0.3125, 0.375, 0.4375,
        0.50, 0.5625, 0.625, 0.6875,
        0.75, 0.8125, 0.875, 0.9375,
    };
    NSInteger i = [self clampedIndex:index];
    return [NSColor colorWithHue:kHues[i] saturation:0.45 brightness:0.85 alpha:1.0];
}

+ (NSInteger)defaultIndexForURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        return 0;
    }
    return (NSInteger)(urlString.hash % (NSUInteger)BrowserShortcutIconPaletteColorCount);
}

+ (NSString *)normalizedLetterFromString:(NSString *)string {
    if (string.length == 0) {
        return @"";
    }
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"";
    }
    __block NSString *first = @"";
    [trimmed enumerateSubstringsInRange:NSMakeRange(0, trimmed.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        (void)substringRange;
        (void)enclosingRange;
        if (substring.length > 0) {
            first = substring;
            *stop = YES;
        }
    }];
    return first;
}

+ (NSString *)defaultLetterForTitle:(NSString *)title urlString:(NSString *)urlString {
    NSString *fromTitle = [self normalizedLetterFromString:title];
    if (fromTitle.length > 0) {
        return [fromTitle uppercaseString];
    }
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *host = url.host.length > 0 ? url.host : @"?";
    if ([host.lowercaseString hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    NSString *fromHost = [self normalizedLetterFromString:host];
    if (fromHost.length > 0) {
        return [fromHost uppercaseString];
    }
    return @"?";
}

@end
