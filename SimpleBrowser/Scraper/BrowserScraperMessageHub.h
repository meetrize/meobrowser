#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserScraperSidebarController;

/// 全局转发 meoScraperPick 消息。
@interface BrowserScraperMessageHub : NSObject <WKScriptMessageHandler>

+ (instancetype)sharedHub;
@property (nonatomic, weak, nullable) BrowserScraperSidebarController *activeSidebar;

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
