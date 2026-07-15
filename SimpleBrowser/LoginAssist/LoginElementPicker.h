#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LoginElementPickerCompletion)(NSString * _Nullable cssSelector, BOOL cancelled);

@interface LoginElementPicker : NSObject

+ (void)registerMessageHandlerOnConfiguration:(WKWebViewConfiguration *)configuration
                                     handler:(id<WKScriptMessageHandler>)handler;

+ (void)startPickingInWebView:(WKWebView *)webView
                   completion:(LoginElementPickerCompletion)completion;

+ (void)handleScriptMessageBody:(id)body;
+ (void)cancelActivePick;

@end

NS_ASSUME_NONNULL_END
