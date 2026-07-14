#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFaviconHTMLParser : NSObject

/// 从 HTML（最多使用前 64 KB）扫描 link[rel*=icon|apple-touch-icon]，
/// 返回绝对 URL，**按清晰度启发式降序**（sizes 大优先、apple-touch / png 加权）。
+ (NSArray<NSURL *> *)iconURLsFromHTMLData:(NSData *)data pageURL:(NSURL *)pageURL;

@end

NS_ASSUME_NONNULL_END
