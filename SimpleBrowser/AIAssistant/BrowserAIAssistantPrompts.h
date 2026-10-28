#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 划词动作：ask | explain | summarize | translate
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionAsk;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionExplain;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionSummarize;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionTranslate;

@interface BrowserAIAssistantPrompts : NSObject

+ (NSArray<NSDictionary *> *)providerCatalog; // id, title（不含 mock）

+ (NSString *)promptForAction:(NSString *)actionKey selection:(NSString *)selection;

+ (NSString *)displayTitleForAction:(NSString *)actionKey;

@end

NS_ASSUME_NONNULL_END
