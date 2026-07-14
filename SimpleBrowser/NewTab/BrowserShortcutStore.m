#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"

static NSString * const kShortcutItemsKey = @"shortcutItems";
static NSString * const kShortcutPayloadVersionKey = @"version";
static NSString * const kShortcutPayloadItemsKey = @"shortcuts";
static NSString * const kShortcutItemIDKey = @"id";
static NSString * const kShortcutTitleKey = @"title";
static NSString * const kShortcutURLKey = @"url";
static NSString * const kShortcutIconURLKey = @"iconURL";
static NSString * const kShortcutOrderKey = @"order";
static NSString * const kShortcutKindKey = @"kind";
static NSString * const kShortcutFolderIDKey = @"folderID";
static NSString * const kShortcutKindLinkValue = @"link";
static NSString * const kShortcutKindFolderValue = @"folder";
static const NSInteger kShortcutPayloadVersion = 2;

NSString * const BrowserShortcutAddItemID = @"__launchpad_add__";

@implementation BrowserShortcutStore

+ (NSArray<BrowserShortcutItem *> *)defaultShortcuts {
    return @[
        [BrowserShortcutItem itemWithTitle:@"Google" urlString:@"https://www.google.com" iconURLString:@"" sortOrder:0],
        [BrowserShortcutItem itemWithTitle:@"GitHub" urlString:@"https://github.com" iconURLString:@"" sortOrder:1],
        [BrowserShortcutItem itemWithTitle:@"Wikipedia" urlString:@"https://www.wikipedia.org" iconURLString:@"" sortOrder:2],
        [BrowserShortcutItem itemWithTitle:@"Hacker News" urlString:@"https://news.ycombinator.com" iconURLString:@"" sortOrder:3],
        [BrowserShortcutItem itemWithTitle:@"Apple" urlString:@"https://www.apple.com" iconURLString:@"" sortOrder:4],
        [BrowserShortcutItem itemWithTitle:@"百度" urlString:@"https://www.baidu.com" iconURLString:@"" sortOrder:5],
        [BrowserShortcutItem itemWithTitle:@"哔哩哔哩" urlString:@"https://www.bilibili.com" iconURLString:@"" sortOrder:6],
        [BrowserShortcutItem itemWithTitle:@"知乎" urlString:@"https://www.zhihu.com" iconURLString:@"" sortOrder:7],
    ];
}

+ (NSArray<BrowserShortcutItem *> *)loadShortcuts {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:kShortcutItemsKey];
    NSArray *rawItems = nil;
    BOOL needsRewrite = NO;

    if ([stored isKindOfClass:[NSDictionary class]]) {
        NSDictionary *payload = (NSDictionary *)stored;
        id versionValue = payload[kShortcutPayloadVersionKey];
        NSInteger version = [versionValue respondsToSelector:@selector(integerValue)] ? [versionValue integerValue] : 0;
        if (version < kShortcutPayloadVersion) {
            needsRewrite = YES;
        }
        id shortcutsValue = payload[kShortcutPayloadItemsKey];
        if ([shortcutsValue isKindOfClass:[NSArray class]]) {
            rawItems = shortcutsValue;
        }
    } else if ([stored isKindOfClass:[NSArray class]]) {
        rawItems = stored;
        needsRewrite = YES;
    }

    if (![rawItems isKindOfClass:[NSArray class]] || rawItems.count == 0) {
        NSArray<BrowserShortcutItem *> *defaults = [self defaultShortcuts];
        [self saveShortcuts:defaults];
        return defaults;
    }

    NSMutableArray<BrowserShortcutItem *> *items = [[NSMutableArray alloc] initWithCapacity:rawItems.count];
    for (id entry in rawItems) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        BrowserShortcutItem *item = [self itemFromDictionary:(NSDictionary *)entry];
        if (![self isValidPersistedItem:item]) {
            continue;
        }
        [items addObject:item];
    }

    if (items.count == 0) {
        NSArray<BrowserShortcutItem *> *defaults = [self defaultShortcuts];
        [self saveShortcuts:defaults];
        return defaults;
    }

    [self repairInvariantsInShortcuts:items];
    [self normalizeSortOrdersInShortcuts:items];
    if (needsRewrite) {
        [self saveShortcuts:items];
    }
    return items;
}

