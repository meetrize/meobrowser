#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserTabController;
@class BrowserTab;
@class BrowserTabStripView;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserWindowController : NSWindowController <WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate>

@property (nonatomic, readonly, nullable) WKWebView *webView;
@property (nonatomic, strong, readonly) BrowserTabController *tabController;
@property (nonatomic, strong, readonly) BrowserTabStripView *tabStripView;

- (instancetype)initWithSessionDictionary:(nullable NSDictionary *)session;
- (instancetype)init;
/// 创建空窗口（无标签），供 adoptTab: 迁入已有标签（保留 WKWebView）。
- (instancetype)initForTabAdoption;
- (void)adoptTab:(BrowserTab *)tab;
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;
/// 将本窗标签真迁移到另一浏览器窗指定下标。
- (void)transferTabID:(NSUUID *)tabID
             toWindow:(BrowserWindowController *)destination
              atIndex:(NSUInteger)index;

- (void)persistTabSession;
/// 当前窗口会话快照（tabs / selectedIndex / pinnedCount / frame）。
- (NSDictionary *)sessionDictionary;
/// 用会话字典恢复标签与可选窗口 frame；session 为空或无效时打开 NTP。
- (void)applySessionDictionary:(nullable NSDictionary *)session;
- (void)scheduleTrafficLightPositioning;
- (void)openURLsFromExternalSource:(NSArray<NSURL *> *)urls;
@end

NS_ASSUME_NONNULL_END
