#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperDetector : NSObject

/// 在当前页启发式检测表格 / ul·li / 同构卡片候选。
+ (void)detectCandidatesInWebView:(WKWebView *)webView
                       completion:(void (^)(NSArray<NSDictionary *> *candidates))completion;

/// 针对已选容器（或其中某节点）分析循环行：表格行 / 列表项 / 同构 div 卡片，并推断字段。
+ (void)analyzeContainerInWebView:(WKWebView *)webView
                    containerPath:(NSString *)containerPath
                       completion:(void (^)(NSDictionary * _Nullable analysis, NSError * _Nullable error))completion;

/// 按 recipe 字段定义抽取当前页行数据。
+ (void)extractRowsInWebView:(WKWebView *)webView
                        mode:(NSString *)mode
               containerPath:(NSString *)containerPath
                     rowPath:(NSString *)rowPath
                      fields:(NSArray<NSDictionary *> *)fields
               absoluteURLs:(BOOL)absoluteURLs
                     maxRows:(NSInteger)maxRows
                  completion:(void (^)(NSArray<NSDictionary *> *rows, NSError * _Nullable error))completion;

+ (NSString *)waitForSelectorJavaScript:(NSString *)selector timeoutMs:(NSInteger)timeoutMs;

@end

NS_ASSUME_NONNULL_END
