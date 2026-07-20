#import <Foundation/Foundation.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserShortcutAddItemID;
/// 快捷方式列表写入后广播（含 Companion 同步合并），Launchpad 应 reload。
extern NSNotificationName const BrowserShortcutStoreDidChangeNotification;

@interface BrowserShortcutStore : NSObject

+ (NSArray<BrowserShortcutItem *> *)defaultShortcuts;
+ (NSArray<BrowserShortcutItem *> *)loadShortcuts;
+ (void)saveShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;

+ (NSArray<BrowserShortcutItem *> *)topLevelShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;
+ (NSArray<BrowserShortcutItem *> *)childrenOfFolderID:(NSString *)folderID
                                           inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;
+ (nullable BrowserShortcutItem *)shortcutWithID:(NSString *)itemID
                                     inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;

+ (BrowserShortcutItem *)addShortcutWithTitle:(NSString *)title
                                    urlString:(NSString *)urlString
                                iconURLString:(NSString *)iconURLString
                                  toShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)updateShortcutWithID:(NSString *)itemID
                       title:(NSString *)title
                   urlString:(NSString *)urlString
               iconURLString:(NSString *)iconURLString
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

/// 按页面 URL 匹配 link 快捷方式并回写 iconURL；找到则保存并返回 YES。
+ (BOOL)updateIconURLString:(NSString *)iconURLString matchingURLString:(NSString *)urlString;

+ (void)removeShortcutWithID:(NSString *)itemID
                 fromShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (nullable BrowserShortcutItem *)createFolderWithTitle:(NSString *)title
                                              fromItem:(BrowserShortcutItem *)targetItem
                                          droppingItem:(BrowserShortcutItem *)droppingItem
                                           inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (BOOL)moveItem:(BrowserShortcutItem *)item
      intoFolder:(BrowserShortcutItem *)folder
     inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (BOOL)moveItem:(BrowserShortcutItem *)item
toTopLevelAtOrder:(NSInteger)order
     inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)renameFolderWithID:(NSString *)folderID
                     title:(NSString *)title
               inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)disbandFolderWithID:(NSString *)folderID
                inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)removeFolderWithID:(NSString *)folderID
            deleteChildren:(BOOL)deleteChildren
               inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)reorderTopLevelItems:(NSArray<BrowserShortcutItem *> *)orderedTopLevel
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (nullable NSString *)normalizedURLStringFromInput:(NSString *)input;
+ (nullable BrowserShortcutItem *)shortcutItemMatchingURLString:(NSString *)urlString
                                                    inShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;
+ (BOOL)isURLStringBookmarked:(NSString *)urlString;

+ (BOOL)validateURLString:(NSString *)input normalizedURL:(NSString * _Nullable * _Nullable)outURL;
+ (BOOL)validateIconURLString:(NSString *)input normalizedURL:(NSString * _Nullable * _Nullable)outURL;

+ (NSArray<BrowserShortcutItem *> *)shortcutsMatchingQuery:(NSString *)query
                                                     limit:(NSUInteger)limit;

@end

NS_ASSUME_NONNULL_END
