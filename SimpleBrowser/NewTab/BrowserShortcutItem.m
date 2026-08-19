#import "BrowserShortcutItem.h"

NSString * const BrowserShortcutIconStyleAuto = @"auto";
NSString * const BrowserShortcutIconStyleLetter = @"letter";

@implementation BrowserShortcutItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _kind = BrowserShortcutItemKindLink;
        _folderID = @"";
        _urlString = @"";
        _iconURLString = @"";
        _title = @"";
        _iconStyle = BrowserShortcutIconStyleAuto;
        _iconLetter = @"";
        _iconColorIndex = 0;
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
    item.iconStyle = BrowserShortcutIconStyleAuto;
    item.iconLetter = @"";
    item.iconColorIndex = 0;
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
    item.iconStyle = BrowserShortcutIconStyleAuto;
    item.iconLetter = @"";
    item.iconColorIndex = 0;
    return item;
}

- (BOOL)isFolder {
    return self.kind == BrowserShortcutItemKindFolder;
}

- (BOOL)isTopLevel {
    return self.folderID.length == 0;
}

- (BOOL)usesCustomLetterIcon {
    if (self.isFolder) {
        return NO;
    }
    return [self.iconStyle isEqualToString:BrowserShortcutIconStyleLetter];
}

- (void)setFolderID:(NSString *)folderID {
    _folderID = folderID ?: @"";
}

- (void)setIconStyle:(NSString *)iconStyle {
    if ([iconStyle isEqualToString:BrowserShortcutIconStyleLetter]) {
        _iconStyle = BrowserShortcutIconStyleLetter;
    } else {
        _iconStyle = BrowserShortcutIconStyleAuto;
    }
}

- (void)setIconLetter:(NSString *)iconLetter {
    _iconLetter = iconLetter ?: @"";
}

@end
