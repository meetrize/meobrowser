#import "BrowserAIAssistantPrompts.h"

NSString * const BrowserAIAssistantActionAsk = @"ask";
NSString * const BrowserAIAssistantActionExplain = @"explain";
NSString * const BrowserAIAssistantActionSummarize = @"summarize";
NSString * const BrowserAIAssistantActionTranslate = @"translate";

@implementation BrowserAIAssistantPrompts

+ (NSArray<NSDictionary *> *)providerCatalog {
    return @[
        @{@"id": @"deepseek", @"title": @"DeepSeek 网页"},
        @{@"id": @"kimi", @"title": @"Kimi 网页"},
        @{@"id": @"iwencai", @"title": @"问财 网页"},
        @{@"id": @"doubao", @"title": @"豆包 网页"},
        @{@"id": @"gemini", @"title": @"Gemini 网页"},
        @{@"id": @"chatgpt", @"title": @"ChatGPT 网页"},
    ];
}

+ (NSString *)promptForAction:(NSString *)actionKey
                      context:(NSString *)context
                  pageContext:(BOOL)pageContext {
    NSString *text = context ?: @"";
    if (pageContext) {
        if ([actionKey isEqualToString:BrowserAIAssistantActionExplain]) {
            return [NSString stringWithFormat:
                    @"请根据下面的网页信息，解释这可能是什么站点或页面、主要用途是什么：\n\n%@", text];
        }
        if ([actionKey isEqualToString:BrowserAIAssistantActionSummarize]) {
            return [NSString stringWithFormat:
                    @"请根据下面的网页信息，推测并总结该页面可能的主题与要点（仅依据给定信息）：\n\n%@", text];
        }
        if ([actionKey isEqualToString:BrowserAIAssistantActionTranslate]) {
            return [NSString stringWithFormat:
                    @"请用简体中文说明下面这个网页地址/标题的含义（站点名、路径含义等）：\n\n%@", text];
        }
        return [NSString stringWithFormat:
                @"请基于下面的网页信息回答：这是什么页面？可能提供什么内容？\n\n%@", text];
    }

    if ([actionKey isEqualToString:BrowserAIAssistantActionExplain]) {
        return [NSString stringWithFormat:@"请解释下面这段文字：\n\n%@", text];
    }
    if ([actionKey isEqualToString:BrowserAIAssistantActionSummarize]) {
        return [NSString stringWithFormat:@"请总结下面这段文字的要点：\n\n%@", text];
    }
    if ([actionKey isEqualToString:BrowserAIAssistantActionTranslate]) {
        return [NSString stringWithFormat:@"请将下面这段文字翻译成简体中文：\n\n%@", text];
    }
    return text;
}

+ (NSString *)displayTitleForAction:(NSString *)actionKey pageContext:(BOOL)pageContext {
    if (pageContext) {
        if ([actionKey isEqualToString:BrowserAIAssistantActionExplain]) return @"解释此页";
        if ([actionKey isEqualToString:BrowserAIAssistantActionSummarize]) return @"总结此页";
        if ([actionKey isEqualToString:BrowserAIAssistantActionTranslate]) return @"说明网址";
        return @"问问此页";
    }
    if ([actionKey isEqualToString:BrowserAIAssistantActionExplain]) return @"解释选区";
    if ([actionKey isEqualToString:BrowserAIAssistantActionSummarize]) return @"总结选区";
    if ([actionKey isEqualToString:BrowserAIAssistantActionTranslate]) return @"翻译选区";
    return @"问问选区";
}

@end
