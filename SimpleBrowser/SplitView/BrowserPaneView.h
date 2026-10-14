#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserPaneChromeMode) {
    BrowserPaneChromeAlways = 0,
    BrowserPaneChromeAutohide = 1, // 默认:hover 显示
    BrowserPaneChromeHidden = 2,
};

/// MW2: 每栏独立地址栏 + 独立 WKWebView 宿主。
@interface BrowserPaneView : NSView <NSTextFieldDelegate>
@property (nonatomic, assign) NSInteger paneIndex;
@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, assign) BrowserPaneChromeMode chromeMode;
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, strong, readonly) NSView *contentHost;
@property (nonatomic, strong, readonly) NSTextField *addressField;
@property (nonatomic, copy, nullable) void (^openURLHandler)(NSInteger paneIndex, NSURL *url);
@property (nonatomic, copy, nullable) void (^becameActiveHandler)(NSInteger paneIndex);
- (instancetype)initWithIndex:(NSInteger)index;
- (void)attachWebView:(WKWebView *)webView;
- (void)detachWebView;
- (void)setPlaceholderURL:(nullable NSURL *)url;
- (void)loadURL:(NSURL *)url;
- (void)updateAddressFieldWithURL:(nullable NSURL *)url;
- (void)setSyncBadge:(nullable NSString *)badge;
- (void)setActiveAndReveal:(BOOL)active;
@end

NS_ASSUME_NONNULL_END
