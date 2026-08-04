#import "BrowserKeyboardPreferences.h"

NSNotificationName const BrowserKeyboardPreferencesDidChangeNotification =
    @"BrowserKeyboardPreferencesDidChangeNotification";

const unsigned short BrowserReloadShortcutDefaultKeyCode = 96; // F5

static NSString * const kReloadKeyCodeKey = @"BrowserReloadShortcutKeyCode";
static NSString * const kReloadModifierFlagsKey = @"BrowserReloadShortcutModifierFlags";
static NSString * const kReloadEnabledKey = @"BrowserReloadShortcutEnabled";
static NSString * const kReloadGlyphKey = @"BrowserReloadShortcutGlyph";

@implementation BrowserKeyboardPreferences

+ (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserKeyboardPreferencesDidChangeNotification
                                                        object:nil];
}

+ (NSEventModifierFlags)normalizedModifierFlags:(NSEventModifierFlags)flags {
    return flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                    NSEventModifierFlagControl | NSEventModifierFlagShift);
}

+ (unsigned short)reloadShortcutKeyCode {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kReloadKeyCodeKey] == nil) {
        return BrowserReloadShortcutDefaultKeyCode;
    }
    return (unsigned short)[defaults integerForKey:kReloadKeyCodeKey];
}

+ (NSEventModifierFlags)reloadShortcutModifierFlags {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kReloadModifierFlagsKey] == nil) {
        return 0;
    }
    return [self normalizedModifierFlags:(NSEventModifierFlags)[defaults integerForKey:kReloadModifierFlagsKey]];
}

+ (nullable NSString *)storedGlyph {
    NSString *glyph = [NSUserDefaults.standardUserDefaults stringForKey:kReloadGlyphKey];
    return glyph.length > 0 ? glyph : nil;
}

+ (void)setReloadShortcutKeyCode:(unsigned short)keyCode
                   modifierFlags:(NSEventModifierFlags)modifierFlags {
    [self setReloadShortcutKeyCode:keyCode modifierFlags:modifierFlags glyph:nil];
}

+ (void)setReloadShortcutKeyCode:(unsigned short)keyCode
                   modifierFlags:(NSEventModifierFlags)modifierFlags
                           glyph:(nullable NSString *)glyph {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:keyCode forKey:kReloadKeyCodeKey];
    [defaults setInteger:(NSInteger)[self normalizedModifierFlags:modifierFlags]
                  forKey:kReloadModifierFlagsKey];
    if (glyph.length > 0) {
        [defaults setObject:glyph forKey:kReloadGlyphKey];
    } else {
        [defaults removeObjectForKey:kReloadGlyphKey];
    }
    [self notifyChanged];
}

+ (void)setReloadShortcutFromEvent:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers ?: @"";
    NSString *glyph = nil;
    if (chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'a' && c <= 'z') {
            glyph = chars.uppercaseString;
        } else if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
            glyph = chars.uppercaseString;
        }
    }
    [self setReloadShortcutKeyCode:event.keyCode
                     modifierFlags:event.modifierFlags
                             glyph:glyph];
}

+ (void)resetReloadShortcutToDefault {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:kReloadKeyCodeKey];
    [defaults removeObjectForKey:kReloadModifierFlagsKey];
    [defaults removeObjectForKey:kReloadGlyphKey];
    [self notifyChanged];
}

+ (BOOL)reloadShortcutEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kReloadEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kReloadEnabledKey];
}

+ (void)setReloadShortcutEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kReloadEnabledKey];
    [self notifyChanged];
}

+ (BOOL)eventMatchesReloadShortcut:(NSEvent *)event {
    if (![self reloadShortcutEnabled]) {
        return NO;
    }
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    NSEventModifierFlags mods = [self normalizedModifierFlags:event.modifierFlags];
    return event.keyCode == [self reloadShortcutKeyCode]
        && mods == [self reloadShortcutModifierFlags];
}

+ (NSString *)displayNameForKeyCode:(unsigned short)keyCode glyph:(nullable NSString *)glyph {
    static NSDictionary<NSNumber *, NSString *> *namedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        namedKeys = @{
            @122: @"F1", @120: @"F2", @99: @"F3", @118: @"F4",
            @96: @"F5", @97: @"F6", @98: @"F7", @100: @"F8",
            @101: @"F9", @109: @"F10", @103: @"F11", @111: @"F12",
            @53: @"Esc", @36: @"↩", @48: @"⇥", @49: @"空格",
            @51: @"⌫", @117: @"⌦",
            @123: @"←", @124: @"→", @125: @"↓", @126: @"↑",
        };
    });
    NSString *named = namedKeys[@(keyCode)];
    if (named) {
        return named;
    }
    if (glyph.length > 0) {
        return glyph;
    }
    return [NSString stringWithFormat:@"键%u", keyCode];
}

+ (NSString *)displayStringForKeyCode:(unsigned short)keyCode
                        modifierFlags:(NSEventModifierFlags)modifierFlags {
    return [self displayStringForKeyCode:keyCode modifierFlags:modifierFlags glyph:nil];
}

+ (NSString *)displayStringForKeyCode:(unsigned short)keyCode
                        modifierFlags:(NSEventModifierFlags)modifierFlags
                                glyph:(nullable NSString *)glyph {
    NSMutableString *result = [NSMutableString string];
    NSEventModifierFlags mods = [self normalizedModifierFlags:modifierFlags];
    if (mods & NSEventModifierFlagControl) {
        [result appendString:@"⌃"];
    }
    if (mods & NSEventModifierFlagOption) {
        [result appendString:@"⌥"];
    }
    if (mods & NSEventModifierFlagShift) {
        [result appendString:@"⇧"];
    }
    if (mods & NSEventModifierFlagCommand) {
        [result appendString:@"⌘"];
    }
    [result appendString:[self displayNameForKeyCode:keyCode glyph:glyph]];
    return [result copy];
}

+ (NSString *)displayStringForReloadShortcut {
    return [self displayStringForKeyCode:[self reloadShortcutKeyCode]
                           modifierFlags:[self reloadShortcutModifierFlags]
                                   glyph:[self storedGlyph]];
}

@end
