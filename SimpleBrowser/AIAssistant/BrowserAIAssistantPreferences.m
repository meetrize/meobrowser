#import "BrowserAIAssistantPreferences.h"
#import "AIBridgeRegistry.h"

NSNotificationName const BrowserAIAssistantPreferencesDidChangeNotification =
    @"BrowserAIAssistantPreferencesDidChangeNotification";

static NSString * const kWidthKey = @"AIAssistant.sidebarWidth";
static NSString * const kModelKey = @"AIAssistant.lastModelId";
static NSString * const kProviderKey = @"AIAssistant.lastProviderId";
static const CGFloat kDefaultWidth = 380.0;
static const CGFloat kMinWidth = 300.0;
/// 仅作持久化硬顶；运行时侧栏还会按窗口宽度 80% 再裁
static const CGFloat kMaxWidth = 4000.0;

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
        NSString *pid = [ud stringForKey:kProviderKey];
        if (pid.length == 0) {
            pid = [AIBridgeRegistry providerIdFromModelId:_lastModelId] ?: @"deepseek";
        }
        _lastProviderId = pid;
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
    NSString *pid = [AIBridgeRegistry providerIdFromModelId:m];
    if (pid.length) {
        _lastProviderId = pid;
        [NSUserDefaults.standardUserDefaults setObject:pid forKey:kProviderKey];
    }
    [self notify];
}

- (void)setLastProviderId:(NSString *)lastProviderId {
    NSString *p = lastProviderId.length ? lastProviderId : @"deepseek";
    if ([_lastProviderId isEqualToString:p]) {
        return;
    }
    _lastProviderId = [p copy];
    [NSUserDefaults.standardUserDefaults setObject:_lastProviderId forKey:kProviderKey];
    [self notify];
}

@end
