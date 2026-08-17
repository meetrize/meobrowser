#import "BrowserInPageTranslator.h"
#import "BrowserTranslationPipeline.h"

@implementation BrowserInPageTranslator

+ (instancetype)sharedTranslator {
    static BrowserInPageTranslator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserInPageTranslator alloc] init];
    });
    return shared;
}

- (BOOL)isTranslatingWebView:(WKWebView *)webView {
    return [[BrowserTranslationPipeline sharedPipeline] isTranslatingWebView:webView];
}

- (void)cancelTranslationForWebView:(WKWebView *)webView {
    [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
}

- (void)translateWebView:(WKWebView *)webView
  targetLocaleIdentifier:(NSString *)localeID
              completion:(void (^)(BOOL, NSString * _Nullable))completion {
    [[BrowserTranslationPipeline sharedPipeline] translateWebView:webView
                                           targetLocaleIdentifier:localeID
                                                             mode:BrowserTranslationPresentationModeReplace
                                                       completion:completion];
}

@end
