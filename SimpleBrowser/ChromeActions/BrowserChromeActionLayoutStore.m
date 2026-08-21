#import "BrowserChromeActionLayoutStore.h"
#import "BrowserChromeActionItem.h"

NSNotificationName const BrowserChromeActionLayoutDidChangeNotification =
    @"BrowserChromeActionLayoutDidChangeNotification";

static NSString * const kOrderDefaultsKey = @"BrowserChromeActionOrder";
static NSString * const kHiddenDefaultsKey = @"BrowserChromeActionHidden";
static NSString * const kSeededAddressBarToolsHiddenKey = @"BrowserChromeActionSeededAddressBarToolsHidden";
static NSString * const kMigratedFromAddressBarKey = @"BrowserChromeActionMigratedFromAddressBar";
static NSString * const kLegacyAddressBarOrderKey = @"BrowserAddressBarActionOrder";
static NSString * const kLegacyAddressBarHiddenKey = @"BrowserAddressBarActionHidden";

@implementation BrowserChromeActionLayoutStore

+ (NSArray<NSString *> *)defaultOrderedCustomActionIDs {
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithArray:@[
        BrowserChromeActionAfkModeID,
        BrowserChromeActionTransparentModeID,
        BrowserChromeActionCompactModeID,
        BrowserChromeActionAlwaysOnTopID,
        BrowserChromeActionAutoScrollID,
        BrowserChromeActionScrollSpeedID,
        BrowserChromeActionWindowLayoutID,
        BrowserChromeActionExtensionID,
    ]];
    [ids addObjectsFromArray:[BrowserChromeActionItem addressBarMigratedActionIDs]];
    return [ids copy];
}

+ (NSArray<NSString *> *)defaultHiddenCustomActionIDs {
    return [BrowserChromeActionItem addressBarMigratedActionIDs];
}

+ (NSSet<NSString *> *)knownCustomActionIDSet {
    return [NSSet setWithArray:[self defaultOrderedCustomActionIDs]];
}

+ (void)seedAddressBarToolsHiddenIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kSeededAddressBarToolsHiddenKey]) {
        return;
    }

    NSMutableSet<NSString *> *hidden = [[self rawHiddenActionIDSet] mutableCopy];
    [hidden addObjectsFromArray:[self defaultHiddenCustomActionIDs]];
    NSArray<NSString *> *ids = [[hidden allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [defaults setObject:ids forKey:kHiddenDefaultsKey];
    [defaults setBool:YES forKey:kSeededAddressBarToolsHiddenKey];
}

+ (NSSet<NSString *> *)rawHiddenActionIDSet {
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
    [self migrateFromAddressBarPreferencesIfNeeded];
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kOrderDefaultsKey];
    return [self sanitizedOrderedIDsFromSaved:saved];
}

+ (void)setOrderedCustomActionIDs:(NSArray<NSString *> *)orderedIDs {
    [self migrateFromAddressBarPreferencesIfNeeded];
    NSArray<NSString *> *sanitized = [self sanitizedOrderedIDsFromSaved:orderedIDs];
    [[NSUserDefaults standardUserDefaults] setObject:sanitized forKey:kOrderDefaultsKey];
    [self postLayoutDidChange];
}

+ (NSSet<NSString *> *)hiddenActionIDSet {
    [self migrateFromAddressBarPreferencesIfNeeded];
    return [self rawHiddenActionIDSet];
}

+ (void)migrateFromAddressBarPreferencesIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kMigratedFromAddressBarKey]) {
        [self seedAddressBarToolsHiddenIfNeeded];
        return;
    }

    [self seedAddressBarToolsHiddenIfNeeded];

    NSArray *legacyOrder = [defaults arrayForKey:kLegacyAddressBarOrderKey];
    NSArray *legacyHidden = [defaults arrayForKey:kLegacyAddressBarHiddenKey];
    BOOL hadLegacy = ([legacyOrder isKindOfClass:[NSArray class]] || [legacyHidden isKindOfClass:[NSArray class]]);

    NSSet<NSString *> *migratedIDs = [NSSet setWithArray:[BrowserChromeActionItem addressBarMigratedActionIDs]];
    NSArray<NSString *> *currentOrder = [self sanitizedOrderedIDsFromSaved:[defaults arrayForKey:kOrderDefaultsKey]];

    NSMutableArray<NSString *> *windowPart = [NSMutableArray array];
    NSMutableArray<NSString *> *toolPart = [NSMutableArray array];
    for (NSString *itemID in currentOrder) {
        if ([migratedIDs containsObject:itemID]) {
            [toolPart addObject:itemID];
        } else {
            [windowPart addObject:itemID];
        }
    }

    if ([legacyOrder isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *reorderedTools = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (id obj in legacyOrder) {
            if (![obj isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *itemID = (NSString *)obj;
            if (![migratedIDs containsObject:itemID] || [seen containsObject:itemID]) {
                continue;
            }
            [reorderedTools addObject:itemID];
            [seen addObject:itemID];
        }
        for (NSString *itemID in toolPart) {
            if (![seen containsObject:itemID]) {
                [reorderedTools addObject:itemID];
                [seen addObject:itemID];
            }
        }
        toolPart = reorderedTools;
    }

    NSMutableArray<NSString *> *mergedOrder = [windowPart mutableCopy];
    [mergedOrder addObjectsFromArray:toolPart];
    [defaults setObject:[self sanitizedOrderedIDsFromSaved:mergedOrder] forKey:kOrderDefaultsKey];

    // 仅当旧 Hidden 键存在时迁移可见性：曾在地址栏显示的项从 Chrome hidden 移除。
    if (hadLegacy && [legacyHidden isKindOfClass:[NSArray class]]) {
        NSSet<NSString *> *legacyHiddenSet = [NSSet setWithArray:legacyHidden];
        NSMutableSet<NSString *> *hidden = [[self rawHiddenActionIDSet] mutableCopy];
        for (NSString *itemID in migratedIDs) {
            if ([legacyHiddenSet containsObject:itemID]) {
                [hidden addObject:itemID];
            } else {
                [hidden removeObject:itemID];
            }
        }
        NSArray<NSString *> *ids = [[hidden allObjects] sortedArrayUsingSelector:@selector(compare:)];
        [defaults setObject:ids forKey:kHiddenDefaultsKey];
    }

    [defaults setBool:YES forKey:kMigratedFromAddressBarKey];
}

+ (BOOL)isActionIDHidden:(NSString *)itemID {
    if (itemID.length == 0) {
        return NO;
    }
    return [[self hiddenActionIDSet] containsObject:itemID];
}

+ (void)setActionID:(NSString *)itemID hidden:(BOOL)hidden {
    [self migrateFromAddressBarPreferencesIfNeeded];
    if (itemID.length == 0 || ![[self knownCustomActionIDSet] containsObject:itemID]) {
        return;
    }
    NSMutableSet<NSString *> *set = [[self rawHiddenActionIDSet] mutableCopy];
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
