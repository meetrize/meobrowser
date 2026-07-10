#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"

static NSString * const kShortcutItemsKey = @"shortcutItems";
static NSString * const kShortcutItemIDKey = @"id";
static NSString * const kShortcutTitleKey = @"title";
static NSString * const kShortcutURLKey = @"url";
static NSString * const kShortcutOrderKey = @"order";

NSString * const BrowserShortcutAddItemID = @"__launchpad_add__";

@implementation BrowserShortcutStore

+ (NSArray<BrowserShortcutItem *> *)defaultShortcuts {
    return @[
        [BrowserShortcutItem itemWithTitle:@"Google" urlString:@"https://www.google.com" sortOrder:0],
        [BrowserShortcutItem itemWithTitle:@"GitHub" urlString:@"https://github.com" sortOrder:1],
        [BrowserShortcutItem itemWithTitle:@"Wikipedia" urlString:@"https://www.wikipedia.org" sortOrder:2],
        [BrowserShortcutItem itemWithTitle:@"Hacker News" urlString:@"https://news.ycombinator.com" sortOrder:3],
        [BrowserShortcutItem itemWithTitle:@"Apple" urlString:@"https://www.apple.com" sortOrder:4],
        [BrowserShortcutItem itemWithTitle:@"百度" urlString:@"https://www.baidu.com" sortOrder:5],
        [BrowserShortcutItem itemWithTitle:@"哔哩哔哩" urlString:@"https://www.bilibili.com" sortOrder:6],
        [BrowserShortcutItem itemWithTitle:@"知乎" urlString:@"https://www.zhihu.com" sortOrder:7],
    ];
}

+ (NSArray<BrowserShortcutItem *> *)loadShortcuts {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kShortcutItemsKey];
    if (![stored isKindOfClass:[NSArray class]] || stored.count == 0) {
        NSArray<BrowserShortcutItem *> *defaults = [self defaultShortcuts];
        [self saveShortcuts:defaults];
        return defaults;
    }

    NSMutableArray<BrowserShortcutItem *> *items = [[NSMutableArray alloc] initWithCapacity:stored.count];
    for (id entry in stored) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        BrowserShortcutItem *item = [self itemFromDictionary:(NSDictionary *)entry];
        if (item.title.length > 0 && item.urlString.length > 0) {
            [items addObject:item];
        }
    }

    if (items.count == 0) {
        NSArray<BrowserShortcutItem *> *defaults = [self defaultShortcuts];
        [self saveShortcuts:defaults];
        return defaults;
    }

    [items sortUsingComparator:^NSComparisonResult(BrowserShortcutItem *a, BrowserShortcutItem *b) {
        if (a.sortOrder == b.sortOrder) {
            return [a.title compare:b.title];
        }
        return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
    return items;
}

+ (void)saveShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts {
    NSMutableArray<NSDictionary *> *payload = [[NSMutableArray alloc] initWithCapacity:shortcuts.count];
    for (NSUInteger i = 0; i < shortcuts.count; i++) {
        BrowserShortcutItem *item = shortcuts[i];
        item.sortOrder = (NSInteger)i;
        [payload addObject:[self dictionaryFromItem:item]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:payload forKey:kShortcutItemsKey];
}

+ (BrowserShortcutItem *)addShortcutWithTitle:(NSString *)title
                                    urlString:(NSString *)urlString
                                  toShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    BrowserShortcutItem *item = [BrowserShortcutItem itemWithTitle:title
                                                       urlString:urlString
                                                       sortOrder:(NSInteger)shortcuts.count];
    [shortcuts addObject:item];
    [self saveShortcuts:shortcuts];
    return item;
}

+ (void)updateShortcutWithID:(NSString *)itemID
                       title:(NSString *)title
                   urlString:(NSString *)urlString
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    for (BrowserShortcutItem *item in shortcuts) {
        if ([item.itemID isEqualToString:itemID]) {
            item.title = [title copy];
            item.urlString = [urlString copy];
            break;
        }
    }
    [self saveShortcuts:shortcuts];
}

+ (void)removeShortcutWithID:(NSString *)itemID
                 fromShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts {
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < shortcuts.count; i++) {
        if ([shortcuts[i].itemID isEqualToString:itemID]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        return;
    }
    [shortcuts removeObjectAtIndex:index];
    [self saveShortcuts:shortcuts];
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

#pragma mark - Serialization

+ (NSDictionary *)dictionaryFromItem:(BrowserShortcutItem *)item {
    return @{
        kShortcutItemIDKey: item.itemID ?: @"",
        kShortcutTitleKey: item.title ?: @"",
        kShortcutURLKey: item.urlString ?: @"",
        kShortcutOrderKey: @(item.sortOrder),
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
    id order = dictionary[kShortcutOrderKey];
    item.sortOrder = [order respondsToSelector:@selector(integerValue)] ? [order integerValue] : 0;
    return item;
}

@end
