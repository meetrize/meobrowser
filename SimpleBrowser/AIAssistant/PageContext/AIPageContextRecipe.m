#import "AIPageContextRecipe.h"
#import "AIPageContextBundle.h"

NSString * const AIPageContextRecipeIDSummarizePage = @"summarize-page";
NSString * const AIPageContextRecipeIDAskPage = @"ask-page";
NSString * const AIPageContextRecipeIDOutlinePage = @"outline-page";
NSString * const AIPageContextRecipeIDExtractFacts = @"extract-facts";
NSString * const AIPageContextRecipeIDRegexExtract = @"regex-extract";

@implementation AIPageContextRecipe

+ (AIPageContextRecipe *)makeId:(NSString *)rid
                          title:(NSString *)title
                     userPrompt:(NSString *)userPrompt
                    systemHint:(NSString *)systemHint
                        layers:(NSArray<NSString *> *)layers
              maxArticleChars:(NSUInteger)maxChars {
    AIPageContextRecipe *r = [[AIPageContextRecipe alloc] init];
    r.recipeId = rid;
    r.title = title;
    r.userPrompt = userPrompt;
    r.systemHint = systemHint;
    r.autoAttachLayers = layers;
    r.maxArticleChars = maxChars;
    r.maxHtmlChars = 100000;
    r.userDefined = NO;
    r.preprocessScript = nil;
    return r;
}

+ (NSArray<AIPageContextRecipe *> *)bundledRecipes {
    static NSArray *recipes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        recipes = @[
            [self makeId:AIPageContextRecipeIDSummarizePage
                   title:@"总结该网页"
              userPrompt:@"请总结该网页的正文要点，用简洁中文分条列出；不要复述导航、页脚或广告。"
             systemHint:@"你只会看到用户勾选的引用。若有「正文」层，请主要依据正文；不要臆造未出现的信息。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:24000],
            [self makeId:AIPageContextRecipeIDAskPage
                   title:@"问答本页"
              userPrompt:@"请根据本页正文回答我的问题（在下方补充具体问题）：\n\n"
             systemHint:@"请主要依据用户提供的页面引用作答；引用中未出现的信息请明确说明不确定。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:24000],
            [self makeId:AIPageContextRecipeIDOutlinePage
                   title:@"生成提纲"
              userPrompt:@"请根据提纲与正文，整理一份层次清晰的中文提纲（三级以内），并给每节一句摘要。"
             systemHint:@"优先使用「提纲」层；正文仅作补充。不要编造未出现的章节。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerOutline, AIPageContextLayerArticle ]
           maxArticleChars:24000],
            [self makeId:AIPageContextRecipeIDExtractFacts
                   title:@"提取要点"
              userPrompt:@"请从正文中提取关键事实、数据、结论，用条目列出；不确定的标为「待核实」。"
             systemHint:@"只提取引用中明确出现的信息；保留数字与专有名词原文。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:24000],
            [self makeId:AIPageContextRecipeIDRegexExtract
                   title:@"按正则提取"
              userPrompt:@"请根据下面的正则（或规则）从引用内容中提取匹配项，列出全部命中并去重。\n正则：\n\n"
             systemHint:@"优先在 HTML 或正文中查找；若无匹配请说明。不要编造匹配结果。"
                 layers:@[ AIPageContextLayerArticle, AIPageContextLayerHTML ]
           maxArticleChars:24000],
        ];
    });
    return recipes;
}

+ (AIPageContextRecipe *)recipeFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *rid = dict[@"id"];
    if (![rid isKindOfClass:[NSString class]] || rid.length == 0) return nil;
    AIPageContextRecipe *r = [[AIPageContextRecipe alloc] init];
    r.recipeId = rid;
    r.title = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : rid;
    r.userPrompt = [dict[@"userPrompt"] isKindOfClass:[NSString class]] ? dict[@"userPrompt"] : @"";
    r.systemHint = [dict[@"systemHint"] isKindOfClass:[NSString class]] ? dict[@"systemHint"] : @"";
    NSArray *layers = dict[@"autoAttach"] ?: dict[@"autoAttachLayers"];
    if ([layers isKindOfClass:[NSArray class]]) {
        r.autoAttachLayers = layers;
    } else {
        r.autoAttachLayers = @[ AIPageContextLayerMeta, AIPageContextLayerArticle ];
    }
    id maxA = dict[@"maxArticleChars"];
    r.maxArticleChars = [maxA respondsToSelector:@selector(unsignedIntegerValue)] ? [maxA unsignedIntegerValue] : 24000;
    id maxH = dict[@"maxHtmlChars"];
    r.maxHtmlChars = [maxH respondsToSelector:@selector(unsignedIntegerValue)] ? [maxH unsignedIntegerValue] : 100000;
    id ud = dict[@"userDefined"];
    r.userDefined = [ud respondsToSelector:@selector(boolValue)] ? [ud boolValue] : YES;
    NSString *pre = dict[@"preprocessScript"];
    r.preprocessScript = [pre isKindOfClass:[NSString class]] ? pre : nil;
    return r;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [@{
        @"id": self.recipeId ?: @"",
        @"title": self.title ?: @"",
        @"userPrompt": self.userPrompt ?: @"",
        @"systemHint": self.systemHint ?: @"",
        @"autoAttach": self.autoAttachLayers ?: @[],
        @"maxArticleChars": @(self.maxArticleChars),
        @"maxHtmlChars": @(self.maxHtmlChars),
        @"userDefined": @(self.userDefined),
    } mutableCopy];
    if (self.preprocessScript.length) {
        d[@"preprocessScript"] = self.preprocessScript;
    }
    return d;
}

+ (AIPageContextRecipe *)recipeWithId:(NSString *)recipeId {
    if (recipeId.length == 0) return nil;
    for (AIPageContextRecipe *r in [self bundledRecipes]) {
        if ([r.recipeId isEqualToString:recipeId]) return r;
    }
    return nil;
}

@end
