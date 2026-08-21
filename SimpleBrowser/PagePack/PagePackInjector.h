#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class PagePack;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PagePackInjectionPhase) {
    PagePackInjectionPhaseDocumentStart = 0,
    PagePackInjectionPhaseDocumentEnd = 1,
};

@interface PagePackInjector : NSObject

+ (instancetype)sharedInjector;

/// didCommit：CSS + document-start JS
- (void)injectMatchingPacksIntoWebView:(WKWebView *)webView
                                   URL:(nullable NSURL *)url
                                 phase:(PagePackInjectionPhase)phase;

/// 热更新单个 Pack（CSS 替换 + 重跑全部 JS）。
- (void)hotApplyPack:(PagePack *)pack
           toWebView:(WKWebView *)webView
                 URL:(nullable NSURL *)url;

/// 移除某 Pack 已注入的 CSS 节点。
- (void)removeCSSForPackID:(NSString *)packID fromWebView:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
