#import <Foundation/Foundation.h>

@class AIPageContextRecipe;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIPageContextRecipeStoreDidChangeNotification;

@interface AIPageContextRecipeStore : NSObject

@property (class, readonly, strong) AIPageContextRecipeStore *sharedStore;

/// 内置 + 用户配方（用户同 id 覆盖）；按 sortOrder 再 title 排序
- (NSArray<AIPageContextRecipe *> *)allRecipes;
- (NSArray<AIPageContextRecipe *> *)allRecipesSorted;
- (nullable AIPageContextRecipe *)recipeWithId:(NSString *)recipeId;
- (NSArray<AIPageContextRecipe *> *)userRecipes;

/// 磁盘上是否有该 id 的用户覆盖/新建
- (BOOL)hasUserOverrideForId:(NSString *)recipeId;
/// 纯用户新建（非覆盖内置）
- (BOOL)isPureUserRecipeId:(NSString *)recipeId;

- (BOOL)saveUserRecipe:(AIPageContextRecipe *)recipe error:(NSError *_Nullable *_Nullable)error;
/// 删除用户 JSON；若为内置 id 则恢复默认
- (BOOL)resetRecipeId:(NSString *)recipeId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteUserRecipeId:(NSString *)recipeId error:(NSError *_Nullable *_Nullable)error;

- (AIPageContextRecipe *)duplicateRecipe:(AIPageContextRecipe *)source withTitle:(NSString *)title;
- (AIPageContextRecipe *)createBlankRecipe;

- (BOOL)exportRecipe:(AIPageContextRecipe *)recipe toURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;
- (nullable AIPageContextRecipe *)importRecipeFromURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

- (void)reloadFromDisk;

@end

NS_ASSUME_NONNULL_END
