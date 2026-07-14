#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTab : NSObject

@property (nonatomic, readonly) NSUUID *tabID;
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL isNewTabPage;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign, readonly) NSInteger titleUpdateGeneration;
/// 地址栏未提交输入草稿；nil 表示使用规范展示（新标签页为空，普通页为当前 URL）。
@property (nonatomic, copy, nullable) NSString *addressBarDraft;

+ (instancetype)tabWithConfiguration:(WKWebViewConfiguration *)configuration;

- (void)loadNewTabPage;
- (void)loadURL:(NSURL *)url;
- (NSString *)displayTitle;

- (void)notePendingMainFrameNavigation;
- (BOOL)beginMainFrameNavigation:(WKNavigation *)navigation;
- (BOOL)isMainFrameNavigation:(WKNavigation *)navigation;
- (void)endMainFrameNavigation:(WKNavigation *)navigation;

@end

NS_ASSUME_NONNULL_END
