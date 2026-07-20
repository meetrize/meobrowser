#import "CompanionBrowseSyncStore.h"

@implementation CompanionBrowseSyncStore

+ (instancetype)sharedStore {
    static CompanionBrowseSyncStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSString *)keyForKind:(NSString *)kind {
    return [NSString stringWithFormat:@"meo.sync.browse.%@", kind];
}

- (BOOL)incomingWins:(NSDictionary *)incoming local:(NSDictionary *)local {
    long long iu = [incoming[@"updatedAt"] longLongValue];
    long long lu = [local[@"updatedAt"] longLongValue];
    if (iu > lu) return YES;
    if (iu < lu) return NO;
    NSString *idIn = [incoming[@"deviceId"] description] ?: @"";
    NSString *idLo = [local[@"deviceId"] description] ?: @"";
    return [idIn compare:idLo] == NSOrderedDescending;
}

- (void)mergeRecords:(NSArray<NSDictionary *> *)records kind:(NSString *)kind {
    if (![kind isEqualToString:@"history"] && ![kind isEqualToString:@"bookmark"]) return;
    NSString *key = [self keyForKind:kind];
    NSArray *existing = [NSUserDefaults.standardUserDefaults arrayForKey:key] ?: @[];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (id e in existing) {
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSString *rid = e[@"id"];
        if ([rid isKindOfClass:[NSString class]]) map[rid] = e;
    }
    for (NSDictionary *incoming in records) {
        if (![incoming isKindOfClass:[NSDictionary class]]) continue;
        NSString *rid = incoming[@"id"];
        if (![rid isKindOfClass:[NSString class]] || rid.length == 0) continue;
        NSDictionary *local = map[rid];
        if (!local || [self incomingWins:incoming local:local]) {
            map[rid] = incoming;
        }
    }
    [NSUserDefaults.standardUserDefaults setObject:map.allValues forKey:key];
}

- (NSArray<NSDictionary *> *)exportRecordsForKind:(NSString *)kind {
    NSArray *existing = [NSUserDefaults.standardUserDefaults arrayForKey:[self keyForKind:kind]] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in existing) {
        if ([e isKindOfClass:[NSDictionary class]]) [out addObject:e];
    }
    return out;
}

@end
