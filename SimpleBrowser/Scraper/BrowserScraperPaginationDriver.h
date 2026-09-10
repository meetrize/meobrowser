#import <WebKit/WebKit.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperPaginationDriver : NSObject

+ (void)advanceInWebView:(WKWebView *)webView
              pagination:(BrowserScraperPagination *)pagination
              completion:(void (^)(BOOL advanced, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
