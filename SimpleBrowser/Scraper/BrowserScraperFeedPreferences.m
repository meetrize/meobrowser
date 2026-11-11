#import "BrowserScraperFeedPreferences.h"

NSNotificationName const BrowserScraperFeedPreferencesDidChangeNotification =
    @"BrowserScraperFeedPreferencesDidChangeNotification";

static NSString * const kEnabledKey = @"BrowserScraperFeed.enabled";
static NSString * const kPortKey = @"BrowserScraperFeed.port";
static const NSInteger kDefaultPort = 3922;

@implementation BrowserScraperFeedPreferences

+ (BrowserScraperFeedPreferences *)sharedPreferences {
    static BrowserScraperFeedPreferences *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[BrowserScraperFeedPreferences alloc] init];
    });
    return prefs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        if ([ud objectForKey:kEnabledKey] != nil) {
            _enabled = [ud boolForKey:kEnabledKey];
        } else {
            _enabled = YES;
        }
        NSInteger port = [ud integerForKey:kPortKey];
        _port = (port > 0 && port <= 65535) ? port : kDefaultPort;
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BrowserScraperFeedPreferencesDidChangeNotification
                      object:self];
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) {
        return;
    }
    _enabled = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kEnabledKey];
    [self notify];
}

- (void)setPort:(NSInteger)port {
    if (port < 1 || port > 65535) {
        port = kDefaultPort;
    }
    if (_port == port) {
        return;
    }
    _port = port;
    [NSUserDefaults.standardUserDefaults setInteger:port forKey:kPortKey];
    [self notify];
}

@end
