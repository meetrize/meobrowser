#import "BrowserShortcutItem.h"

@implementation BrowserShortcutItem

+ (instancetype)itemWithTitle:(NSString *)title
                    urlString:(NSString *)urlString
                    sortOrder:(NSInteger)sortOrder {
    BrowserShortcutItem *item = [[self alloc] init];
    item.itemID = [[NSUUID UUID] UUIDString];
    item.title = [title copy];
    item.urlString = [urlString copy];
    item.sortOrder = sortOrder;
    return item;
}

@end
