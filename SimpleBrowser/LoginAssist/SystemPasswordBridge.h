#import <Cocoa/Cocoa.h>
#import <AuthenticationServices/AuthenticationServices.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SystemPasswordBridgeCompletion)(NSString * _Nullable username,
                                               NSString * _Nullable password,
                                               NSError * _Nullable error);

@interface SystemPasswordBridge : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>

- (void)requestPasswordWithAnchorWindow:(NSWindow *)window
                             completion:(SystemPasswordBridgeCompletion)completion;

@end

NS_ASSUME_NONNULL_END
