#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const FormMemoInlineHandlerName;

@class FormMemo;

@interface FormMemoInlineDetector : NSObject

+ (NSString *)userScriptSource;
+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
               messageHandler:(id<WKScriptMessageHandler>)handler;

/// 将匹配备忘的字段选择器注入页面，用于显示「↓」一键填入图标。
+ (NSString *)javaScriptSettingFillTargets:(NSArray<NSDictionary *> *)targets;
+ (NSString *)javaScriptSettingFillTargets:(NSArray<NSDictionary *> *)targets hasMemo:(BOOL)hasMemo;
+ (NSArray<NSDictionary *> *)fillTargetDictionariesFromMemo:(nullable FormMemo *)memo;

@end

NS_ASSUME_NONNULL_END
