#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 风险域策略：休眠保护与登录助手抑制（后缀匹配，避免 notgoogle.com 误命中）。
@interface BrowserRiskHostPolicy : NSObject

+ (BOOL)hostIsHibernationProtected:(nullable NSString *)host;
+ (BOOL)URLIsHibernationProtected:(nullable NSURL *)url;

+ (BOOL)hostShouldSuppressLoginAssist:(nullable NSString *)host;
+ (BOOL)URLShouldSuppressLoginAssist:(nullable NSURL *)url;

/// 供嵌入式 JS 使用的 host 后缀列表（JSON 数组字面量内容不含外层括号时用 joined）。
+ (NSArray<NSString *> *)loginAssistSuppressionHostSuffixes;

@end

NS_ASSUME_NONNULL_END
