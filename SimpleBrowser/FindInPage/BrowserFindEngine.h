#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "BrowserFindSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFindResult : NSObject
@property (nonatomic, assign) NSInteger matchCount;
@property (nonatomic, assign) NSInteger currentIndex; // 1-based
@property (nonatomic, assign) BOOL wrapped;
@property (nonatomic, assign) BOOL truncated;
@property (nonatomic, assign) BOOL invalidQuery;
@end

@interface BrowserFindEngine : NSObject

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

+ (void)searchInWebView:(WKWebView *)webView
                  query:(NSString *)query
                   mode:(BrowserFindMode)mode
          caseSensitive:(BOOL)caseSensitive
             completion:(void (^)(BrowserFindResult *result))completion;

+ (void)nextInWebView:(WKWebView *)webView
           completion:(void (^)(BrowserFindResult *result))completion;

+ (void)previousInWebView:(WKWebView *)webView
               completion:(void (^)(BrowserFindResult *result))completion;

+ (void)clearInWebView:(WKWebView *)webView
            completion:(nullable void (^)(void))completion;

+ (void)selectionTextInWebView:(WKWebView *)webView
                    completion:(void (^)(NSString *text))completion;

@end

NS_ASSUME_NONNULL_END
