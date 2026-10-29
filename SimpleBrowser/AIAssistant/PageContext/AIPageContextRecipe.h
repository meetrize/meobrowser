#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDSummarizePage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDAskPage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDOutlinePage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDExtractFacts;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDRegexExtract;

@interface AIPageContextRecipe : NSObject

@property (nonatomic, copy) NSString *recipeId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *userPrompt;
@property (nonatomic, copy) NSString *systemHint;
@property (nonatomic, copy) NSArray<NSString *> *autoAttachLayers;
@property (nonatomic, assign) NSUInteger maxArticleChars;
@property (nonatomic, assign) NSUInteger maxHtmlChars;
@property (nonatomic, assign) BOOL userDefined;
/// PC-3 预留：页内预处理 JS（返回 {ok, layers?, citations?}）；空则跳过。
@property (nonatomic, copy, nullable) NSString *preprocessScript;

+ (nullable AIPageContextRecipe *)recipeWithId:(NSString *)recipeId;
+ (NSArray<AIPageContextRecipe *> *)bundledRecipes;
+ (nullable instancetype)recipeFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
