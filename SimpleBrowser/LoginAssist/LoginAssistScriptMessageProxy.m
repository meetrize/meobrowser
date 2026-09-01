#import "LoginAssistScriptMessageProxy.h"

@implementation LoginAssistScriptMessageProxy

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    id<WKScriptMessageHandler> target = self.target;
    if (![target respondsToSelector:@selector(userContentController:didReceiveScriptMessage:)]) {
        return;
    }
    // WK 可能在后台线程回调；UI / 凭证读写必须在主线程。
    if ([NSThread isMainThread]) {
        [target userContentController:userContentController didReceiveScriptMessage:message];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [target userContentController:userContentController didReceiveScriptMessage:message];
    });
}

@end
