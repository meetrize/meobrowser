#import "AIPageContextRecipe.h"
#import "AIPageContextBundle.h"

NSString * const AIPageContextRecipeIDSummarizePage = @"summarize-page";
NSString * const AIPageContextRecipeIDAskPage = @"ask-page";
NSString * const AIPageContextRecipeIDOutlinePage = @"outline-page";
NSString * const AIPageContextRecipeIDExtractFacts = @"extract-facts";
NSString * const AIPageContextRecipeIDRegexExtract = @"regex-extract";
NSString * const AIPageContextRecipeIDBackgroundDig = @"background-dig";

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
              userPrompt:
                   @"请用简体中文总结该网页正文，严格按下面结构回复（不要复述导航、页脚或广告）：\n"
                   @"\n"
                   @"1. 核心（必须放在最前）：用 1～2 句写出全文最重要、最有价值、不可忽略的信息，"
                   @"或整文纲领性结论；整段用 Markdown 加粗（**……**），控制在约 40～80 字，不要列表。\n"
                   @"2. 要点：空一行后，用简洁条目列出其余关键内容（事实、结论、步骤等）。\n"
                   @"\n"
                   @"只依据引用中出现的信息，不要臆造。"
             systemHint:
                   @"你只会看到用户勾选的引用。若有「正文」层，请主要依据正文；不要臆造未出现的信息。"
                   @"回复必须以一行加粗的「核心」开头（Markdown **…**），再跟分条要点；"
                   @"核心段不要用列表或标题前缀，直接加粗正文即可。"
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
            [self makeId:AIPageContextRecipeIDBackgroundDig
                   title:@"背景挖掘"
              userPrompt:
                   @"请基于本页正文，完成「背景与衍生信息挖掘」，输出一份简体中文《背景信息研究分析报告》。\n"
                   @"\n"
                   @"先在内心完成（不必逐步写出推理过程）：\n"
                   @"1) 判断文章性质（新闻/研报/教程/产品/访谈/小说网文/政策/学术等），据此决定要挖哪些关联维度；\n"
                   @"2) 抽取文中关键知识锚点：人名或角色、机构、产品/技术、行业与赛道、地域、时间节点、关键数据等；\n"
                   @"3) 按文章性质从下列维度按需选取（勿机械全选）：背景知识、行业/领域关联、趋势与催化、"
                   @"风险与争议、人物或机构侧写、文中暗示但未展开的衍生议题；\n"
                   @"4) 若你具备联网或搜索能力，请先针对上述锚点检索再写；若无搜索，用已有知识补充并标明局限。\n"
                   @"\n"
                   @"最终只输出报告，结构如下：\n"
                   @"**核心研判**（开篇 1～2 句，Markdown 加粗：读者最该补强的背景认知）\n"
                   @"## 文中关键锚点\n"
                   @"## 背景知识\n"
                   @"## 行业与关联信息\n"
                   @"## 趋势\n"
                   @"## 风险与注意点\n"
                   @"## 延伸阅读方向（3～5 个建议继续核实的关键词或问题）\n"
                   @"\n"
                   @"规则：正文未给出但合理的补充标注「文外补充」；不确定标注「待核实」；"
                   @"不要复述导航/广告；重洞察、控制篇幅，不要堆砌常识。"
             systemHint:
                   @"你主要依据用户勾选的页面引用（尤其是正文）。先识别文章类型与关键实体，再按需展开背景、"
                   @"行业关联、趋势与风险，不要对无关维度硬凑章节。"
                   @"正文之外的知识必须标注「文外补充」或「待核实」；有搜索能力时应先检索关键锚点。"
                   @"回复必须以加粗的「核心研判」开头，再按标题输出报告；不要复述采集过程。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:32000],
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
