#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class BrowserTabController;

@interface BrowserWindowController : NSWindowController <WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate>

@property (nonatomic, readonly, nullable) WKWebView *webView;
@property (nonatomic, strong, readonly) BrowserTabController * _Nonnull tabController;

- (void)persistTabSession;
- (void)scheduleTrafficLightPositioning;
- (void)openURLsFromExternalSource:(NSArray<NSURL *> * _Nonnull)urls;
@end
