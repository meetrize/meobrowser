#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserTranslationPreferencesDidChangeNotification;

/// MTranServer 兼容后端（默认）：POST {base}/translate · /translate/batch
FOUNDATION_EXPORT NSString * const BrowserTranslationProviderMTran;
/// 内置 Google 文本 API + Lingva 回退
FOUNDATION_EXPORT NSString * const BrowserTranslationProviderGoogle;

FOUNDATION_EXPORT NSString * const BrowserTranslationDefaultMTranBaseURL;

/// 网页翻译后端偏好（地址栏替换 / 双语对照 / 即指即译共用）。
@interface BrowserTranslationPreferences : NSObject

+ (instancetype)sharedPreferences;

/// `BrowserTranslationProviderMTran` 或 `BrowserTranslationProviderGoogle`。
@property (nonatomic, copy) NSString *provider;

/// MTranServer 根地址，默认 `http://192.168.31.111:8989`（无尾斜杠）。
@property (nonatomic, copy) NSString *apiBaseURL;

/// 可选；非空时请求带 `Authorization: Bearer …`。
@property (nonatomic, copy) NSString *apiToken;

+ (NSString *)displayNameForProvider:(NSString *)provider;
+ (NSArray<NSString *> *)availableProviders;

/// 规范化根地址：去空白、去尾 `/`；空则回默认。
- (NSString *)normalizedAPIBaseURL;

@end

NS_ASSUME_NONNULL_END
