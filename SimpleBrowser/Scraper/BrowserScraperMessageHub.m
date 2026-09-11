#import "BrowserScraperMessageHub.h"
#import "BrowserScraperElementPicker.h"
#import "BrowserScraperCandidateOverlay.h"
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
    // 候选标注层消息：转给侧栏，不走点选 completion
    if ([BrowserScraperCandidateOverlay isSelectCandidateMessage:message.body]) {
        BrowserScraperSidebarController *sidebar = self.activeSidebar;
        if (sidebar) {
            [sidebar handleCandidateOverlayMessage:message.body];
        }
        return;
    }
    [BrowserScraperElementPicker handleScriptMessageBody:message.body];
}

@end
