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

@end

NS_ASSUME_NONNULL_END
