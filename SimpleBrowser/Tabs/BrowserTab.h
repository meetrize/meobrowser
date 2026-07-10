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
