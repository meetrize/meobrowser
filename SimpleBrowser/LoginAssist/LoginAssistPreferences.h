#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const LoginAssistPreferencesDidChangeNotification;

typedef NSString *LoginFieldInlineMode NS_TYPED_EXTENSIBLE_ENUM;
/// 每个登录相关字段显示「＋ / 填入」（默认）。
FOUNDATION_EXPORT LoginFieldInlineMode const LoginFieldInlineModePerField;
/// V1.5：仅密码框旁一枚钥匙，点击弹菜单。
FOUNDATION_EXPORT LoginFieldInlineMode const LoginFieldInlineModeLegacySingleKey;

@interface LoginAssistPreferences : NSObject

+ (BOOL)inlineAssistEnabled;
+ (void)setInlineAssistEnabled:(BOOL)enabled;

+ (BOOL)promptSaveOnSuccess;
+ (void)setPromptSaveOnSuccess:(BOOL)enabled;

/// 内联图标密度。默认 `LoginFieldInlineModePerField`。新标签 / 新导航后生效。
+ (LoginFieldInlineMode)loginFieldInlineMode;
+ (void)setLoginFieldInlineMode:(LoginFieldInlineMode)mode;

/// 是否在登录上下文中为非帐密/手机/OTP 的额外文本框显示图标。默认 NO。
+ (BOOL)loginExtraFieldInlineEnabled;
+ (void)setLoginExtraFieldInlineEnabled:(BOOL)enabled;

+ (BOOL)shouldSuppressSavePromptForHost:(NSString *)host;
+ (void)setSuppressSavePrompt:(BOOL)suppress forHost:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
