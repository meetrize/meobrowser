#import "SyncMerger.h"
#import "SyncRecord.h"

static const long long kTombstoneTTLSeconds = 30LL * 24LL * 60LL * 60LL;

@implementation SyncMerger

+ (BOOL)incomingWins:(SyncRecord *)incoming local:(SyncRecord *)local {
    if (!incoming) {
        return NO;
    }
    if (!local) {
        return YES;
    }
    if (incoming.updatedAt > local.updatedAt) {
        return YES;
    }
    if (incoming.updatedAt < local.updatedAt) {
        return NO;
    }
    NSString *idIn = incoming.deviceId ?: @"";
    NSString *idLo = local.deviceId ?: @"";
    return [idIn compare:idLo] == NSOrderedDescending;
}

+ (NSArray<SyncRecord *> *)mergeIncoming:(NSArray<SyncRecord *> *)incoming
                              intoLocal:(NSArray<SyncRecord *> *)local {
    NSMutableDictionary<NSString *, SyncRecord *> *map = [NSMutableDictionary dictionary];
    for (SyncRecord *rec in local) {
        if (rec.recordID.length == 0) {
            continue;
        }
        map[rec.recordID] = rec;
    }
    for (SyncRecord *inc in incoming) {
        if (inc.recordID.length == 0) {
            continue;
        }
        SyncRecord *existing = map[inc.recordID];
        if ([self incomingWins:inc local:existing]) {
            map[inc.recordID] = [inc copy];
        }
    }
    return map.allValues;
}

+ (NSArray<SyncRecord *> *)purgeExpiredTombstones:(NSArray<SyncRecord *> *)records
                                              now:(long long)nowUnix {
    NSMutableArray<SyncRecord *> *kept = [NSMutableArray array];
    for (SyncRecord *rec in records) {
        if (rec.deleted && rec.updatedAt > 0 && (nowUnix - rec.updatedAt) > kTombstoneTTLSeconds) {
            continue;
        }
        [kept addObject:rec];
    }
    return kept;
}

@end