+ (void)saveShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    NSMutableArray<BrowserShortcutItem *> *mutableCopy = [shortcuts mutableCopy];
    [self repairInvariantsInShortcuts:mutableCopy];
    [self normalizeSortOrdersInShortcuts:mutableCopy];

    NSMutableArray<NSDictionary *> *payloadItems = [[NSMutableArray alloc] initWithCapacity:mutableCopy.count];
    for (BrowserShortcutItem *item in mutableCopy) {
        [payloadItems addObject:[self dictionaryFromItem:item]];
    }

    NSDictionary *payload = @{
        kShortcutPayloadVersionKey: @(kShortcutPayloadVersion),
        kShortcutPayloadItemsKey: payloadItems,
    };
    [[NSUserDefaults standardUserDefaults] setObject:payload forKey:kShortcutItemsKey];

    if (shortcuts != mutableCopy && [shortcuts isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *mutable = (NSMutableArray *)shortcuts;
        [mutable setArray:mutableCopy];
    }
}

+ (NSArray<BrowserShortcutItem *> *)topLevelShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    NSMutableArray<BrowserShortcutItem *> *topLevel = [[NSMutableArray alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isTopLevel) {
            [topLevel addObject:item];
        }
    }
    [topLevel sortUsingComparator:^NSComparisonResult(BrowserShortcutItem *a, BrowserShortcutItem *b) {
        if (a.sortOrder == b.sortOrder) {
            return [a.title compare:b.title];
        }
        return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
    return topLevel;
}

+ (NSArray<BrowserShortcutItem *> *)childrenOfFolderID:(NSString *)folderID
                                           inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    if (folderID.length == 0) {
        return @[];
    }
    NSMutableArray<BrowserShortcutItem *> *children = [[NSMutableArray alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (!item.isFolder && [item.folderID isEqualToString:folderID]) {
            [children addObject:item];
        }
    }
    [children sortUsingComparator:^NSComparisonResult(BrowserShortcutItem *a, BrowserShortcutItem *b) {
        if (a.sortOrder == b.sortOrder) {
            return [a.title compare:b.title];
        }
        return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
    return children;
}

+ (nullable BrowserShortcutItem *)shortcutWithID:(NSString *)itemID
                                     inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    if (itemID.length == 0) {
        return nil;
    }
    for (BrowserShortcutItem *item in shortcuts) {
        if ([item.itemID isEqualToString:itemID]) {
            return item;
        }
    }
    return nil;
}

+ (BrowserShortcutItem *)addShortcutWithTitle:(NSString *)title
                                    urlString:(NSString *)urlString
                                iconURLString:(NSString *)iconURLString
                                  toShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    NSArray<BrowserShortcutItem *> *topLevel = [self topLevelShortcuts:shortcuts];
    NSInteger order = (NSInteger)topLevel.count;
    BrowserShortcutItem *item = [BrowserShortcutItem itemWithTitle:title
                                                         urlString:urlString
                                                      iconURLString:iconURLString
                                                         sortOrder:order];
    [shortcuts addObject:item];
    [self saveShortcuts:shortcuts];
    return item;
}

+ (void)updateShortcutWithID:(NSString *)itemID
                       title:(NSString *)title
                   urlString:(NSString *)urlString
               iconURLString:(NSString *)iconURLString
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    for (BrowserShortcutItem *item in shortcuts) {
        if ([item.itemID isEqualToString:itemID] && !item.isFolder) {
            item.title = [title copy];
            item.urlString = [urlString copy];
            item.iconURLString = [iconURLString copy];
            break;
        }
    }
    [self saveShortcuts:shortcuts];
}

+ (BOOL)updateIconURLString:(NSString *)iconURLString matchingURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        return NO;
    }
    NSMutableArray<BrowserShortcutItem *> *shortcuts = [[self loadShortcuts] mutableCopy];
    BrowserShortcutItem *item = [self shortcutItemMatchingURLString:urlString inShortcuts:shortcuts];
    if (item == nil || item.isFolder) {
        return NO;
    }
    NSString *icon = iconURLString ?: @"";
    if ([item.iconURLString isEqualToString:icon]) {
        return YES;
    }
    [self updateShortcutWithID:item.itemID
                         title:item.title
                     urlString:item.urlString
                 iconURLString:icon
                   inShortcuts:shortcuts];
    return YES;
}

