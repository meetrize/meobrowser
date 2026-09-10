#import "BrowserScraperSettings.h"

static NSString * const kScraperSidebarWidthKey = @"MeoBrowserScraperSidebarWidth";
static NSString * const kScraperMaxRetainedRunsKey = @"MeoBrowserScraperMaxRetainedRuns";

@implementation BrowserScraperSettings

+ (instancetype)sharedSettings {
    static BrowserScraperSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (CGFloat)sidebarWidth {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kScraperSidebarWidthKey] == nil) {
        return 400.0;
    }
    CGFloat width = [defaults doubleForKey:kScraperSidebarWidthKey];
    if (width < 320.0) width = 320.0;
    if (width > 2400.0) width = 2400.0;
    return width;
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat width = sidebarWidth;
    if (width < 320.0) width = 320.0;
    if (width > 2400.0) width = 2400.0;
    [NSUserDefaults.standardUserDefaults setDouble:width forKey:kScraperSidebarWidthKey];
}

- (NSInteger)maxRetainedRuns {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kScraperMaxRetainedRunsKey] == nil) {
        return 20;
    }
    return MAX(1, [defaults integerForKey:kScraperMaxRetainedRunsKey]);
}

- (void)setMaxRetainedRuns:(NSInteger)maxRetainedRuns {
    [NSUserDefaults.standardUserDefaults setInteger:MAX(1, maxRetainedRuns) forKey:kScraperMaxRetainedRunsKey];
}

@end
