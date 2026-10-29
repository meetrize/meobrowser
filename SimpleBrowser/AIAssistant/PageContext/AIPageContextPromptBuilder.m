#import "AIPageContextPromptBuilder.h"
#import "AIPageContextBundle.h"
#import "AIPageContextRecipe.h"
#import "AIPageContextResource.h"
#import "AIAssistantCitation.h"

@implementation AIPageContextPromptBuilder

+ (NSString *)truncateText:(NSString *)text maxChars:(NSUInteger)maxChars {
    if (text.length == 0 || maxChars == 0 || text.length <= maxChars) {
        return text ?: @"";
    }
    NSString *head = [text substringToIndex:maxChars];
    return [head stringByAppendingString:@"\n\n…（已截断）"];
}

+ (NSInteger)citationKindForLayerId:(NSString *)layerId {
    if ([layerId isEqualToString:AIPageContextLayerMeta]) return AIAssistantCitationKindPageMeta;
    if ([layerId isEqualToString:AIPageContextLayerArticle]) return AIAssistantCitationKindPageArticle;
    if ([layerId isEqualToString:AIPageContextLayerOutline]) return AIAssistantCitationKindPageOutline;
    if ([layerId isEqualToString:AIPageContextLayerHTML]) return AIAssistantCitationKindPageHTML;
    if ([layerId isEqualToString:AIPageContextLayerMarkdown]) return AIAssistantCitationKindPageMarkdown;
    return -1;
}

+ (NSString *)layerIdForCitationKind:(NSInteger)kind {
    switch ((AIAssistantCitationKind)kind) {
        case AIAssistantCitationKindPageMeta: return AIPageContextLayerMeta;
        case AIAssistantCitationKindPageArticle: return AIPageContextLayerArticle;
        case AIAssistantCitationKindPageOutline: return AIPageContextLayerOutline;
        case AIAssistantCitationKindPageHTML: return AIPageContextLayerHTML;
        case AIAssistantCitationKindPageMarkdown: return AIPageContextLayerMarkdown;
        default: return nil;
    }
}

+ (AIAssistantCitation *)citationForLayer:(NSString *)layerId
                                 inBundle:(AIPageContextBundle *)bundle
                                   recipe:(AIPageContextRecipe *)recipe {
    if (!bundle || layerId.length == 0) return nil;
    NSUInteger maxArt = recipe.maxArticleChars > 0 ? recipe.maxArticleChars : 24000;
    NSUInteger maxHtml = recipe.maxHtmlChars > 0 ? recipe.maxHtmlChars : 100000;

    if ([layerId isEqualToString:AIPageContextLayerMeta]) {
        return [AIAssistantCitation pageMetaCitationWithTitle:bundle.title
                                                    urlString:bundle.urlString
                                                  description:bundle.metaDescription
                                                     language:bundle.metaLanguage];
    }
    if ([layerId isEqualToString:AIPageContextLayerArticle]) {
        NSString *text = [self truncateText:[bundle effectiveArticleText] maxChars:maxArt];
        if (text.length == 0) return nil;
        return [AIAssistantCitation pageArticleCitationWithText:text
                                                        quality:bundle.articleQuality == AIPageContextArticleQualityHigh ? @"high" :
                                                               (bundle.articleQuality == AIPageContextArticleQualityLow ? @"low" : nil)
                                                        warning:bundle.articleWarning
                                                      pageTitle:bundle.title
                                                        pageURL:bundle.urlString];
    }
    if ([layerId isEqualToString:AIPageContextLayerOutline]) {
        NSString *text = [self truncateText:bundle.outlineText ?: @"" maxChars:8000];
        if (text.length == 0) return nil;
        return [AIAssistantCitation pageOutlineCitationWithText:text
                                                      pageTitle:bundle.title
                                                        pageURL:bundle.urlString];
    }
    if ([layerId isEqualToString:AIPageContextLayerHTML]) {
        NSString *text = [self truncateText:bundle.htmlText ?: @"" maxChars:maxHtml];
        if (text.length == 0) return nil;
        return [AIAssistantCitation pageHTMLCitationWithText:text
                                                   truncated:bundle.htmlTruncated || (bundle.htmlText.length > maxHtml)
                                                   pageTitle:bundle.title
                                                     pageURL:bundle.urlString];
    }
    if ([layerId isEqualToString:AIPageContextLayerMarkdown]) {
        NSString *text = [self truncateText:bundle.markdownText ?: @"" maxChars:maxArt];
        if (text.length == 0) return nil;
        return [AIAssistantCitation pageMarkdownCitationWithText:text
                                                       pageTitle:bundle.title
                                                         pageURL:bundle.urlString];
    }
    return nil;
}

+ (NSArray<AIAssistantCitation *> *)citationsFromBundle:(AIPageContextBundle *)bundle
                                                 layers:(NSArray<NSString *> *)layers
                                                 recipe:(AIPageContextRecipe *)recipe {
    if (!bundle || layers.count == 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *layer in layers) {
        AIAssistantCitation *c = [self citationForLayer:layer inBundle:bundle recipe:recipe];
        if (c) [out addObject:c];
    }
    return out;
}

