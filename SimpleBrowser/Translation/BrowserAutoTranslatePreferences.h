#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserAutoTranslatePreferencesDidChangeNotification;

/// 打开即译偏好：指定站点、或「所有英文网站」；显式关闭的站点优先。
@interface BrowserAutoTranslatePreferences : NSObject

+ (instancetype)sharedPreferences;

/// 是否对所有英文网页自动翻译（可被「本站关闭」覆盖）。
@property (nonatomic, assign) BOOL alwaysTranslateEnglish;

/// 规范化 host（小写、去 www. 可选保留）。空则返回 nil。
+ (nullable NSString *)normalizedHostFromURL:(nullable NSURL *)url;

/// 当前 URL 是否应自动翻译。pageLanguage 可为 `en` / `zh` / 空（未知）。
- (BOOL)shouldAutoTranslateURL:(nullable NSURL *)url pageLanguage:(nullable NSString *)pageLanguage;

/// 勾选态：本站已开启，或（全英文开启且本站未显式关闭）。
- (BOOL)isAutoTranslateCheckedForURL:(nullable NSURL *)url pageLanguage:(nullable NSString *)pageLanguage;

/// 用户勾选「默认翻译」：开启本站。
- (void)enableAutoTranslateForURL:(nullable NSURL *)url;

/// 用户取消勾选：关闭本站（即使「所有英文」开启也不译本站）。
- (void)disableAutoTranslateForURL:(nullable NSURL *)url;

- (BOOL)isHostExplicitlyEnabled:(nullable NSString *)host;
- (BOOL)isHostExplicitlyDisabled:(nullable NSString *)host;

/// 页面语言是否视为英文（或其它非中文外语，适合自动译）。
+ (BOOL)isForeignLanguageWorthAutoTranslating:(nullable NSString *)pageLanguage;

@end

NS_ASSUME_NONNULL_END
