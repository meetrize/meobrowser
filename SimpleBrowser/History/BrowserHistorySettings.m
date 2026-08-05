#import "BrowserHistorySettings.h"

static NSString * const kHistorySidebarWidthKey = @"MeoBrowserHistorySidebarWidth";
static const CGFloat kDefaultWidth = 380.0;
static const CGFloat kMinWidth = 320.0;
static const CGFloat kMaxWidth = 560.0;

@implementation BrowserHistorySettings

+ (instancetype)sharedSettings {
    static BrowserHistorySettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (CGFloat)sidebarWidth {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kHistorySidebarWidthKey] == nil) {
        return kDefaultWidth;
    }
    CGFloat width = [defaults doubleForKey:kHistorySidebarWidthKey];
    return MIN(kMaxWidth, MAX(kMinWidth, width));
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat width = MIN(kMaxWidth, MAX(kMinWidth, sidebarWidth));
    [NSUserDefaults.standardUserDefaults setDouble:width forKey:kHistorySidebarWidthKey];
}

@end
