#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 查看网页源代码：DOM 快照包装为只读展示页。
@interface BrowserPageSource : NSObject

/// 超过该 UTF-16 长度则截断（约 5 MB 量级字符）。
+ (NSUInteger)maxSourceLength;

/// 将 outerHTML 包装为带等宽 `<pre>` 的完整 HTML 文档，供 `loadHTMLString:` 使用。
/// @param source DOM 序列化文本；可为空。
/// @param pageTitle 原页面标题（用于文档 title）。
/// @param truncated 是否已截断。
+ (NSString *)HTMLDocumentForSource:(NSString *)source
                          pageTitle:(nullable NSString *)pageTitle
                          truncated:(BOOL)truncated;

/// 转义 HTML 特殊字符。
+ (NSString *)escapedHTMLFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
