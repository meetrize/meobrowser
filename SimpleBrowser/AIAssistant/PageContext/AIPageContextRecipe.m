#import "AIPageContextRecipe.h"
#import "AIPageContextBundle.h"

NSString * const AIPageContextRecipeIDSummarizePage = @"summarize-page";
NSString * const AIPageContextRecipeIDAskPage = @"ask-page";
NSString * const AIPageContextRecipeIDOutlinePage = @"outline-page";
NSString * const AIPageContextRecipeIDExtractFacts = @"extract-facts";
NSString * const AIPageContextRecipeIDRegexExtract = @"regex-extract";
NSString * const AIPageContextRecipeIDBackgroundDig = @"background-dig";
NSString * const AIPageContextRecipeIDInvestmentThesis = @"investment-thesis";
NSString * const AIPageContextRecipeIDRiskScan = @"risk-scan";
NSString * const AIPageContextRecipeIDMarketTrend = @"market-trend";

static NSString * const kFinanceDisclaimer =
    @"文末固定一行免责：以上为信息整理与逻辑推演，不构成投资建议。";

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
            [self makeId:AIPageContextRecipeIDInvestmentThesis
                   title:@"投资研判"
              userPrompt:[NSString stringWithFormat:
                   @"请基于本页正文，输出一份简体中文《投资研判备忘》（偏股票/行业/金融产品视角）。\n"
                   @"\n"
                   @"先识别：标的或主题是什么、文章立场（多/空/中性/营销）、信息类型（研报/公告解读/自媒体/产品软文等）。\n"
                   @"有搜索能力可先核实关键专有名词与事件；无搜索则用已有知识并标明局限。\n"
                   @"\n"
                   @"输出结构：\n"
                   @"**核心结论**（开篇 1～2 句加粗：多空倾向与最关键依据，勿给目标价）\n"
                   @"## 标的 / 主题定位\n"
                   @"## 多方逻辑\n"
                   @"## 空方 / 质疑逻辑\n"
                   @"## 催化剂与时间窗\n"
                   @"## 关键假设（哪些成立研判才成立）\n"
                   @"## 风险与证伪条件\n"
                   @"## 需核实清单（3～7 条数据或口径）\n"
                   @"\n"
                   @"规则：数字尽量保留文中原口径（同比/扣非/指引等）；文外补充标「文外补充」，不确定标「待核实」；"
                   @"禁止假装精确预测点位；情景用「若…则…」。\n"
                   @"%@",
                   kFinanceDisclaimer]
             systemHint:
                   @"面向投研阅读助手：依据页面引用整理可讨论的多空框架，不是荐股。"
                   @"必须以加粗核心结论开头；区分文中明示与文外推断；文末免责声明不可省略。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:32000],
            [self makeId:AIPageContextRecipeIDRiskScan
                   title:@"风险扫描"
              userPrompt:[NSString stringWithFormat:
                   @"请基于本页正文，做「风险与雷点扫描」，输出简体中文风险备忘（偏投资/金融产品语境）。\n"
                   @"\n"
                   @"重点查找：财务与现金流、治理与关联交易、监管与合规、流动性与质押、估值叙事泡沫、"
                   @"产品条款陷阱（费率/杠杆/敲入敲出/底层暴露）、夸大宣传与未证实承诺。\n"
                   @"对每条风险标注来源：文中明示 / 文外推断 / 待核实。\n"
                   @"\n"
                   @"输出结构：\n"
                   @"**核心风险**（开篇 1～2 句加粗：最该警惕的 1～2 个点）\n"
                   @"## 高优先级雷点\n"
                   @"## 中低优先级关注\n"
                   @"## 条款 / 口径陷阱（若有）\n"
                   @"## 证据不足但仍需追问\n"
                   @"## 建议优先核实的问题\n"
                   @"\n"
                   @"不要为凑章节硬写无关风险；没有明显雷点就如实写「文中未见显著雷点」并说明仍缺什么信息。\n"
                   @"%@",
                   kFinanceDisclaimer]
             systemHint:
                   @"专门找坑：优先列出可能造成本金或决策失误的风险，而非复述看多故事。"
                   @"每条风险标明文中明示/文外推断/待核实；开篇加粗核心风险；文末免责不可省。"
                 layers:@[ AIPageContextLayerMeta, AIPageContextLayerArticle ]
           maxArticleChars:32000],
            [self makeId:AIPageContextRecipeIDMarketTrend
                   title:@"趋势框架"
              userPrompt:[NSString stringWithFormat:
                   @"请基于本页正文，输出简体中文《趋势与行情框架》分析（宏观/行业/主题/个股皆可，按文中层次选）。\n"
                   @"\n"
                   @"先判断讨论层次（宏观、行业、主题、个股、产品），再组织驱动与情景，勿机械套模板。\n"
                   @"\n"
                   @"输出结构：\n"
                   @"**核心判断**（开篇 1～2 句加粗：当前可能处于什么阶段、主驱动是什么）\n"
                   @"## 主驱动拆解（基本面 / 资金 / 政策 / 情绪，按文取舍）\n"
                   @"## 周期位置（若可判断；否则写不确定及原因）\n"
                   @"## 关键节点（事件、数据、价位或政策窗口——仅文中出现或可合理推断）\n"
                   @"## 情景推演（2～3 个：若…则…；禁止假装精确点位预测）\n"
                   @"## 跟踪指标（3～6 个）\n"
                   @"## 与旧叙事是否矛盾（若文中可判断）\n"
                   @"\n"
                   @"文外补充标「文外补充」，不确定标「待核实」。\n"
                   @"%@",
                   kFinanceDisclaimer]
             systemHint:
                   @"趋势框架助手：拆驱动、定层次、给情景，不给买卖指令。"
                   @"开篇加粗核心判断；禁止伪装精确预测；文末免责不可省。"
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

+ (BOOL)shouldAutoSendRecipeId:(NSString *)recipeId {
    if (recipeId.length == 0) return NO;
    static NSSet *ids;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ids = [NSSet setWithArray:@[
            AIPageContextRecipeIDSummarizePage,
            AIPageContextRecipeIDBackgroundDig,
            AIPageContextRecipeIDInvestmentThesis,
            AIPageContextRecipeIDRiskScan,
            AIPageContextRecipeIDMarketTrend,
            AIPageContextRecipeIDOutlinePage,
            AIPageContextRecipeIDExtractFacts,
        ]];
    });
    return [ids containsObject:recipeId];
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
