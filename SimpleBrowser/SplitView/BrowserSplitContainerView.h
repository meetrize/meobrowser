#import <Cocoa/Cocoa.h>
#import "BrowserSplitLayout.h"
#import <WebKit/WebKit.h>

@class BrowserPaneView;

NS_ASSUME_NONNULL_BEGIN

/// 分栏容器:按 layout+weights 排布 panes,细 divider 拖拽改比例。
@interface BrowserSplitContainerView : NSView
@property (nonatomic, assign) BrowserSplitLayoutID layoutID;
@property (nonatomic, copy) NSArray<NSNumber *> *weights;
@property (nonatomic, strong, readonly) NSArray<BrowserPaneView *> *panes;
@property (nonatomic, assign) NSInteger activePaneIndex;
@property (nonatomic, copy, nullable) void (^weightsDidChangeHandler)(NSArray<NSNumber *> *weights);
- (void)applyLayout:(BrowserSplitLayoutID)layout weights:(nullable NSArray<NSNumber *> *)weights urls:(nullable NSArray *)urls;
- (void)focusPaneAtIndex:(NSInteger)index;
- (void)bindWebViewsWithConfiguration:(WKWebViewConfiguration *)config
                   navigationDelegate:(nullable id<WKNavigationDelegate>)navDelegate
                           uiDelegate:(nullable id<WKUIDelegate>)uiDelegate
                      openURLHandler:(void (^)(NSInteger paneIndex, NSURL *url))handler
                     activeHandler:(void (^)(NSInteger paneIndex))activeHandler;
- (void)loadURLs:(nullable NSArray *)urls;
- (void)setChromeMode:(NSInteger)mode forPane:(NSInteger)paneIndex; // -1 = all
@end

NS_ASSUME_NONNULL_END
