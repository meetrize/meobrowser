#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperTransformContext : NSObject
@property (nonatomic, strong) NSDate *now;
@property (nonatomic, copy, nullable) NSString *baseURL;
@property (nonatomic, copy) NSString *onError; // empty | raw
+ (instancetype)defaultContext;
@end

/// 字段值规范化：对 transforms 步骤数组求值（可嵌套 op 节点）。
@interface BrowserScraperValueTransform : NSObject

/// 对单字段原文应用步骤管线；rowSoFar 供 field 引用（按字段顺序累积）。
+ (NSString *)applyTransforms:(nullable NSArray *)transforms
                     rawValue:(nullable NSString *)rawValue
                          row:(nullable NSDictionary *)rowSoFar
                      context:(nullable BrowserScraperTransformContext *)context;

/// 对整行：按 fields 顺序抽取名→值后做 transforms（输入已是原始行字典）。
+ (NSDictionary *)normalizeRow:(NSDictionary *)rawRow
                        fields:(NSArray *)fields
                       context:(nullable BrowserScraperTransformContext *)context;

/// 批量规范化。
+ (NSArray<NSDictionary *> *)normalizeRows:(NSArray<NSDictionary *> *)rows
                                    fields:(NSArray *)fields
                                   context:(nullable BrowserScraperTransformContext *)context;

/// 步骤摘要，供表格「处理」列展示。
+ (NSString *)summaryForTransforms:(nullable NSArray *)transforms;

/// 预设模板：name → steps
+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)presetTemplates;

+ (NSArray<NSDictionary *> *)catalog; // [{op,title,group,help,usage,example}]

/// 完整函数说明文稿（供帮助面板展示）。
+ (NSString *)helpDocumentText;

@end

NS_ASSUME_NONNULL_END