+ (NSArray<AIAssistantCitation *> *)citationsFromBundle:(AIPageContextBundle *)bundle
                                                 recipe:(AIPageContextRecipe *)recipe {
    if (!bundle || !recipe) return @[];
    return [self citationsFromBundle:bundle layers:recipe.autoAttachLayers recipe:recipe];
}

+ (AIAssistantCitation *)citationForResource:(AIPageContextResource *)resource
                                    inBundle:(AIPageContextBundle *)bundle {
    if (!resource) return nil;
    AIAssistantCitationKind kind = AIAssistantCitationKindResourceScript;
    switch (resource.kind) {
        case AIPageContextResourceKindStylesheet: kind = AIAssistantCitationKindResourceStyle; break;
        case AIPageContextResourceKindJSON: kind = AIAssistantCitationKindResourceJSON; break;
        case AIPageContextResourceKindImage:
            return [AIAssistantCitation imageCitationWithURL:[NSURL URLWithString:resource.urlString ?: @""]
                                                       title:resource.label
                                               sourcePageURL:bundle.urlString.length ? [NSURL URLWithString:bundle.urlString] : nil
                                                   pageTitle:bundle.title];
        case AIPageContextResourceKindScript:
        case AIPageContextResourceKindOther:
        default: kind = AIAssistantCitationKindResourceScript; break;
    }
    NSString *body = resource.text ?: @"";
    if (body.length == 0 && resource.urlString.length) {
        body = [NSString stringWithFormat:@"（仅 URL，正文未加载）\n%@", resource.urlString];
    }
    body = [self truncateText:body maxChars:65536];
    return [AIAssistantCitation resourceCitationWithKind:kind
                                                   title:resource.chipLabel
                                                    body:body
                                                     url:resource.urlString
                                              resourceId:resource.resourceId
                                               pageTitle:bundle.title
                                                 pageURL:bundle.urlString];
}

+ (NSString *)trimCitations:(NSMutableArray<AIAssistantCitation *> *)citations
                 toMaxChars:(NSUInteger)maxTotalChars {
    if (citations.count == 0 || maxTotalChars == 0) return nil;
    NSUInteger total = 0;
    for (AIAssistantCitation *c in citations) {
        total += c.promptBlock.length;
    }
    if (total <= maxTotalChars) return nil;

    // 优先丢掉 HTML，再 Markdown，再 Outline，保留 meta/article
    NSArray<NSNumber *> *dropOrder = @[
        @(AIAssistantCitationKindPageHTML),
        @(AIAssistantCitationKindResourceScript),
        @(AIAssistantCitationKindResourceStyle),
        @(AIAssistantCitationKindResourceJSON),
        @(AIAssistantCitationKindPageMarkdown),
        @(AIAssistantCitationKindPageOutline),
    ];
    NSMutableArray *dropped = [NSMutableArray array];
    for (NSNumber *kindNum in dropOrder) {
        if (total <= maxTotalChars) break;
        AIAssistantCitationKind kind = (AIAssistantCitationKind)kindNum.integerValue;
        for (NSInteger i = (NSInteger)citations.count - 1; i >= 0; i--) {
            AIAssistantCitation *c = citations[(NSUInteger)i];
            if (c.kind != kind) continue;
            total -= c.promptBlock.length;
            [dropped addObject:c.kindDisplayName];
            [citations removeObjectAtIndex:(NSUInteger)i];
            break;
        }
    }
    // 仍超：截断剩余最大的 pageArticle / 其它
    while (total > maxTotalChars && citations.count > 1) {
        NSUInteger longestIdx = NSNotFound;
        NSUInteger longestLen = 0;
        for (NSUInteger i = 0; i < citations.count; i++) {
            AIAssistantCitation *c = citations[i];
            if (c.kind == AIAssistantCitationKindPageMeta) continue;
            NSUInteger len = c.promptBlock.length;
            if (len > longestLen) {
                longestLen = len;
                longestIdx = i;
            }
        }
        if (longestIdx == NSNotFound) break;
        AIAssistantCitation *victim = citations[longestIdx];
        total -= victim.promptBlock.length;
        [dropped addObject:victim.kindDisplayName];
        [citations removeObjectAtIndex:longestIdx];
    }
    if (dropped.count == 0) return @"上下文超长，已尽量裁剪";
    return [NSString stringWithFormat:@"上下文超长，已去掉：%@", [dropped componentsJoinedByString:@"、"]];
}

+ (NSString *)apiPromptWithRecipe:(AIPageContextRecipe *)recipe
                       citations:(NSArray<AIAssistantCitation *> *)citations
                        userText:(NSString *)userText {
    NSMutableString *out = [NSMutableString string];
    if (recipe.systemHint.length) {
        [out appendString:recipe.systemHint];
        [out appendString:@"\n\n"];
    }
    if (citations.count > 0) {
        [out appendString:@"以下是用户提供的上下文引用，请结合它们回答后面的问题：\n\n"];
        NSInteger i = 1;
        for (AIAssistantCitation *c in citations) {
            [out appendFormat:@"### 引用 %ld\n%@\n\n", (long)i, [c promptBlock]];
            i += 1;
        }
    }
    NSString *q = [userText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (q.length == 0 && recipe.userPrompt.length) {
        q = recipe.userPrompt;
    }
    [out appendString:@"### 用户问题\n"];
    [out appendString:q.length ? q : @"（请根据以上引用作答）"];
    return out;
}

@end
