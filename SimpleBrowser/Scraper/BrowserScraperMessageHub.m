#import "BrowserScraperMessageHub.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserScraperSidebarController.h"

@implementation BrowserScraperMessageHub

+ (instancetype)sharedHub {
    static BrowserScraperMessageHub *hub;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hub = [[self alloc] init];
    });
    return hub;
}

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    [BrowserScraperElementPicker registerMessageHandlerOnConfiguration:configuration
                                                               handler:[self sharedHub]];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:@"meoScraperPick"]) return;
    [BrowserScraperElementPicker handleScriptMessageBody:message.body];
    BrowserScraperSidebarController *sidebar = self.activeSidebar;
    if (sidebar) {
        // handleScriptMessageBody 已触发 completion；此处无需重复
        (void)sidebar;
    }
}

@end
