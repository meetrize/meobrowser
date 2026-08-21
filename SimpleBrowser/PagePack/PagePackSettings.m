#import "PagePackSettings.h"

static NSString * const kPagePackEnabledKey = @"MeoPagePackEnabled";
static NSString * const kPagePackSidebarWidthKey = @"MeoPagePackSidebarWidth";

@implementation PagePackSettings

+ (instancetype)sharedSettings {
    static PagePackSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (BOOL)pagePackEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kPagePackEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kPagePackEnabledKey];
}

- (void)setPagePackEnabled:(BOOL)pagePackEnabled {
    [NSUserDefaults.standardUserDefaults setBool:pagePackEnabled forKey:kPagePackEnabledKey];
}

- (CGFloat)sidebarWidth {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kPagePackSidebarWidthKey] == nil) {
        return 400.0;
    }
    CGFloat width = [defaults doubleForKey:kPagePackSidebarWidthKey];
    if (width < 320.0) {
        width = 320.0;
    }
    if (width > 560.0) {
        width = 560.0;
    }
    return width;
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat width = sidebarWidth;
    if (width < 320.0) {
        width = 320.0;
    }
    if (width > 560.0) {
        width = 560.0;
    }
    [NSUserDefaults.standardUserDefaults setDouble:width forKey:kPagePackSidebarWidthKey];
}

@end
