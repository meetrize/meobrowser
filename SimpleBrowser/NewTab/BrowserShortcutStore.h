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
                                  toShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)updateShortcutWithID:(NSString *)itemID
                       title:(NSString *)title
                   urlString:(NSString *)urlString
                 inShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (void)removeShortcutWithID:(NSString *)itemID
                 fromShortcuts:(NSMutableArray<BrowserShortcutItem *> *)shortcuts;

+ (BOOL)validateURLString:(NSString *)input normalizedURL:(NSString * _Nullable * _Nullable)outURL;

@end

NS_ASSUME_NONNULL_END
