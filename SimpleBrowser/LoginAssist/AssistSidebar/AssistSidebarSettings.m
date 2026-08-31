#import "AssistSidebarSettings.h"

static NSString * const kAssistSidebarWidthKey = @"MeoLoginAssistSidebarWidth";
static NSString * const kAssistSidebarDetailHeightKey = @"MeoLoginAssistSidebarDetailHeight";

static const CGFloat kDefaultWidth = 360.0;
static const CGFloat kMinWidth = 320.0;
static const CGFloat kMaxWidth = 560.0;

static const CGFloat kDefaultDetailHeight = 380.0;
static const CGFloat kMinDetailHeight = 180.0;
static const CGFloat kMaxDetailHeight = 520.0;

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

- (CGFloat)detailHeight {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kAssistSidebarDetailHeightKey] == nil) {
        return kDefaultDetailHeight;
    }
    CGFloat height = [defaults doubleForKey:kAssistSidebarDetailHeightKey];
    return MIN(kMaxDetailHeight, MAX(kMinDetailHeight, height));
}

- (void)setDetailHeight:(CGFloat)detailHeight {
    CGFloat height = MIN(kMaxDetailHeight, MAX(kMinDetailHeight, detailHeight));
    [NSUserDefaults.standardUserDefaults setDouble:height forKey:kAssistSidebarDetailHeightKey];
}

@end
