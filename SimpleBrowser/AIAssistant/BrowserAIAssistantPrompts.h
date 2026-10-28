#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 划词 / 页面动作：ask | explain | summarize | translate
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionAsk;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionExplain;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionSummarize;
FOUNDATION_EXPORT NSString * const BrowserAIAssistantActionTranslate;

@interface BrowserAIAssistantPrompts : NSObject

+ (NSArray<NSDictionary *> *)providerCatalog; // id, title（不含 mock）

/// context：选中文本，或页面上下文（标题+URL）。
/// pageContext=YES 表示无选区、以当前页为上下文。
+ (NSString *)promptForAction:(NSString *)actionKey
                      context:(NSString *)context
                  pageContext:(BOOL)pageContext;

+ (NSString *)displayTitleForAction:(NSString *)actionKey pageContext:(BOOL)pageContext;

@end

NS_ASSUME_NONNULL_END
