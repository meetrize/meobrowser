#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTranslationPresentationMode) {
    BrowserTranslationPresentationModeReplace = 0,
    BrowserTranslationPresentationModeBilingual,
    BrowserTranslationPresentationModeHover,
};

/// 抽取 → 翻译 → 按模式应用（Replace / Bilingual / Hover）。
@interface BrowserTranslationPipeline : NSObject

+ (instancetype)sharedPipeline;

- (BOOL)isTranslatingWebView:(WKWebView *)webView;

- (void)translateWebView:(WKWebView *)webView
        targetLocaleIdentifier:(NSString *)localeID
                          mode:(BrowserTranslationPresentationMode)mode
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion;

/// resumeIncomplete=YES：保留已上屏译文，只译尚未完成的段落（限流中断后续译）。
- (void)translateWebView:(WKWebView *)webView
        targetLocaleIdentifier:(NSString *)localeID
                          mode:(BrowserTranslationPresentationMode)mode
             resumeIncomplete:(BOOL)resumeIncomplete
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion;

- (void)cancelTranslationForWebView:(WKWebView *)webView;
- (void)cancelTranslationForWebView:(WKWebView *)webView
                      cancelMessage:(nullable NSString *)cancelMessage;

/// 清除页面上的双语/悬停注入（不 reload）。
- (void)clearPagePresentationInWebView:(WKWebView *)webView
                            completion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
