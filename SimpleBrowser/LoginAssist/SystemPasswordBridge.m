#import "SystemPasswordBridge.h"

@interface SystemPasswordBridge ()
@property (nonatomic, copy, nullable) SystemPasswordBridgeCompletion completion;
@property (nonatomic, weak, nullable) NSWindow *anchorWindow;
@end

@implementation SystemPasswordBridge

- (void)requestPasswordWithAnchorWindow:(NSWindow *)window
                             completion:(SystemPasswordBridgeCompletion)completion {
    self.completion = completion;
    self.anchorWindow = window;

    if (@available(macOS 11.0, *)) {
        ASAuthorizationPasswordProvider *provider = [[ASAuthorizationPasswordProvider alloc] init];
        ASAuthorizationPasswordRequest *request = [provider createRequest];
        ASAuthorizationController *controller =
            [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ request ]];
        controller.delegate = self;
        controller.presentationContextProvider = self;
        [controller performRequests];
    } else {
        if (completion) {
            completion(nil, nil, [NSError errorWithDomain:@"SystemPasswordBridge"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"当前系统版本不支持密码选择器"}]);
        }
        self.completion = nil;
    }
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller API_AVAILABLE(macos(11.0)) {
    (void)controller;
    return self.anchorWindow ?: NSApp.keyWindow ?: NSApp.windows.firstObject;
}

- (void)authorizationController:(ASAuthorizationController *)controller
   didCompleteWithAuthorization:(ASAuthorization *)authorization API_AVAILABLE(macos(11.0)) {
    (void)controller;
    SystemPasswordBridgeCompletion completion = self.completion;
    self.completion = nil;
    if ([authorization.credential isKindOfClass:[ASPasswordCredential class]]) {
        ASPasswordCredential *credential = (ASPasswordCredential *)authorization.credential;
        if (completion) {
            completion(credential.user, credential.password, nil);
        }
        return;
    }
    if (completion) {
        completion(nil, nil, [NSError errorWithDomain:@"SystemPasswordBridge"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey: @"未获得密码凭证"}]);
    }
}

- (void)authorizationController:(ASAuthorizationController *)controller
           didCompleteWithError:(NSError *)error API_AVAILABLE(macos(11.0)) {
    (void)controller;
    SystemPasswordBridgeCompletion completion = self.completion;
    self.completion = nil;
    if (completion) {
        completion(nil, nil, error);
    }
}

@end
