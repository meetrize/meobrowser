#import "LoginAssistScriptMessageProxy.h"

@implementation LoginAssistScriptMessageProxy

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    id<WKScriptMessageHandler> target = self.target;
    if ([target respondsToSelector:@selector(userContentController:didReceiveScriptMessage:)]) {
        [target userContentController:userContentController didReceiveScriptMessage:message];
    }
}

@end