+ (void)removeShortcutWithID:(NSString *)itemID
                 fromShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    BrowserShortcutItem *item = [self shortcutWithID:itemID inShortcuts:shortcuts];
    if (!item) {
        return;
    }
    if (item.isFolder) {
        [self disbandFolderWithID:itemID inShortcuts:shortcuts];
        return;
    }

    NSString *parentFolderID = item.folderID;
    [shortcuts removeObject:item];
    if (parentFolderID.length > 0) {
        [self removeEmptyFolderWithID:parentFolderID inShortcuts:shortcuts];
    }
    [self saveShortcuts:shortcuts];
}

+ (nullable BrowserShortcutItem *)createFolderWithTitle:(NSString *)title
                                              fromItem:(BrowserShortcutItem *)targetItem
                                          droppingItem:(BrowserShortcutItem *)droppingItem
                                           inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    if (!targetItem || !droppingItem || targetItem == droppingItem) {
        return nil;
    }
    if (targetItem.isFolder || droppingItem.isFolder) {
        return nil;
    }
    // 目标须在顶层；拖入项可以来自另一文件夹（夹外拖合）。
    if (!targetItem.isTopLevel) {
        return nil;
    }
    if (![shortcuts containsObject:targetItem] || ![shortcuts containsObject:droppingItem]) {
        return nil;
    }

    NSString *folderTitle = title.length > 0 ? title : @"文件夹";
    BrowserShortcutItem *folder = [BrowserShortcutItem folderWithTitle:folderTitle sortOrder:targetItem.sortOrder];
    NSInteger insertIndex = [shortcuts indexOfObject:targetItem];
    if (insertIndex == NSNotFound) {
        return nil;
    }

    NSString *previousFolderID = droppingItem.folderID;
    targetItem.folderID = folder.itemID;
    targetItem.sortOrder = 0;
    droppingItem.folderID = folder.itemID;
    droppingItem.sortOrder = 1;

    [shortcuts insertObject:folder atIndex:insertIndex];
    if (previousFolderID.length > 0) {
        [self removeEmptyFolderWithID:previousFolderID inShortcuts:shortcuts];
    }
    [self saveShortcuts:shortcuts];
    return folder;
}

+ (BOOL)moveItem:(BrowserShortcutItem *)item
      intoFolder:(BrowserShortcutItem *)folder
     inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    if (!item || !folder || item.isFolder || !folder.isFolder) {
        return NO;
    }
    if (![shortcuts containsObject:item] || ![shortcuts containsObject:folder]) {
        return NO;
    }
    if ([item.folderID isEqualToString:folder.itemID]) {
        return YES;
    }

    NSString *previousFolderID = item.folderID;
    NSArray<BrowserShortcutItem *> *children = [self childrenOfFolderID:folder.itemID inShortcuts:shortcuts];
    item.folderID = folder.itemID;
    item.sortOrder = (NSInteger)children.count;
    if (previousFolderID.length > 0) {
        [self removeEmptyFolderWithID:previousFolderID inShortcuts:shortcuts];
    }
    [self saveShortcuts:shortcuts];
    return YES;
}

+ (BOOL)moveItem:(BrowserShortcutItem *)item
toTopLevelAtOrder:(NSInteger)order
     inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    if (!item || item.isFolder || ![shortcuts containsObject:item]) {
        return NO;
    }

    NSString *previousFolderID = item.folderID;
    item.folderID = @"";

    NSMutableArray<BrowserShortcutItem *> *topLevel = [[self topLevelShortcuts:shortcuts] mutableCopy];
    [topLevel removeObject:item];
    NSInteger clamped = MAX(0, MIN(order, (NSInteger)topLevel.count));
    [topLevel insertObject:item atIndex:(NSUInteger)clamped];
    [self reorderTopLevelItems:topLevel inShortcuts:shortcuts save:NO];

    if (previousFolderID.length > 0) {
        [self removeEmptyFolderWithID:previousFolderID inShortcuts:shortcuts];
    }
    [self saveShortcuts:shortcuts];
    return YES;
}

+ (void)renameFolderWithID:(NSString *)folderID
                     title:(NSString *)title
               inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    BrowserShortcutItem *folder = [self shortcutWithID:folderID inShortcuts:shortcuts];
    if (!folder || !folder.isFolder) {
        return;
    }
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    folder.title = trimmed;
    [self saveShortcuts:shortcuts];
}

