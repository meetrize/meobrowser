#import "BrowserWebViewPickCoordinator.h"

NSNotificationName const BrowserWebViewPickCoordinatorDidYieldNotification = @"BrowserWebViewPickCoordinatorDidYieldNotification";
NSString * const BrowserWebViewPickYieldedOwnerKey = @"owner";

@interface BrowserWebViewPickCoordinator ()
@property (nonatomic, weak, nullable) id currentOwner;
@end

@implementation BrowserWebViewPickCoordinator

+ (BrowserWebViewPickCoordinator *)shared {
    static BrowserWebViewPickCoordinator *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserWebViewPickCoordinator alloc] init];
    });
    return shared;
}

- (BOOL)beginPickInWebView:(WKWebView *)webView owner:(id)owner {
    if (!owner) {
        return NO;
    }
    id previous = self.currentOwner;
    if (previous && previous != owner) {
        self.currentOwner = nil;
        if ([previous respondsToSelector:@selector(browserWebViewPickCoordinatorDidYield:)]) {
            [previous browserWebViewPickCoordinatorDidYield:owner];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:BrowserWebViewPickCoordinatorDidYieldNotification
                                                            object:self
                                                          userInfo:@{BrowserWebViewPickYieldedOwnerKey: previous}];
        if (self.currentOwner == previous) {
            // 旧 owner 没有主动退出（协议未实现），放弃本次申请。
            return NO;
        }
    }
    self.currentOwner = owner;
    return YES;
}

- (void)endPickForOwner:(id)owner {
    if (owner && self.currentOwner == owner) {
        self.currentOwner = nil;
    }
}

- (BOOL)isCurrentOwner:(id)owner {
    return owner != nil && self.currentOwner == owner;
}

@end
