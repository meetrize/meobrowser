#import <Foundation/Foundation.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserScraperRecipeStoreDidChangeNotification;

@interface BrowserScraperRecipeStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, copy, readonly) NSArray<BrowserScraperRecipe *> *recipes;

- (nullable BrowserScraperRecipe *)recipeWithID:(NSString *)recipeID;
- (NSArray<BrowserScraperRecipe *> *)recipesMatchingURL:(NSURL *)url;

- (BOOL)saveRecipe:(BrowserScraperRecipe *)recipe error:(NSError **)error;
- (BOOL)deleteRecipeWithID:(NSString *)recipeID error:(NSError **)error;

- (BOOL)exportRecipe:(BrowserScraperRecipe *)recipe toURL:(NSURL *)url error:(NSError **)error;
- (nullable BrowserScraperRecipe *)importRecipeFromURL:(NSURL *)url error:(NSError **)error;

+ (NSString *)scraperRootDirectory;
+ (NSString *)runsRootDirectory;
- (void)reloadFromDisk;

@end

NS_ASSUME_NONNULL_END
