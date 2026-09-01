#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class LoginCredentials;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LoginFormInlineHandlerName;

@interface LoginFormDetector : NSObject

+ (NSString *)userScriptSource;
+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
               messageHandler:(id<WKScriptMessageHandler>)handler;

/// 将字段级「＋ / 填入」状态注入页面（perField 模式）。
+ (NSString *)javaScriptSettingFieldAssistTargets:(NSArray<NSDictionary *> *)targets;

/// 根据匹配 Recipe + 凭证 + 页面检测到的 slots 生成 targets。
+ (NSArray<NSDictionary *> *)fieldAssistTargetDictionariesForRecipe:(nullable LoginRecipe *)recipe
                                                       credentials:(nullable LoginCredentials *)credentials
                                                    detectedSlots:(nullable NSArray *)detectedSlots
                                          extraFieldInlineEnabled:(BOOL)extraEnabled;

@end

NS_ASSUME_NONNULL_END
