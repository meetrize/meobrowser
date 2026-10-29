#import <Foundation/Foundation.h>

@class AIPageContextBundle;
@class BrowserScraperRecipe;

NS_ASSUME_NONNULL_BEGIN

@interface AIPageContextScraperBridge : NSObject

/// 从页面 Bundle（及可选点选结果）生成爬虫草稿配方。
+ (BrowserScraperRecipe *)draftRecipeFromBundle:(AIPageContextBundle *)bundle
                                     pickResult:(nullable NSDictionary *)pickResult;

@end

NS_ASSUME_NONNULL_END
