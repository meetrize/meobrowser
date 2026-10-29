#import <Foundation/Foundation.h>

@class AIPageContextBundle;
@class AIPageContextRecipe;
@class AIPageContextResource;
@class AIAssistantCitation;

NS_ASSUME_NONNULL_BEGIN

@interface AIPageContextPromptBuilder : NSObject

+ (NSString *)truncateText:(NSString *)text maxChars:(NSUInteger)maxChars;

+ (nullable AIAssistantCitation *)citationForLayer:(NSString *)layerId
                                          inBundle:(AIPageContextBundle *)bundle
                                            recipe:(nullable AIPageContextRecipe *)recipe;

+ (nullable AIAssistantCitation *)citationForResource:(AIPageContextResource *)resource
                                             inBundle:(AIPageContextBundle *)bundle;

/// 按指定层列表生成 Citation（已截断）。
+ (NSArray<AIAssistantCitation *> *)citationsFromBundle:(AIPageContextBundle *)bundle
                                                 layers:(NSArray<NSString *> *)layers
                                                 recipe:(nullable AIPageContextRecipe *)recipe;

/// 按 recipe.autoAttachLayers 生成。
+ (NSArray<AIAssistantCitation *> *)citationsFromBundle:(AIPageContextBundle *)bundle
                                                 recipe:(AIPageContextRecipe *)recipe;

/// 总预算裁剪（按层顺序丢弃超长部分）；返回提示文案（可能为空）。
+ (nullable NSString *)trimCitations:(NSMutableArray<AIAssistantCitation *> *)citations
                         toMaxChars:(NSUInteger)maxTotalChars;

+ (NSString *)apiPromptWithRecipe:(nullable AIPageContextRecipe *)recipe
                       citations:(NSArray<AIAssistantCitation *> *)citations
                        userText:(nullable NSString *)userText;

+ (nullable NSString *)layerIdForCitationKind:(NSInteger)kind;
+ (NSInteger)citationKindForLayerId:(NSString *)layerId;

@end

NS_ASSUME_NONNULL_END
