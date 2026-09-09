#import "BrowserUserActivityMonitor.h"
#import <AppKit/AppKit.h>

static NSString * const kMeoUserActiveSecondsKey = @"MeoBrowserUserActiveSeconds";
static NSString * const kMeoBackgroundIdleSecondsKey = @"MeoBrowserBackgroundIdleSeconds";

static const NSTimeInterval kDefaultActiveWindowSeconds = 90.0;
static const NSTimeInterval kDefaultBackgroundIdleSeconds = 30.0;

@interface BrowserUserActivityMonitor ()
@property (nonatomic, assign) NSTimeInterval lastInputTimestamp;
@property (nonatomic, assign) NSTimeInterval lastBecameInactiveTimestamp;
@end

@implementation BrowserUserActivityMonitor

+ (instancetype)sharedMonitor {
    static BrowserUserActivityMonitor *monitor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        monitor = [[BrowserUserActivityMonitor alloc] init];
    });
    return monitor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastInputTimestamp = [NSDate date].timeIntervalSince1970;
        _lastBecameInactiveTimestamp = 0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTimeInterval)activeWindowSeconds {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kMeoUserActiveSecondsKey];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        NSTimeInterval s = [value doubleValue];
        if (s >= 15.0) {
            return s;
        }
    }
    return kDefaultActiveWindowSeconds;
}

- (NSTimeInterval)backgroundIdleSeconds {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kMeoBackgroundIdleSecondsKey];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        NSTimeInterval s = [value doubleValue];
        if (s >= 5.0) {
            return s;
        }
    }
    return kDefaultBackgroundIdleSeconds;
}

- (void)noteUserInput {
    self.lastInputTimestamp = [NSDate date].timeIntervalSince1970;
}

- (NSTimeInterval)secondsSinceLastInput {
    return [NSDate date].timeIntervalSince1970 - self.lastInputTimestamp;
}

- (BOOL)isUserActivelyBrowsing {
    if (!NSApp.isActive) {
        return NO;
    }
    return self.secondsSinceLastInput < self.activeWindowSeconds;
}

- (BOOL)isIdleForReclaim {
    if (self.isUserActivelyBrowsing) {
        return NO;
    }
    // 前台但长时间无操作 → 可回收。
    if (NSApp.isActive) {
        return self.secondsSinceLastInput >= self.activeWindowSeconds;
    }
    // 已退到后台：再等一小段，避免点一下别的 App 又立刻杀页。
    if (self.lastBecameInactiveTimestamp <= 0) {
        return YES;
    }
    NSTimeInterval sinceInactive = [NSDate date].timeIntervalSince1970 - self.lastBecameInactiveTimestamp;
    return sinceInactive >= self.backgroundIdleSeconds;
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    // 回到前台算一次交互，给用户操作窗口。
    [self noteUserInput];
    self.lastBecameInactiveTimestamp = 0;
}

- (void)appDidResignActive:(NSNotification *)notification {
    (void)notification;
    self.lastBecameInactiveTimestamp = [NSDate date].timeIntervalSince1970;
}

@end
