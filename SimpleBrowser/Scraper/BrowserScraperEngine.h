#import <WebKit/WebKit.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@class BrowserScraperEngine;

@protocol BrowserScraperEngineDelegate <NSObject>
@optional
- (void)scraperEngine:(BrowserScraperEngine *)engine didAppendRows:(NSArray<NSDictionary *> *)rows totalRows:(NSInteger)totalRows page:(NSInteger)page;
- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line;
- (void)scraperEngine:(BrowserScraperEngine *)engine didFinishWithRunDirectory:(NSString *)runDirectory error:(NSError * _Nullable)error;
@end

@interface BrowserScraperEngine : NSObject

@property (nonatomic, weak, nullable) id<BrowserScraperEngineDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL running;
@property (nonatomic, assign, readonly) BOOL paused;
/// 试运行：按翻页设置爬取，最多 10 页，不写出 Excel/MySQL。
@property (nonatomic, assign, readonly) BOOL trialMode;
@property (nonatomic, copy, readonly, nullable) NSString *currentRunDirectory;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *previewRows;

- (void)startWithRecipe:(BrowserScraperRecipe *)recipe
                webView:(WKWebView *)webView;
/// 试运行：沿用当前翻页配置，maxPages 上限 10，不写 sink。
- (void)startTrialWithRecipe:(BrowserScraperRecipe *)recipe
                     webView:(WKWebView *)webView;
- (void)pause;
- (void)resume;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
