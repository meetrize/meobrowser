#import <Foundation/Foundation.h>
#import "AIBridgeDOMProvider.h"

@interface AIBridgeDOMProvider (PollingTest)
- (void)pollJobOnWebView:(WKWebView *)webView deadline:(NSDate *)deadline
              completion:(AIBridgeDOMCompletion)completion;
- (void)evaluate:(NSString *)script onWebView:(WKWebView *)webView
      completion:(void (^)(id, NSError *))completion;
@end

@interface PollProvider : AIBridgeDOMProvider
@property NSInteger calls;
@end

@implementation PollProvider
- (void)evaluate:(NSString *)script onWebView:(WKWebView *)webView
      completion:(void (^)(id, NSError *))completion {
    (void)script; (void)webView;
    self.calls++;
    NSInteger call = self.calls;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (call == 1) {
            completion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:nil]);
        } else if (call < 4) {
            completion(@{@"status": @"running", @"text": @"partial", @"baseline": @"complete"}, nil);
        } else {
            completion(@{@"status": @"done", @"result": @{@"ok": @YES, @"text": @"complete"}}, nil);
        }
    });
}
@end

int main(void) { @autoreleasepool {
    PollProvider *provider = [PollProvider new];
    __block NSDictionary *result = nil;
    __block NSInteger completions = 0;
    NSDate *start = [NSDate date];
    [provider pollJobOnWebView:(WKWebView *)[NSObject new]
                      deadline:[NSDate dateWithTimeIntervalSinceNow:4]
                    completion:^(NSDictionary *value, NSError *error) {
        (void)error;
        completions++;
        result = value;
    }];
    while (!result && -start.timeIntervalSinceNow < 3) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (![result[@"text"] isEqual:@"complete"] || provider.calls != 4 || completions != 1) {
        NSLog(@"poll failed: calls=%ld completions=%ld result=%@", (long)provider.calls, (long)completions, result);
        return 1;
    }
    NSLog(@"poll completed in %.2fs after %ld asynchronous checks", -start.timeIntervalSinceNow, (long)provider.calls);
    return 0;
} }
