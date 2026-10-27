#import <Foundation/Foundation.h>

@class LoginRecipe;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const LoginRecipeStoreDidChangeNotification;

@interface LoginRecipeStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<LoginRecipe *> *)allRecipes;
- (NSArray<LoginRecipe *> *)recipesMatchingURL:(NSURL *)url;
- (nullable LoginRecipe *)defaultRecipeMatchingURL:(NSURL *)url;
- (nullable LoginRecipe *)recipeWithID:(NSString *)recipeID;

- (BOOL)upsertRecipe:(LoginRecipe *)recipe error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteRecipeWithID:(NSString *)recipeID error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setDefaultRecipeID:(NSString *)recipeID error:(NSError * _Nullable * _Nullable)error;
/// 云同步写回：整表替换，保留各 recipe.updatedAt，不强制刷新时间戳。
- (BOOL)replaceAllRecipes:(NSArray<LoginRecipe *> *)recipes error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
