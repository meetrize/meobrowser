#import <Foundation/Foundation.h>

@class AIPageContextRecipe;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AIPageContextRecipeStoreDidChangeNotification;

@interface AIPageContextRecipeStore : NSObject

@property (class, readonly, strong) AIPageContextRecipeStore *sharedStore;

/// 内置 + 用户配方（用户同 id 可覆盖显示，但不改内置文件）
- (NSArray<AIPageContextRecipe *> *)allRecipes;
- (nullable AIPageContextRecipe *)recipeWithId:(NSString *)recipeId;
- (NSArray<AIPageContextRecipe *> *)userRecipes;

- (BOOL)saveUserRecipe:(AIPageContextRecipe *)recipe error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteUserRecipeId:(NSString *)recipeId error:(NSError *_Nullable *_Nullable)error;
- (AIPageContextRecipe *)duplicateRecipe:(AIPageContextRecipe *)source withTitle:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
