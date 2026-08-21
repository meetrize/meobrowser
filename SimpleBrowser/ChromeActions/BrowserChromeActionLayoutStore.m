#import "BrowserChromeActionLayoutStore.h"
#import "BrowserChromeActionItem.h"

NSNotificationName const BrowserChromeActionLayoutDidChangeNotification =
    @"BrowserChromeActionLayoutDidChangeNotification";

static NSString * const kOrderDefaultsKey = @"BrowserChromeActionOrder";
static NSString * const kHiddenDefaultsKey = @"BrowserChromeActionHidden";

@implementation BrowserChromeActionLayoutStore

+ (NSArray<NSString *> *)defaultOrderedCustomActionIDs {
    return @[
        BrowserChromeActionAfkModeID,
        BrowserChromeActionTransparentModeID,
        BrowserChromeActionCompactModeID,
        BrowserChromeActionAlwaysOnTopID,
        BrowserChromeActionAutoScrollID,
        BrowserChromeActionScrollSpeedID,
        BrowserChromeActionWindowLayoutID,
    ];
}

+ (NSSet<NSString *> *)knownCustomActionIDSet {
    return [NSSet setWithArray:[self defaultOrderedCustomActionIDs]];
}

+ (NSArray<NSString *> *)sanitizedOrderedIDsFromSaved:(nullable NSArray *)saved {
    NSSet<NSString *> *known = [self knownCustomActionIDSet];
    NSMutableArray<NSString *> *ordered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    if ([saved isKindOfClass:[NSArray class]]) {
        for (id obj in saved) {
            if (![obj isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *itemID = (NSString *)obj;
            if (itemID.length == 0 || ![known containsObject:itemID] || [seen containsObject:itemID]) {
                continue;
            }
            [ordered addObject:itemID];
            [seen addObject:itemID];
        }
    }

    for (NSString *itemID in [self defaultOrderedCustomActionIDs]) {
        if (![seen containsObject:itemID]) {
            [ordered addObject:itemID];
            [seen addObject:itemID];
        }
    }
    return [ordered copy];
}

+ (NSArray<NSString *> *)orderedCustomActionIDs {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kOrderDefaultsKey];
    return [self sanitizedOrderedIDsFromSaved:saved];
}

+ (void)setOrderedCustomActionIDs:(NSArray<NSString *> *)orderedIDs {
    NSArray<NSString *> *sanitized = [self sanitizedOrderedIDsFromSaved:orderedIDs];
    [[NSUserDefaults standardUserDefaults] setObject:sanitized forKey:kOrderDefaultsKey];
    [self postLayoutDidChange];
}

+ (NSSet<NSString *> *)hiddenActionIDSet {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kHiddenDefaultsKey];
    NSSet<NSString *> *known = [self knownCustomActionIDSet];
    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (id obj in saved) {
            if (![obj isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *itemID = (NSString *)obj;
            if (itemID.length > 0 && [known containsObject:itemID]) {
                [hidden addObject:itemID];
            }
        }
    }
    return [hidden copy];
}

+ (BOOL)isActionIDHidden:(NSString *)itemID {
    if (itemID.length == 0) {
        return NO;
    }
    return [[self hiddenActionIDSet] containsObject:itemID];
}

+ (void)setActionID:(NSString *)itemID hidden:(BOOL)hidden {
    if (itemID.length == 0 || ![[self knownCustomActionIDSet] containsObject:itemID]) {
        return;
    }
    NSMutableSet<NSString *> *set = [[self hiddenActionIDSet] mutableCopy];
    if (hidden) {
        [set addObject:itemID];
    } else {
        [set removeObject:itemID];
    }
    NSArray<NSString *> *ids = [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kHiddenDefaultsKey];
    [self postLayoutDidChange];
}

+ (NSArray<NSString *> *)visibleCustomActionIDs {
    NSSet<NSString *> *hidden = [self hiddenActionIDSet];
    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    for (NSString *itemID in [self orderedCustomActionIDs]) {
        if (![hidden containsObject:itemID]) {
            [visible addObject:itemID];
        }
    }
    return [visible copy];
}

+ (NSArray<NSString *> *)orderedIDsByReplacingVisibleSubsequence:(NSArray<NSString *> *)visibleIDs {
    NSArray<NSString *> *incoming = [visibleIDs isKindOfClass:[NSArray class]] ? visibleIDs : @[];
    NSSet<NSString *> *known = [self knownCustomActionIDSet];
    NSMutableArray<NSString *> *cleanVisible = [NSMutableArray array];
    NSMutableSet<NSString *> *seenVisible = [NSMutableSet set];
    for (id obj in incoming) {
        if (![obj isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *itemID = (NSString *)obj;
        if (itemID.length == 0 || ![known containsObject:itemID] || [seenVisible containsObject:itemID]) {
            continue;
        }
        [cleanVisible addObject:itemID];
        [seenVisible addObject:itemID];
    }

    NSSet<NSString *> *hidden = [self hiddenActionIDSet];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSUInteger visibleCursor = 0;
    for (NSString *itemID in [self orderedCustomActionIDs]) {
        if ([hidden containsObject:itemID]) {
            [result addObject:itemID];
            continue;
        }
        if (visibleCursor < cleanVisible.count) {
            [result addObject:cleanVisible[visibleCursor]];
            visibleCursor += 1;
        }
    }
    while (visibleCursor < cleanVisible.count) {
        NSString *itemID = cleanVisible[visibleCursor];
        if (![result containsObject:itemID]) {
            [result addObject:itemID];
        }
        visibleCursor += 1;
    }
    return [self sanitizedOrderedIDsFromSaved:result];
}

+ (void)postLayoutDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserChromeActionLayoutDidChangeNotification
                                                        object:nil];
}

@end
