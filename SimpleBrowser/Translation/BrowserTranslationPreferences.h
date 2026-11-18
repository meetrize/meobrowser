#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserTranslationPreferencesDidChangeNotification;

/// Index-Translate 公开 / 自建 OpenAI 兼容 API（默认）：POST {base}/chat/completions
FOUNDATION_EXPORT NSString * const BrowserTranslationProviderIndexTranslate;
/// MTranServer 兼容后端：POST {base}/translate · /translate/batch
FOUNDATION_EXPORT NSString * const BrowserTranslationProviderMTran;
/// 内置 Google 文本 API + Lingva 回退
FOUNDATION_EXPORT NSString * const BrowserTranslationProviderGoogle;

FOUNDATION_EXPORT NSString * const BrowserTranslationDefaultIndexTranslateBaseURL;
FOUNDATION_EXPORT NSString * const BrowserTranslationDefaultMTranBaseURL;
FOUNDATION_EXPORT NSString * const BrowserTranslationDefaultIndexTranslateModel;

/// 网页翻译后端偏好（地址栏替换 / 双语对照 / 即指即译共用）。
@interface BrowserTranslationPreferences : NSObject

+ (instancetype)sharedPreferences;

/// `BrowserTranslationProviderIndexTranslate` / `MTran` / `Google`。
@property (nonatomic, copy) NSString *provider;

/// Index / MTran 根地址（无尾斜杠）。随 provider 切换展示对应默认值。
@property (nonatomic, copy) NSString *apiBaseURL;

/// 可选；非空时请求带 `Authorization: Bearer …`。Index 公开 API 可留空。
@property (nonatomic, copy) NSString *apiToken;

/// Index-Translate 模型 ID，默认 `Index-Translate-2B`。
@property (nonatomic, copy) NSString *model;

+ (NSString *)displayNameForProvider:(NSString *)provider;
+ (NSArray<NSString *> *)availableProviders;
+ (NSString *)defaultAPIBaseURLForProvider:(NSString *)provider;
+ (NSArray<NSString *> *)availableIndexTranslateModels;
+ (NSString *)displayNameForIndexTranslateModel:(NSString *)model;

/// 规范化根地址：去空白、去尾 `/`；空则回当前 provider 默认。
- (NSString *)normalizedAPIBaseURL;

@end

NS_ASSUME_NONNULL_END
