#import "BrowserAIAssistantPreferences.h"

NSNotificationName const BrowserAIAssistantPreferencesDidChangeNotification =
    @"BrowserAIAssistantPreferencesDidChangeNotification";

static NSString * const kWidthKey = @"AIAssistant.sidebarWidth";
static NSString * const kModelKey = @"AIAssistant.lastModelId";
static const CGFloat kDefaultWidth = 360.0;
static const CGFloat kMinWidth = 280.0;
static const CGFloat kMaxWidth = 560.0;

@implementation BrowserAIAssistantPreferences

+ (BrowserAIAssistantPreferences *)sharedPreferences {
    static BrowserAIAssistantPreferences *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[BrowserAIAssistantPreferences alloc] init];
    });
    return prefs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        CGFloat w = [ud doubleForKey:kWidthKey];
        if (w < kMinWidth || w > kMaxWidth) {
            w = kDefaultWidth;
        }
        _sidebarWidth = w;
        NSString *model = [ud stringForKey:kModelKey];
        _lastModelId = model.length ? model : @"bridge__deepseek";
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserAIAssistantPreferencesDidChangeNotification
                                                        object:self];
}

- (void)setSidebarWidth:(CGFloat)sidebarWidth {
    CGFloat w = sidebarWidth;
    if (w < kMinWidth) w = kMinWidth;
    if (w > kMaxWidth) w = kMaxWidth;
    if (fabs(_sidebarWidth - w) < 0.5) {
        return;
    }
    _sidebarWidth = w;
    [NSUserDefaults.standardUserDefaults setDouble:w forKey:kWidthKey];
    [self notify];
}

- (void)setLastModelId:(NSString *)lastModelId {
    NSString *m = lastModelId.length ? lastModelId : @"bridge__deepseek";
    if ([_lastModelId isEqualToString:m]) {
        return;
    }
    _lastModelId = [m copy];
    [NSUserDefaults.standardUserDefaults setObject:_lastModelId forKey:kModelKey];
    [self notify];
}

@end
