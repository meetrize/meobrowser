#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AIBridgeToolSimKind) {
    AIBridgeToolSimKindMessage = 0,
    AIBridgeToolSimKindToolCalls = 1,
};

@interface AIBridgeToolSimResult : NSObject
@property (nonatomic, assign) AIBridgeToolSimKind kind;
@property (nonatomic, copy, nullable) NSString *content;
/// OpenAI 形态：[{id,type,function:{name,arguments}}]，arguments 已是 JSON 字符串
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *toolCalls;
@property (nonatomic, copy, nullable) NSString *parseError;
@end

@interface AIBridgeToolSimulator : NSObject

/// tools 非空且 tool_choice 不是 "none"
+ (BOOL)shouldEnableForRequest:(NSDictionary *)json;

/// tool_choice 为 required / 指定 function 时，只允许 tool_calls
+ (BOOL)requiresToolCallsForRequest:(NSDictionary *)json;

/// 自包含网页提示词（含 tools + 压缩 messages）
+ (NSString *)buildWebpagePromptFromRequest:(NSDictionary *)json;

/// 解析失败后的修复提示（附带上次原文片段）
+ (NSString *)buildRepairPromptFromRequest:(NSDictionary *)json
                              previousText:(NSString *)previousText;

/// 解析网页正文 → message 或 tool_calls；失败时 result.parseError 非空
+ (AIBridgeToolSimResult *)parseWebpageText:(NSString *)text
                                 forRequest:(NSDictionary *)json;

/// 提示词最大字符（保护网页输入框）
+ (NSUInteger)maxPromptChars;

@end

NS_ASSUME_NONNULL_END
