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

+ (NSString *)promptForAction:(NSString *)actionKey selection:(NSString *)selection {
    NSString *text = selection ?: @"";
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

+ (NSString *)displayTitleForAction:(NSString *)actionKey {
    if ([actionKey isEqualToString:BrowserAIAssistantActionExplain]) return @"解释";
    if ([actionKey isEqualToString:BrowserAIAssistantActionSummarize]) return @"总结";
    if ([actionKey isEqualToString:BrowserAIAssistantActionTranslate]) return @"翻译成中文";
    return @"问问 AI";
}

@end
