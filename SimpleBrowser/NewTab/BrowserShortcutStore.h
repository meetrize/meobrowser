#import <Foundation/Foundation.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserShortcutAddItemID;

@interface BrowserShortcutStore : NSObject

+ (NSArray<BrowserShortcutItem *> *)defaultShortcuts;
+ (NSArray<BrowserShortcutItem *> *)loadShortcuts;
+ (void)saveShortcuts:(NSArray<BrowserShortcutItem *> *)shortcuts;

+ (BrowserShortcutItem *)addShortcutWithTitle:(NSString *)title
                                    urlString:(NSString *)urlString
                                iconURLString:(NSString *)iconURLString
                                  toShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)updateShortcutWithID:(NSString *)itemID
                       title:(NSString *)title
                   urlString:(NSString *)urlString
               iconURLString:(NSString *)iconURLString
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)removeShortcutWithID:(NSString *)itemID
                 fromShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

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
