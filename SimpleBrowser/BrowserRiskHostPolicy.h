#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 风险域策略：休眠保护与页面自动化脚本抑制（后缀匹配，避免 notgoogle.com 误命中）。
@interface BrowserRiskHostPolicy : NSObject

+ (BOOL)hostIsHibernationProtected:(nullable NSString *)host;
+ (BOOL)URLIsHibernationProtected:(nullable NSURL *)url;

+ (BOOL)hostShouldSuppressLoginAssist:(nullable NSString *)host;
+ (BOOL)URLShouldSuppressLoginAssist:(nullable NSURL *)url;

/// 与登录助手相同的人机页 / 风险域判定；供媒体捕获、验证码检测、Feed、查找等统一静默。
+ (BOOL)URLShouldSuppressPageAutomation:(nullable NSURL *)url;

/// 标题启发式：Managed Challenge / Turnstile 插页常见文案（业务域干净 URL 时 URL 启发式不够）。
+ (BOOL)titleLooksLikeChallenge:(nullable NSString *)title;

/// URL 或标题任一命中即抑制（供 PagePack / Feed / 透明模式等 Native 侧门禁）。
+ (BOOL)shouldSuppressPageAutomationForURL:(nullable NSURL *)url title:(nullable NSString *)title;

/// 供嵌入式 JS 使用的 host 后缀列表。
+ (NSArray<NSString *> *)loginAssistSuppressionHostSuffixes;
+ (NSArray<NSString *> *)pageAutomationSuppressionHostSuffixes;

/// 生成 `function <name>(){...}`，命中 Cloudflare / reCAPTCHA 等人机页或风险域时返回 true。
+ (NSString *)javaScriptShouldSuppressPageAutomationFunctionNamed:(NSString *)functionName;

@end

NS_ASSUME_NONNULL_END
