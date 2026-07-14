#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserShortcutItemKind) {
    BrowserShortcutItemKindLink = 0,
    BrowserShortcutItemKindFolder = 1,
};

@interface BrowserShortcutItem : NSObject

@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *iconURLString;
@property (nonatomic, assign) NSInteger sortOrder;
@property (nonatomic, assign) BrowserShortcutItemKind kind;
@property (nonatomic, copy) NSString *folderID;

@property (nonatomic, readonly, getter=isFolder) BOOL folder;
@property (nonatomic, readonly, getter=isTopLevel) BOOL topLevel;

+ (instancetype)itemWithTitle:(NSString *)title
                    urlString:(NSString *)urlString
                 iconURLString:(NSString *)iconURLString
                    sortOrder:(NSInteger)sortOrder;

+ (instancetype)folderWithTitle:(NSString *)title sortOrder:(NSInteger)sortOrder;

@end

NS_ASSUME_NONNULL_END
