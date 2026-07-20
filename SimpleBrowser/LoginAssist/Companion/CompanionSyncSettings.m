#import "CompanionSyncSettings.h"

static NSString * const kSyncEnabledKey = @"meo.sync.enabled";
static NSString * const kSyncShortcutsKey = @"meo.sync.shortcuts";
static NSString * const kSyncHistoryKey = @"meo.sync.history";
static NSString * const kSyncBookmarksKey = @"meo.sync.bookmarks";
static NSString * const kSyncLastAtKey = @"meo.sync.lastAt";
static NSString * const kSyncEpochKey = @"meo.sync.epoch";

@implementation CompanionSyncSettings

+ (instancetype)sharedSettings {
    static CompanionSyncSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSUserDefaults *)defaults {
    return NSUserDefaults.standardUserDefaults;
}

- (BOOL)syncEnabled {
    // 未写过键时默认开：配对设备推快捷方式即可同步（与 mirror 默认开一致）
    if (![self.defaults objectForKey:kSyncEnabledKey]) return YES;
    return [self.defaults boolForKey:kSyncEnabledKey];
}
- (void)setSyncEnabled:(BOOL)syncEnabled {
    [self.defaults setBool:syncEnabled forKey:kSyncEnabledKey];
}

- (BOOL)syncShortcuts {
    if (![self.defaults objectForKey:kSyncShortcutsKey]) return YES;
    return [self.defaults boolForKey:kSyncShortcutsKey];
}
- (void)setSyncShortcuts:(BOOL)syncShortcuts {
    [self.defaults setBool:syncShortcuts forKey:kSyncShortcutsKey];
}

- (BOOL)syncHistory {
    return [self.defaults boolForKey:kSyncHistoryKey];
}
- (void)setSyncHistory:(BOOL)syncHistory {
    [self.defaults setBool:syncHistory forKey:kSyncHistoryKey];
}

- (BOOL)syncBookmarks {
    return [self.defaults boolForKey:kSyncBookmarksKey];
}
- (void)setSyncBookmarks:(BOOL)syncBookmarks {
    [self.defaults setBool:syncBookmarks forKey:kSyncBookmarksKey];
}

- (NSTimeInterval)lastSyncAt {
    return [self.defaults doubleForKey:kSyncLastAtKey];
}
- (void)setLastSyncAt:(NSTimeInterval)lastSyncAt {
    [self.defaults setDouble:lastSyncAt forKey:kSyncLastAtKey];
}

- (long long)epoch {
    return [self.defaults integerForKey:kSyncEpochKey];
}
- (void)setEpoch:(long long)epoch {
    [self.defaults setInteger:(NSInteger)epoch forKey:kSyncEpochKey];
}

- (long long)bumpEpoch {
    long long next = self.epoch + 1;
    self.epoch = next;
    return next;
}

@end