+ (void)disbandFolderWithID:(NSString *)folderID
                inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    BrowserShortcutItem *folder = [self shortcutWithID:folderID inShortcuts:shortcuts];
    if (!folder || !folder.isFolder) {
        return;
    }

    NSArray<BrowserShortcutItem *> *children = [self childrenOfFolderID:folderID inShortcuts:shortcuts];
    NSMutableArray<BrowserShortcutItem *> *topLevel = [[self topLevelShortcuts:shortcuts] mutableCopy];
    NSUInteger folderIndex = [topLevel indexOfObject:folder];
    if (folderIndex == NSNotFound) {
        folderIndex = topLevel.count;
    }
    [topLevel removeObject:folder];
    for (NSInteger i = (NSInteger)children.count - 1; i >= 0; i--) {
        BrowserShortcutItem *child = children[(NSUInteger)i];
        child.folderID = @"";
        [topLevel insertObject:child atIndex:folderIndex];
    }
    [shortcuts removeObject:folder];
    [self reorderTopLevelItems:topLevel inShortcuts:shortcuts save:NO];
    [self saveShortcuts:shortcuts];
}

+ (void)removeFolderWithID:(NSString *)folderID
            deleteChildren:(BOOL)deleteChildren
               inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    if (!deleteChildren) {
        [self disbandFolderWithID:folderID inShortcuts:shortcuts];
        return;
    }

    BrowserShortcutItem *folder = [self shortcutWithID:folderID inShortcuts:shortcuts];
    if (!folder || !folder.isFolder) {
        return;
    }
    NSArray<BrowserShortcutItem *> *children = [self childrenOfFolderID:folderID inShortcuts:shortcuts];
    for (BrowserShortcutItem *child in children) {
        [shortcuts removeObject:child];
    }
    [shortcuts removeObject:folder];
    [self saveShortcuts:shortcuts];
}

+ (void)reorderTopLevelItems:(NSArray<BrowserShortcutItem *> *)orderedTopLevel
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    [self reorderTopLevelItems:orderedTopLevel inShortcuts:shortcuts save:YES];
}

+ (nullable NSString *)normalizedURLStringFromInput:(NSString *)input {
    NSString *normalized = nil;
    if (![self validateURLString:input normalizedURL:&normalized]) {
        return nil;
    }
    return normalized;
}

/// 用于星标/快捷方式匹配：忽略尾斜杠、主机大小写、默认端口与 fragment。
+ (nullable NSString *)bookmarkMatchKeyFromURLString:(NSString *)urlString {
    NSString *normalized = [self normalizedURLStringFromInput:urlString];
    if (!normalized) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:normalized];
    if (!components || components.host.length == 0) {
        return nil;
    }

    components.scheme = components.scheme.lowercaseString;
    components.host = components.host.lowercaseString;
    components.fragment = nil;
    components.user = nil;
    components.password = nil;

    if (components.port != nil) {
        NSInteger port = components.port.integerValue;
        BOOL httpDefault = [components.scheme isEqualToString:@"http"] && port == 80;
        BOOL httpsDefault = [components.scheme isEqualToString:@"https"] && port == 443;
        if (httpDefault || httpsDefault) {
            components.port = nil;
        }
    }

    NSString *path = components.path ?: @"";
    if ([path isEqualToString:@"/"]) {
        components.path = @"";
    } else if (path.length > 1 && [path hasSuffix:@"/"]) {
        components.path = [path substringToIndex:path.length - 1];
    }

    return components.string;
}

+ (nullable BrowserShortcutItem *)shortcutItemMatchingURLString:(NSString *)urlString
                                                    inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    NSString *target = [self bookmarkMatchKeyFromURLString:urlString];
    if (!target) {
        return nil;
    }
    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isFolder) {
            continue;
        }
        NSString *candidate = [self bookmarkMatchKeyFromURLString:item.urlString];
        if (candidate && [candidate isEqualToString:target]) {
            return item;
        }
    }
    return nil;
}

+ (BOOL)isURLStringBookmarked:(NSString *)urlString {
    NSArray<BrowserShortcutItem *> *shortcuts = [self loadShortcuts];
    return [self shortcutItemMatchingURLString:urlString inShortcuts:shortcuts] != nil;
}

