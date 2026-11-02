#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDSummarizePage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDAskPage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDOutlinePage;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDExtractFacts;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDRegexExtract;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDBackgroundDig;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDInvestmentThesis;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDRiskScan;
FOUNDATION_EXPORT NSString * const AIPageContextRecipeIDMarketTrend;

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

/// 侧栏快捷按钮
@property (nonatomic, assign) BOOL showInSidebar;
/// 「问问 AI」子菜单
@property (nonatomic, assign) BOOL showInContextMenu;
/// 右键顶层第一项（全局至多一个）
@property (nonatomic, assign) BOOL contextMenuTopLevel;
/// 运行后是否自动发送
@property (nonatomic, assign) BOOL autoSend;
/// 侧栏/菜单排序（升序）
@property (nonatomic, assign) NSInteger sortOrder;

+ (nullable AIPageContextRecipe *)recipeWithId:(NSString *)recipeId;
+ (NSArray<AIPageContextRecipe *> *)bundledRecipes;
/// @deprecated 请用 Store 合并后的 recipe.autoSend
+ (BOOL)shouldAutoSendRecipeId:(NSString *)recipeId;
+ (nullable instancetype)recipeFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
- (instancetype)copyRecipe;

/// 是否为代码内置 id（可能被用户 JSON 覆盖）
+ (BOOL)isBundledRecipeId:(NSString *)recipeId;

@end

NS_ASSUME_NONNULL_END
