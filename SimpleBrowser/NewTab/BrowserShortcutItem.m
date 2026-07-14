#import "BrowserShortcutItem.h"

@implementation BrowserShortcutItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _kind = BrowserShortcutItemKindLink;
        _folderID = @"";
        _urlString = @"";
        _iconURLString = @"";
        _title = @"";
    }
    return self;
}

+ (instancetype)itemWithTitle:(NSString *)title
                    urlString:(NSString *)urlString
                 iconURLString:(NSString *)iconURLString
                    sortOrder:(NSInteger)sortOrder {
    BrowserShortcutItem *item = [[self alloc] init];
    item.itemID = [[NSUUID UUID] UUIDString];
    item.title = [title copy];
    item.urlString = [urlString copy];
    item.iconURLString = [iconURLString copy];
    item.sortOrder = sortOrder;
    item.kind = BrowserShortcutItemKindLink;
    item.folderID = @"";
    return item;
}

+ (instancetype)folderWithTitle:(NSString *)title sortOrder:(NSInteger)sortOrder {
    BrowserShortcutItem *item = [[self alloc] init];
    item.itemID = [[NSUUID UUID] UUIDString];
    item.title = [title copy];
    item.urlString = @"";
    item.iconURLString = @"";
    item.sortOrder = sortOrder;
    item.kind = BrowserShortcutItemKindFolder;
    item.folderID = @"";
    return item;
}

- (BOOL)isFolder {
    return self.kind == BrowserShortcutItemKindFolder;
}

- (BOOL)isTopLevel {
    return self.folderID.length == 0;
}

- (void)setFolderID:(NSString *)folderID {
    _folderID = folderID ?: @"";
}

@end