+ (BOOL)validateURLString:(NSString *)input normalizedURL:(NSString * _Nullable __autoreleasing * _Nullable)outURL {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    NSString *candidate = trimmed;
    if (![candidate hasPrefix:@"http://"] && ![candidate hasPrefix:@"https://"]) {
        candidate = [@"https://" stringByAppendingString:candidate];
    }

    NSURL *url = [NSURL URLWithString:candidate];
    if (!url) {
        return NO;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    if (url.host.length == 0) {
        return NO;
    }

    if (outURL) {
        *outURL = url.absoluteString;
    }
    return YES;
}

+ (NSInteger)matchScoreForShortcut:(BrowserShortcutItem *)item query:(NSString *)query {
    if (item.isFolder) {
        return NSNotFound;
    }

    NSString *lowercaseQuery = query.lowercaseString;
    if (lowercaseQuery.length == 0) {
        return NSNotFound;
    }

    NSInteger bestScore = -1;
    NSString *title = item.title.lowercaseString;
    if (title.length > 0) {
        if ([title hasPrefix:lowercaseQuery]) {
            bestScore = MAX(bestScore, 100);
        } else if ([title containsString:lowercaseQuery]) {
            bestScore = MAX(bestScore, 80);
        }
    }

    NSURL *url = [NSURL URLWithString:item.urlString];
    NSString *host = url.host.lowercaseString ?: @"";
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    if (host.length > 0) {
        if ([host hasPrefix:lowercaseQuery]) {
            bestScore = MAX(bestScore, 60);
        } else if ([host containsString:lowercaseQuery]) {
            bestScore = MAX(bestScore, 40);
        }
    }

    return bestScore >= 0 ? bestScore : NSNotFound;
}

+ (NSArray<BrowserShortcutItem *> *)shortcutsMatchingQuery:(NSString *)query
                                                     limit:(NSUInteger)limit {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || limit == 0) {
        return @[];
    }

    NSArray<BrowserShortcutItem *> *shortcuts = [self loadShortcuts];
    NSMutableArray<BrowserShortcutItem *> *matches = [[NSMutableArray alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isFolder) {
            continue;
        }
        if ([self matchScoreForShortcut:item query:trimmed] != NSNotFound) {
            [matches addObject:item];
        }
    }

    [matches sortUsingComparator:^NSComparisonResult(BrowserShortcutItem *a, BrowserShortcutItem *b) {
        NSInteger scoreA = [self matchScoreForShortcut:a query:trimmed];
        NSInteger scoreB = [self matchScoreForShortcut:b query:trimmed];
        if (scoreA != scoreB) {
            return scoreA > scoreB ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.sortOrder != b.sortOrder) {
            return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.title compare:b.title];
    }];

    if (matches.count > limit) {
        return [matches subarrayWithRange:NSMakeRange(0, limit)];
    }
    return matches;
}

+ (BOOL)validateIconURLString:(NSString *)input normalizedURL:(NSString * _Nullable __autoreleasing * _Nullable)outURL {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (outURL) {
            *outURL = @"";
        }
        return YES;
    }
    return [self validateURLString:trimmed normalizedURL:outURL];
}

#pragma mark - Internals

+ (BOOL)isValidPersistedItem:(BrowserShortcutItem *)item {
    if (item.title.length == 0) {
        return NO;
    }
    if (item.isFolder) {
        return YES;
    }
    return item.urlString.length > 0;
}

+ (void)repairInvariantsInShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    NSMutableSet<NSString *> *folderIDs = [[NSMutableSet alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isFolder) {
            item.folderID = @"";
            [folderIDs addObject:item.itemID];
        }
    }

    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isFolder) {
            continue;
        }
        if (item.folderID.length > 0 && ![folderIDs containsObject:item.folderID]) {
            item.folderID = @"";
        }
    }

    NSArray<BrowserShortcutItem *> *folders = [shortcuts filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(BrowserShortcutItem *evaluated, NSDictionary *bindings) {
            (void)bindings;
            return evaluated.isFolder;
        }]];
    for (BrowserShortcutItem *folder in folders) {
        [self removeEmptyFolderWithID:folder.itemID inShortcuts:shortcuts];
    }
}

