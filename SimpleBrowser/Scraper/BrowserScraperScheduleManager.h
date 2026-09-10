#import <Foundation/Foundation.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperScheduleManager : NSObject

+ (instancetype)sharedManager;

/// 按 recipe.schedule 安装或卸载 LaunchAgent。
- (BOOL)applyScheduleForRecipe:(BrowserScraperRecipe *)recipe error:(NSError **)error;
- (BOOL)unloadScheduleForRecipeID:(NSString *)recipeID label:(nullable NSString *)label error:(NSError **)error;

+ (NSString *)runnerExecutablePath;

@end

NS_ASSUME_NONNULL_END
