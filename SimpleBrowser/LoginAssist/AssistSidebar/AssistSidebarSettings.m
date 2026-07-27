#import "AssistSidebarSettings.h"

static NSString * const kAssistSidebarWidthKey = @"MeoLoginAssistSidebarWidth";
static const CGFloat kDefaultWidth = 360.0;
static const CGFloat kMinWidth = 320.0;
static const CGFloat kMaxWidth = 560.0;

@implementation AssistSidebarSettings

+ (instancetype)sharedSettings {
    static AssistSidebarSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [[self alloc] init];
    });
    return settings;
}

- (CGFloat)sidebarWidth {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kAssistSidebarWidthKey] == nil) {
        return kDefaultWidth;
    }
    CGFloat width = [defaults doubleForKey:kAssistSidebarWidthKey];
    return MIN(kMaxWidth, MAX(kMinWidth, width));
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat width = MIN(kMaxWidth, MAX(kMinWidth, sidebarWidth));
    [NSUserDefaults.standardUserDefaults setDouble:width forKey:kAssistSidebarWidthKey];
}

@end