+ (void)removeEmptyFolderWithID:(NSString *)folderID
                    inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    if (folderID.length == 0) {
        return;
    }
    NSArray<BrowserShortcutItem *> *children = [self childrenOfFolderID:folderID inShortcuts:shortcuts];
    if (children.count > 0) {
        return;
    }
    BrowserShortcutItem *folder = [self shortcutWithID:folderID inShortcuts:shortcuts];
    if (folder && folder.isFolder) {
        [shortcuts removeObject:folder];
    }
}

+ (void)normalizeSortOrdersInShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    NSArray<BrowserShortcutItem *> *topLevel = [self topLevelShortcuts:shortcuts];
    for (NSUInteger i = 0; i < topLevel.count; i++) {
        topLevel[i].sortOrder = (NSInteger)i;
    }

    NSMutableSet<NSString *> *folderIDs = [[NSMutableSet alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (item.isFolder) {
            [folderIDs addObject:item.itemID];
        }
    }
    for (NSString *folderID in folderIDs) {
        NSArray<BrowserShortcutItem *> *children = [self childrenOfFolderID:folderID inShortcuts:shortcuts];
        for (NSUInteger i = 0; i < children.count; i++) {
            children[i].sortOrder = (NSInteger)i;
        }
    }
}

+ (void)reorderTopLevelItems:(NSArray<BrowserShortcutItem *> *)orderedTopLevel
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts
                        save:(BOOL)save {
    NSMutableArray<BrowserShortcutItem *> *nested = [[NSMutableArray alloc] init];
    for (BrowserShortcutItem *item in shortcuts) {
        if (!item.isTopLevel) {
            [nested addObject:item];
        }
    }

    [shortcuts removeAllObjects];
    for (NSUInteger i = 0; i < orderedTopLevel.count; i++) {
        BrowserShortcutItem *item = orderedTopLevel[i];
        item.folderID = @"";
        item.sortOrder = (NSInteger)i;
        [shortcuts addObject:item];
    }
    [shortcuts addObjectsFromArray:nested];

    if (save) {
        [self saveShortcuts:shortcuts];
    }
}

#pragma mark - Serialization

+ (NSDictionary *)dictionaryFromItem:(BrowserShortcutItem *)item {
    NSString *kindValue = item.isFolder ? kShortcutKindFolderValue : kShortcutKindLinkValue;
    return @{
        kShortcutItemIDKey: item.itemID ?: @"",
        kShortcutTitleKey: item.title ?: @"",
        kShortcutURLKey: item.urlString ?: @"",
        kShortcutIconURLKey: item.iconURLString ?: @"",
        kShortcutOrderKey: @(item.sortOrder),
        kShortcutKindKey: kindValue,
        kShortcutFolderIDKey: item.folderID ?: @"",
    };
}

+ (BrowserShortcutItem *)itemFromDictionary:(NSDictionary *)dictionary {
    BrowserShortcutItem *item = [[BrowserShortcutItem alloc] init];
    id itemID = dictionary[kShortcutItemIDKey];
    item.itemID = [itemID isKindOfClass:[NSString class]] ? itemID : [[NSUUID UUID] UUIDString];
    id title = dictionary[kShortcutTitleKey];
    item.title = [title isKindOfClass:[NSString class]] ? title : @"";
    id url = dictionary[kShortcutURLKey];
    item.urlString = [url isKindOfClass:[NSString class]] ? url : @"";
    id iconURL = dictionary[kShortcutIconURLKey];
    item.iconURLString = [iconURL isKindOfClass:[NSString class]] ? iconURL : @"";
    id order = dictionary[kShortcutOrderKey];
    item.sortOrder = [order respondsToSelector:@selector(integerValue)] ? [order integerValue] : 0;

    id kindValue = dictionary[kShortcutKindKey];
    if ([kindValue isKindOfClass:[NSString class]] && [kindValue isEqualToString:kShortcutKindFolderValue]) {
        item.kind = BrowserShortcutItemKindFolder;
    } else if ([kindValue respondsToSelector:@selector(integerValue)] && [kindValue integerValue] == BrowserShortcutItemKindFolder) {
        item.kind = BrowserShortcutItemKindFolder;
    } else {
        item.kind = BrowserShortcutItemKindLink;
    }

    id folderID = dictionary[kShortcutFolderIDKey];
    item.folderID = [folderID isKindOfClass:[NSString class]] ? folderID : @"";
    if (item.isFolder) {
        item.folderID = @"";
        item.urlString = @"";
    }
    return item;
}

@end
